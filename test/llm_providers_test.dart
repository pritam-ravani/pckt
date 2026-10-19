import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pckt/llm/llm_client.dart';
import 'package:pckt/llm/providers/anthropic_client.dart';
import 'package:pckt/llm/providers/gemini_client.dart';
import 'package:pckt/llm/providers/openai_client.dart';

const _tool = LlmTool(
  name: 'spending_summary',
  description: 'Totals',
  parameters: {
    'type': 'object',
    'properties': {
      'group_by': {'type': 'string'},
    },
    'required': ['group_by'],
  },
);

/// Records requests and replies with queued JSON bodies.
class _Recorder {
  final requests = <http.Request>[];
  final replies = <(int, Object)>[];

  MockClient get client => MockClient((req) async {
    requests.add(req);
    final (status, body) = replies.removeAt(0);
    return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
  });

  Map<String, dynamic> body(int i) => jsonDecode(requests[i].body) as Map<String, dynamic>;
}

void main() {
  group('OpenAI-compatible', () {
    test('request shape, tool call parsing and tool result round trip', () async {
      final r = _Recorder()
        ..replies.add((
          200,
          {
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {'name': 'spending_summary', 'arguments': '{"group_by":"category"}'},
                    },
                  ],
                },
              },
            ],
          },
        ))
        ..replies.add((
          200,
          {
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'role': 'assistant', 'content': 'You spent **₹1,200**.'},
              },
            ],
          },
        ));
      final c = OpenAiCompatibleClient(
        httpClient: r.client,
        baseUrl: 'https://openrouter.ai/api/v1/',
        model: 'm',
        apiKey: 'sk-1',
      );

      final first = await c.chat(system: 'sys', messages: const [UserMessage('hi')], tools: const [_tool]);
      expect(r.requests[0].url.toString(), 'https://openrouter.ai/api/v1/chat/completions');
      expect(r.requests[0].headers['authorization'], 'Bearer sk-1');
      final b0 = r.body(0);
      expect(b0['model'], 'm');
      expect(b0['max_tokens'], 4096);
      expect(b0['messages'][0], {'role': 'system', 'content': 'sys'});
      expect(b0['tools'][0]['type'], 'function');
      expect(b0['tools'][0]['function']['name'], 'spending_summary');
      expect(b0['tools'][0]['function']['parameters']['required'], ['group_by']);

      expect(first.stop, LlmStop.toolUse);
      expect(first.toolCalls.single.id, 'call_1');
      expect(first.toolCalls.single.arguments, {'group_by': 'category'});

      final second = await c.chat(
        messages: [
          const UserMessage('hi'),
          first.message,
          const ToolResultsMessage([ToolResult(callId: 'call_1', name: 'spending_summary', content: '{"total":1200}')]),
        ],
        tools: const [_tool],
      );
      final msgs = r.body(1)['messages'] as List;
      expect(msgs[1]['role'], 'assistant');
      expect(msgs[1]['tool_calls'][0]['function']['arguments'], '{"group_by":"category"}');
      expect(msgs[2], {'role': 'tool', 'tool_call_id': 'call_1', 'content': '{"total":1200}'});
      expect(second.text, 'You spent **₹1,200**.');
      expect(second.stop, LlmStop.endTurn);
    });

    test('OpenAI host uses max_completion_tokens; local servers need no key', () async {
      final r = _Recorder()
        ..replies.add((
          200,
          {
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': 'ok'},
              },
            ],
          },
        ))
        ..replies.add((
          200,
          {
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': 'ok'},
              },
            ],
          },
        ));
      await OpenAiCompatibleClient(
        httpClient: r.client,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt',
        apiKey: 'k',
      ).chat(messages: const [UserMessage('x')]);
      expect(r.body(0).containsKey('max_completion_tokens'), isTrue);
      expect(r.body(0).containsKey('max_tokens'), isFalse);
      expect(r.body(0).containsKey('tools'), isFalse);

      await OpenAiCompatibleClient(
        httpClient: r.client,
        baseUrl: 'http://192.168.1.5:11434/v1',
        model: 'qwen3',
      ).chat(messages: const [UserMessage('x')]);
      expect(r.requests[1].headers.containsKey('authorization'), isFalse);
    });

    test('lists models and maps errors', () async {
      final r = _Recorder()
        ..replies.add((
          200,
          {
            'data': [
              {'id': 'b-model'},
              {'id': 'a-model'},
            ],
          },
        ))
        ..replies.add((
          401,
          {
            'error': {'message': 'Incorrect API key'},
          },
        ))
        ..replies.add((
          429,
          {
            'error': {'message': 'slow down'},
          },
        ))
        ..replies.add((503, {'error': 'overloaded'}));
      final c = OpenAiCompatibleClient(httpClient: r.client, baseUrl: 'https://x.ai/v1', model: 'm', apiKey: 'k');
      expect(await c.listModels(), ['a-model', 'b-model']);
      expect(r.requests[0].url.path, '/v1/models');
      Future<LlmErrorKind> kind() async {
        try {
          await c.chat(messages: const [UserMessage('x')]);
        } on LlmException catch (e) {
          return e.kind;
        }
        fail('expected an error');
      }

      expect(await kind(), LlmErrorKind.auth);
      expect(await kind(), LlmErrorKind.rateLimit);
      expect(await kind(), LlmErrorKind.server);
    });
  });

  group('Anthropic', () {
    test('request shape, tool_use parsing and verbatim echo of content blocks', () async {
      final firstContent = [
        {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
        {'type': 'text', 'text': 'Let me check.'},
        {
          'type': 'tool_use',
          'id': 'toolu_1',
          'name': 'spending_summary',
          'input': {'group_by': 'merchant'},
        },
      ];
      final r = _Recorder()
        ..replies.add((200, {'stop_reason': 'tool_use', 'content': firstContent}))
        ..replies.add((
          200,
          {
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'Done.'},
            ],
          },
        ));
      final c = AnthropicClient(httpClient: r.client, apiKey: 'sk-ant', model: 'claude-opus-5-5');

      final first = await c.chat(system: 'sys', messages: const [UserMessage('hi')], tools: const [_tool]);
      final req = r.requests[0];
      expect(req.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(req.headers['x-api-key'], 'sk-ant');
      expect(req.headers['anthropic-version'], '2023-06-01');
      final b = r.body(0);
      expect(b['model'], 'claude-opus-5-5');
      expect(b['system'], 'sys');
      expect(b['max_tokens'], greaterThanOrEqualTo(16000));
      expect(b['tools'][0]['input_schema']['type'], 'object');
      expect(b['messages'][0]['role'], 'user');

      expect(first.stop, LlmStop.toolUse);
      expect(first.text, 'Let me check.');
      expect(first.toolCalls.single.id, 'toolu_1');
      expect(first.toolCalls.single.arguments, {'group_by': 'merchant'});

      final second = await c.chat(
        messages: [
          const UserMessage('hi'),
          first.message,
          const ToolResultsMessage([ToolResult(callId: 'toolu_1', name: 'spending_summary', content: '{}')]),
        ],
        tools: const [_tool],
      );
      final msgs = r.body(1)['messages'] as List;
      expect(msgs[1], {'role': 'assistant', 'content': firstContent}); // thinking block preserved
      expect(msgs[2]['role'], 'user');
      expect(msgs[2]['content'][0], {'type': 'tool_result', 'tool_use_id': 'toolu_1', 'content': '{}'});
      expect(second.text, 'Done.');
    });

    test('refusal and model listing', () async {
      final r = _Recorder()
        ..replies.add((200, {'stop_reason': 'refusal', 'content': <Object>[]}))
        ..replies.add((
          200,
          {
            'data': [
              {'id': 'claude-opus-5-5'},
              {'id': 'claude-haiku-4-5'},
            ],
          },
        ));
      final c = AnthropicClient(httpClient: r.client, apiKey: 'k', model: 'claude-haiku-4-5');
      await expectLater(
        c.chat(messages: const [UserMessage('x')]),
        throwsA(isA<LlmException>().having((e) => e.kind, 'kind', LlmErrorKind.refused)),
      );
      expect(r.body(0).containsKey('fallbacks'), isFalse); // only for models that support it
      expect(await c.listModels(), ['claude-opus-5-5', 'claude-haiku-4-5']);
      expect(r.requests[1].url.path, '/v1/models');
    });
  });

  group('Gemini', () {
    test('request shape, functionCall parsing and functionResponse', () async {
      final parts = [
        {
          'functionCall': {
            'name': 'spending_summary',
            'args': {'group_by': 'month'},
          },
          'thoughtSignature': 'abc',
        },
      ];
      final r = _Recorder()
        ..replies.add((
          200,
          {
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {'role': 'model', 'parts': parts},
              },
            ],
          },
        ))
        ..replies.add((
          200,
          {
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'role': 'model',
                  'parts': [
                    {'text': 'thinking…', 'thought': true},
                    {'text': 'Answer'},
                  ],
                },
              },
            ],
          },
        ));
      final c = GeminiClient(httpClient: r.client, apiKey: 'g-key', model: 'models/gemini-2.5-flash');

      final first = await c.chat(system: 'sys', messages: const [UserMessage('hi')], tools: const [_tool]);
      expect(
        r.requests[0].url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
      );
      expect(r.requests[0].headers['x-goog-api-key'], 'g-key');
      final b = r.body(0);
      expect(b['systemInstruction']['parts'][0]['text'], 'sys');
      expect(b['contents'][0], {
        'role': 'user',
        'parts': [
          {'text': 'hi'},
        ],
      });
      expect(b['tools'][0]['functionDeclarations'][0]['name'], 'spending_summary');
      expect(first.toolCalls.single.name, 'spending_summary');
      expect(first.toolCalls.single.arguments, {'group_by': 'month'});
      expect(first.stop, LlmStop.toolUse);

      final second = await c.chat(
        messages: [
          const UserMessage('hi'),
          first.message,
          ToolResultsMessage([
            ToolResult(callId: first.toolCalls.single.id, name: 'spending_summary', content: '{"total":5}'),
          ]),
        ],
        tools: const [_tool],
      );
      final contents = r.body(1)['contents'] as List;
      expect(contents[1], {'role': 'model', 'parts': parts}); // thought signature echoed
      expect(contents[2]['parts'][0]['functionResponse'], {
        'name': 'spending_summary',
        'response': {'total': 5},
      });
      expect(second.text, 'Answer');
    });

    test('lists only generateContent models', () async {
      final r = _Recorder()
        ..replies.add((
          200,
          {
            'models': [
              {
                'name': 'models/gemini-2.5-flash',
                'supportedGenerationMethods': ['generateContent', 'countTokens'],
              },
              {
                'name': 'models/text-embedding-004',
                'supportedGenerationMethods': ['embedContent'],
              },
            ],
          },
        ));
      final c = GeminiClient(httpClient: r.client, apiKey: 'k', model: 'x');
      expect(await c.listModels(), ['gemini-2.5-flash']);
      expect(r.requests[0].headers['x-goog-api-key'], 'k');
    });
  });
}
