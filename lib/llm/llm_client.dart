import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

/// Provider-agnostic chat interface. Implementations translate to and from
/// each vendor's wire format; the rest of the app only sees these types.
abstract interface class LlmClient {
  /// Short id of the provider family, used to tag provider-native turns.
  String get providerId;

  Future<LlmResponse> chat({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
  });

  /// Model ids available to this key, for the settings picker.
  Future<List<String>> listModels();
}

// ------------------------------------------------------------------ messages

sealed class LlmMessage {
  const LlmMessage();
}

final class UserMessage extends LlmMessage {
  const UserMessage(this.text);
  final String text;
}

/// A model turn. [native] keeps the provider's own representation (e.g.
/// Anthropic content blocks incl. thinking, Gemini parts incl. thought
/// signatures) so it can be echoed back verbatim — some providers require
/// that within a tool-use loop.
final class AssistantMessage extends LlmMessage {
  const AssistantMessage({this.text = '', this.toolCalls = const [], this.native, this.nativeProvider});
  final String text;
  final List<ToolCall> toolCalls;
  final Object? native;
  final String? nativeProvider;
}

final class ToolResultsMessage extends LlmMessage {
  const ToolResultsMessage(this.results);
  final List<ToolResult> results;
}

class ToolCall {
  const ToolCall({required this.id, required this.name, required this.arguments});
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class ToolResult {
  const ToolResult({required this.callId, required this.name, required this.content, this.isError = false});
  final String callId;
  final String name;

  /// JSON (or plain text) handed back to the model.
  final String content;
  final bool isError;
}

/// A function the model may call. [parameters] is a JSON-schema object.
class LlmTool {
  const LlmTool({required this.name, required this.description, required this.parameters});
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
}

enum LlmStop { endTurn, toolUse, maxTokens, other }

class LlmResponse {
  const LlmResponse({required this.message, required this.stop});
  final AssistantMessage message;
  final LlmStop stop;

  String get text => message.text;
  List<ToolCall> get toolCalls => message.toolCalls;
}

// -------------------------------------------------------------------- errors

enum LlmErrorKind { notConfigured, auth, rateLimit, server, network, timeout, badRequest, refused, invalidResponse }

class LlmException implements Exception {
  const LlmException(this.kind, this.message, {this.statusCode});
  final LlmErrorKind kind;
  final String message;
  final int? statusCode;

  /// Worth retrying later (as opposed to a config problem).
  bool get isTransient =>
      kind == LlmErrorKind.rateLimit ||
      kind == LlmErrorKind.server ||
      kind == LlmErrorKind.network ||
      kind == LlmErrorKind.timeout;

  String get userMessage => switch (kind) {
    LlmErrorKind.notConfigured => 'Connect an LLM in Settings first.',
    LlmErrorKind.auth => 'The API key was rejected ($message).',
    LlmErrorKind.rateLimit => 'Rate limited by the provider — try again in a minute.',
    LlmErrorKind.server => 'The provider had a server error ($message).',
    LlmErrorKind.network => 'Could not reach the provider. Check the URL and your connection.',
    LlmErrorKind.timeout => 'The provider took too long to answer.',
    LlmErrorKind.badRequest => 'Request rejected: $message',
    LlmErrorKind.refused => 'The model declined to answer.',
    LlmErrorKind.invalidResponse => 'Unexpected response: $message',
  };

  @override
  String toString() => 'LlmException(${kind.name}${statusCode == null ? '' : ' $statusCode'}: $message)';
}

// ------------------------------------------------------------------- transport

/// Thin JSON-over-HTTP helper shared by the provider clients: timeouts and
/// consistent error mapping.
class JsonTransport {
  JsonTransport(this.client, {this.timeout = const Duration(seconds: 90)});

  final http.Client client;
  final Duration timeout;

  Future<Map<String, dynamic>> post(Uri uri, Map<String, String> headers, Map<String, dynamic> body) =>
      _send(() => client.post(uri, headers: {'content-type': 'application/json', ...headers}, body: jsonEncode(body)));

  Future<Map<String, dynamic>> get(Uri uri, Map<String, String> headers) =>
      _send(() => client.get(uri, headers: headers));

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() req) async {
    final http.Response res;
    try {
      res = await req().timeout(timeout);
    } on TimeoutException {
      throw const LlmException(LlmErrorKind.timeout, 'timed out');
    } on SocketException catch (e) {
      throw LlmException(LlmErrorKind.network, e.message);
    } on http.ClientException catch (e) {
      throw LlmException(LlmErrorKind.network, e.message);
    }
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // fall through
      }
      throw LlmException(LlmErrorKind.invalidResponse, _snippet(text), statusCode: res.statusCode);
    }
    final detail = _errorDetail(text);
    final kind = switch (res.statusCode) {
      401 || 403 => LlmErrorKind.auth,
      429 => LlmErrorKind.rateLimit,
      408 => LlmErrorKind.timeout,
      >= 500 => LlmErrorKind.server,
      _ => LlmErrorKind.badRequest,
    };
    throw LlmException(kind, detail, statusCode: res.statusCode);
  }

  static String _errorDetail(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final e = j['error'];
        if (e is Map && e['message'] is String) return e['message'] as String;
        if (e is String) return e;
        if (j['message'] is String) return j['message'] as String;
      }
      if (j is List && j.isNotEmpty && j.first is Map) return _errorDetail(jsonEncode(j.first));
    } catch (_) {}
    return _snippet(body);
  }

  static String _snippet(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
}

/// Decodes tool-call arguments that may arrive as a JSON string or a map.
Map<String, dynamic> decodeArgs(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final v = jsonDecode(raw);
      if (v is Map) return v.cast<String, dynamic>();
    } on FormatException {
      return {'_raw': raw};
    }
  }
  return {};
}
