import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llm_client.dart';

/// Google Gemini via `models/{model}:generateContent` with function calling.
class GeminiClient implements LlmClient {
  GeminiClient({
    required http.Client httpClient,
    required this.apiKey,
    required String model,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 120),
  }) : model = model.startsWith('models/') ? model.substring(7) : model,
       baseUrl = (baseUrl == null || baseUrl.isEmpty ? defaultBaseUrl : baseUrl).replaceAll(RegExp(r'/+$'), ''),
       _t = JsonTransport(httpClient, timeout: timeout);

  static const defaultBaseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  final String baseUrl;
  final String apiKey;
  final String model;
  final JsonTransport _t;

  @override
  String get providerId => 'gemini';

  Map<String, String> get _headers => {'x-goog-api-key': apiKey};

  @override
  Future<LlmResponse> chat({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
  }) async {
    final body = <String, dynamic>{
      if (system != null)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
      'contents': encodeMessages(messages),
      if (tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final t in tools) {'name': t.name, 'description': t.description, 'parameters': t.parameters},
            ],
          },
        ],
      // Thinking models spend part of this on reasoning.
      'generationConfig': {'maxOutputTokens': maxTokens < 8192 ? 8192 : maxTokens},
    };
    final res = await _t.post(Uri.parse('$baseUrl/models/$model:generateContent'), _headers, body);
    return parseResponse(res);
  }

  List<Map<String, dynamic>> encodeMessages(List<LlmMessage> messages) {
    final out = <Map<String, dynamic>>[];
    void add(String role, List<Object?> parts) {
      if (out.isNotEmpty && out.last['role'] == role) {
        (out.last['parts'] as List).addAll(parts);
      } else {
        out.add({
          'role': role,
          'parts': [...parts],
        });
      }
    }

    for (final m in messages) {
      switch (m) {
        case UserMessage(:final text):
          add('user', [
            {'text': text},
          ]);
        case AssistantMessage(:final native, :final nativeProvider, :final text, :final toolCalls):
          // Replaying our own parts keeps thought signatures intact.
          if (nativeProvider == providerId && native is List) {
            add('model', native);
          } else {
            add('model', [
              if (text.isNotEmpty) {'text': text},
              for (final c in toolCalls)
                {
                  'functionCall': {'name': c.name, 'args': c.arguments},
                },
            ]);
          }
        case ToolResultsMessage(:final results):
          add('user', [
            for (final r in results)
              {
                'functionResponse': {
                  if (!r.callId.startsWith('gemini_')) 'id': r.callId,
                  'name': r.name,
                  'response': r.isError ? {'error': r.content} : _struct(r.content),
                },
              },
          ]);
      }
    }
    return out;
  }

  /// functionResponse.response must be a JSON object.
  static Map<String, dynamic> _struct(String content) {
    try {
      final v = jsonDecode(content);
      if (v is Map<String, dynamic>) return v;
      return {'result': v};
    } on FormatException {
      return {'result': content};
    }
  }

  LlmResponse parseResponse(Map<String, dynamic> res) {
    final feedback = res['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw LlmException(LlmErrorKind.refused, '${feedback['blockReason']}');
    }
    final candidates = res['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      throw const LlmException(LlmErrorKind.invalidResponse, 'no candidates');
    }
    final cand = candidates.first as Map;
    final finish = cand['finishReason'];
    final parts = (cand['content'] as Map?)?['parts'];
    final partList = parts is List ? parts : const [];
    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final (i, p) in partList.indexed) {
      if (p is! Map) continue;
      if (p['text'] is String && p['thought'] != true) text.write(p['text']);
      final fc = p['functionCall'];
      if (fc is Map && fc['name'] is String) {
        calls.add(
          ToolCall(
            // Older models don't return ids; synthesize one (not sent back).
            id: (fc['id'] as String?) ?? 'gemini_$i',
            name: fc['name'] as String,
            arguments: decodeArgs(fc['args']),
          ),
        );
      }
    }
    if (partList.isEmpty && (finish == 'SAFETY' || finish == 'PROHIBITED_CONTENT' || finish == 'BLOCKLIST')) {
      throw LlmException(LlmErrorKind.refused, '$finish');
    }
    return LlmResponse(
      message: AssistantMessage(
        text: text.toString(),
        toolCalls: calls,
        native: List<Object?>.from(partList),
        nativeProvider: providerId,
      ),
      stop: calls.isNotEmpty
          ? LlmStop.toolUse
          : finish == 'MAX_TOKENS'
          ? LlmStop.maxTokens
          : finish == 'STOP' || finish == null
          ? LlmStop.endTurn
          : LlmStop.other,
    );
  }

  @override
  Future<List<String>> listModels() async {
    final out = <String>[];
    String? page;
    for (var i = 0; i < 5; i++) {
      final res = await _t.get(
        Uri.parse('$baseUrl/models?pageSize=200${page == null ? '' : '&pageToken=${Uri.encodeQueryComponent(page)}'}'),
        _headers,
      );
      final models = res['models'];
      if (models is List) {
        for (final m in models) {
          if (m is! Map || m['name'] is! String) continue;
          final methods = m['supportedGenerationMethods'];
          if (methods is List && !methods.contains('generateContent')) continue;
          final name = m['name'] as String;
          out.add(name.startsWith('models/') ? name.substring(7) : name);
        }
      }
      page = res['nextPageToken'] as String?;
      if (page == null || page.isEmpty) break;
    }
    return out;
  }
}
