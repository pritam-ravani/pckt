import 'package:http/http.dart' as http;

import '../llm_client.dart';

/// Claude via the Messages API (`POST /v1/messages`), raw HTTP — there is
/// no official Dart SDK.
class AnthropicClient implements LlmClient {
  AnthropicClient({
    required http.Client httpClient,
    required this.apiKey,
    required this.model,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 120),
  }) : baseUrl = (baseUrl == null || baseUrl.isEmpty ? defaultBaseUrl : baseUrl).replaceAll(RegExp(r'/+$'), ''),
       _t = JsonTransport(httpClient, timeout: timeout);

  static const defaultBaseUrl = 'https://api.anthropic.com';
  static const apiVersion = '2023-06-01';

  /// Models that accept server-side refusal fallbacks (`fallbacks: "default"`):
  /// if a safety classifier declines, the API retries on a suitable model.
  static const _fallbackModels = {'claude-opus-5-5', 'claude-opus-5', 'claude-sonnet-5-5', 'claude-fable-5-1'};
  static const _fallbackBeta = 'server-side-fallback-2026-07-01';

  /// Current models think adaptively and the thinking counts toward
  /// `max_tokens`, so never send a tiny budget.
  static const _minMaxTokens = 16000;

  final String baseUrl;
  final String apiKey;
  final String model;
  final JsonTransport _t;

  @override
  String get providerId => 'anthropic';

  bool get _fallbacks => _fallbackModels.contains(model);

  Map<String, String> get _headers => {
    'x-api-key': apiKey,
    'anthropic-version': apiVersion,
    if (_fallbacks) 'anthropic-beta': _fallbackBeta,
  };

  @override
  Future<LlmResponse> chat({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens < _minMaxTokens ? _minMaxTokens : maxTokens,
      'system': ?system,
      'messages': encodeMessages(messages),
      if (tools.isNotEmpty)
        'tools': [
          for (final t in tools) {'name': t.name, 'description': t.description, 'input_schema': t.parameters},
        ],
      if (_fallbacks) 'fallbacks': 'default',
    };
    final res = await _t.post(Uri.parse('$baseUrl/v1/messages'), _headers, body);
    return parseResponse(res);
  }

  /// Consecutive same-role turns are merged so the history always alternates.
  List<Map<String, dynamic>> encodeMessages(List<LlmMessage> messages) {
    final out = <Map<String, dynamic>>[];
    void add(String role, List<Object?> blocks) {
      if (out.isNotEmpty && out.last['role'] == role) {
        (out.last['content'] as List).addAll(blocks);
      } else {
        out.add({
          'role': role,
          'content': [...blocks],
        });
      }
    }

    for (final m in messages) {
      switch (m) {
        case UserMessage(:final text):
          add('user', [
            {'type': 'text', 'text': text},
          ]);
        case AssistantMessage(:final native, :final nativeProvider, :final text, :final toolCalls):
          // Echo our own content blocks back unchanged (thinking blocks must
          // be replayed verbatim within a tool-use loop).
          if (nativeProvider == providerId && native is List) {
            add('assistant', native);
          } else {
            add('assistant', [
              if (text.isNotEmpty) {'type': 'text', 'text': text},
              for (final c in toolCalls) {'type': 'tool_use', 'id': c.id, 'name': c.name, 'input': c.arguments},
            ]);
          }
        case ToolResultsMessage(:final results):
          add('user', [
            for (final r in results)
              {'type': 'tool_result', 'tool_use_id': r.callId, 'content': r.content, if (r.isError) 'is_error': true},
          ]);
      }
    }
    return out;
  }

  LlmResponse parseResponse(Map<String, dynamic> res) {
    final stop = res['stop_reason'];
    if (stop == 'refusal') throw const LlmException(LlmErrorKind.refused, 'refusal');
    final content = res['content'];
    if (content is! List) throw const LlmException(LlmErrorKind.invalidResponse, 'missing content');
    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final b in content) {
      if (b is! Map) continue;
      switch (b['type']) {
        case 'text':
          text.write(b['text'] ?? '');
        case 'tool_use':
          calls.add(ToolCall(id: b['id'] as String, name: b['name'] as String, arguments: decodeArgs(b['input'])));
      }
    }
    return LlmResponse(
      message: AssistantMessage(
        text: text.toString(),
        toolCalls: calls,
        native: List<Object?>.from(content),
        nativeProvider: providerId,
      ),
      stop: switch (stop) {
        'tool_use' => LlmStop.toolUse,
        'end_turn' || 'stop_sequence' => LlmStop.endTurn,
        'max_tokens' => LlmStop.maxTokens,
        _ => calls.isNotEmpty ? LlmStop.toolUse : LlmStop.other,
      },
    );
  }

  @override
  Future<List<String>> listModels() async {
    final res = await _t.get(Uri.parse('$baseUrl/v1/models?limit=100'), {
      'x-api-key': apiKey,
      'anthropic-version': apiVersion,
    });
    final data = res['data'];
    if (data is! List) return const [];
    return [
      for (final m in data)
        if (m is Map && m['id'] is String) m['id'] as String,
    ];
  }
}
