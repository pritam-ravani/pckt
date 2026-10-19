import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llm_client.dart';

/// OpenAI Chat Completions and everything that speaks it: OpenAI,
/// OpenRouter, Groq, DeepSeek, Ollama (`/v1`), LM Studio, vLLM…
class OpenAiCompatibleClient implements LlmClient {
  OpenAiCompatibleClient({
    required http.Client httpClient,
    required String baseUrl,
    required this.model,
    this.apiKey,
    Duration timeout = const Duration(seconds: 90),
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _t = JsonTransport(httpClient, timeout: timeout);

  final String baseUrl;
  final String model;
  final String? apiKey;
  final JsonTransport _t;

  @override
  String get providerId => 'openai';

  Map<String, String> get _headers => {
    if (apiKey != null && apiKey!.isNotEmpty) 'authorization': 'Bearer $apiKey',
    // OpenRouter shows this in its dashboard; other providers ignore it.
    'x-title': 'Pckt',
  };

  /// OpenAI's own API wants `max_completion_tokens` (reasoning models reject
  /// `max_tokens`); most compatible servers only understand `max_tokens`.
  bool get _isOpenAi => Uri.tryParse(baseUrl)?.host == 'api.openai.com';

  @override
  Future<LlmResponse> chat({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': [
        if (system != null) {'role': 'system', 'content': system},
        for (final m in messages) ..._encode(m),
      ],
      if (tools.isNotEmpty)
        'tools': [
          for (final t in tools)
            {
              'type': 'function',
              'function': {'name': t.name, 'description': t.description, 'parameters': t.parameters},
            },
        ],
      _isOpenAi ? 'max_completion_tokens' : 'max_tokens': maxTokens,
    };
    final res = await _t.post(Uri.parse('$baseUrl/chat/completions'), _headers, body);
    return parseResponse(res);
  }

  static List<Map<String, dynamic>> _encode(LlmMessage m) => switch (m) {
    UserMessage(:final text) => [
      {'role': 'user', 'content': text},
    ],
    AssistantMessage(:final text, :final toolCalls) => [
      {
        'role': 'assistant',
        'content': text.isEmpty && toolCalls.isNotEmpty ? null : text,
        if (toolCalls.isNotEmpty)
          'tool_calls': [
            for (final c in toolCalls)
              {
                'id': c.id,
                'type': 'function',
                'function': {'name': c.name, 'arguments': jsonEncode(c.arguments)},
              },
          ],
      },
    ],
    ToolResultsMessage(:final results) => [
      for (final r in results) {'role': 'tool', 'tool_call_id': r.callId, 'content': r.content},
    ],
  };

  static LlmResponse parseResponse(Map<String, dynamic> res) {
    final choices = res['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw LlmException(LlmErrorKind.invalidResponse, 'no choices in response');
    }
    final choice = choices.first as Map;
    final msg = (choice['message'] as Map?) ?? const {};
    final calls = <ToolCall>[];
    final rawCalls = msg['tool_calls'];
    if (rawCalls is List) {
      for (final (i, c) in rawCalls.indexed) {
        if (c is! Map) continue;
        final fn = c['function'];
        if (fn is! Map || fn['name'] is! String) continue;
        calls.add(
          ToolCall(
            id: (c['id'] as String?) ?? 'call_$i',
            name: fn['name'] as String,
            arguments: decodeArgs(fn['arguments']),
          ),
        );
      }
    }
    final content = msg['content'];
    final text = content is String
        ? content
        : content is List
        ? content.whereType<Map>().map((p) => p['text']).whereType<String>().join()
        : '';
    final finish = choice['finish_reason'];
    if (finish == 'content_filter' && calls.isEmpty && text.isEmpty) {
      throw const LlmException(LlmErrorKind.refused, 'content_filter');
    }
    return LlmResponse(
      message: AssistantMessage(text: text, toolCalls: calls),
      stop: calls.isNotEmpty
          ? LlmStop.toolUse
          : finish == 'length'
          ? LlmStop.maxTokens
          : finish == 'stop' || finish == null
          ? LlmStop.endTurn
          : LlmStop.other,
    );
  }

  @override
  Future<List<String>> listModels() async {
    final res = await _t.get(Uri.parse('$baseUrl/models'), _headers);
    final data = res['data'] ?? res['models'];
    if (data is! List) return const [];
    return [
      for (final m in data)
        if (m is Map && m['id'] is String) m['id'] as String,
    ]..sort();
  }
}
