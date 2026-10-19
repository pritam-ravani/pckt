import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/llm/llm_client.dart';
import 'package:pckt/llm/llm_config.dart';
import 'package:pckt/llm/on_device/model_catalog.dart';
import 'package:pckt/llm/on_device/on_device_client.dart';
import 'package:http/http.dart' as http;

void main() {
  test('agent transcript maps to flutter_edge_ai messages', () {
    final msgs = toEdgeMessages([
      const UserMessage('How much on food?'),
      const AssistantMessage(
        text: 'Let me check.',
        toolCalls: [
          ToolCall(id: 'call_0', name: 'spending_summary', arguments: {'group_by': 'category'}),
        ],
      ),
      const ToolResultsMessage([
        ToolResult(callId: 'call_0', name: 'spending_summary', content: '{"total":"₹4,200"}'),
        ToolResult(callId: 'call_1', name: 'list_accounts', content: 'plain text', isError: true),
      ]),
      const AssistantMessage(text: 'You spent ₹4,200.'),
    ]);

    expect(msgs.map((m) => m.type), [
      MessageType.text,
      MessageType.toolCall,
      MessageType.toolResponse,
      MessageType.toolResponse,
      MessageType.text,
    ]);
    expect(msgs[0].isUser, isTrue);
    expect(msgs[1].toolCalls.single.name, 'spending_summary');
    expect(msgs[1].toolCalls.single.args, {'group_by': 'category'});
    expect(msgs[2].toolName, 'spending_summary');
    expect(jsonDecode(msgs[2].text), {'total': '₹4,200'});
    expect(jsonDecode(msgs[3].text), {
      'error': {'result': 'plain text'},
    });
    expect(msgs[4].isUser, isFalse);
  });

  test('responses map back, numbering id-less tool calls', () {
    final text = fromEdgeResponse(const TextResponse('  Done. '));
    expect(text.text, 'Done.');
    expect(text.stop, LlmStop.endTurn);

    final one = fromEdgeResponse(const FunctionCallResponse(name: 'list_categories', args: {}));
    expect(one.stop, LlmStop.toolUse);
    expect(one.toolCalls.single.id, 'call_0');

    final many = fromEdgeResponse(
      const ParallelFunctionCallResponse(
        calls: [
          FunctionCallResponse(name: 'a', args: {'x': 1}),
          FunctionCallResponse(name: 'b', args: {}, id: 'given'),
        ],
      ),
    );
    expect(many.toolCalls.map((c) => c.id), ['call_0', 'given']);
    expect(many.toolCalls.first.arguments, {'x': 1});
  });

  test('tools keep their JSON schema', () {
    final t = toEdgeTools([
      const LlmTool(
        name: 'query_transactions',
        description: 'Find transactions',
        parameters: {'type': 'object', 'properties': {}},
      ),
    ]).single;
    expect(t.name, 'query_transactions');
    expect(t.parameters['type'], 'object');
  });

  test('on-device preset builds an OnDeviceClient that advertises its budget', () {
    final client = buildLlmClient(
      preset: LlmPresets.byId('ondevice'),
      baseUrl: '',
      model: ModelCatalog.gemma3_1b.id,
      apiKey: 'hf_token',
      httpClient: http.Client(),
    );
    expect(client, isA<OnDeviceClient>());
    expect((client as LlmBudget).supportsTools, isFalse);
    expect((client as LlmBudget).contextTokens, 2048);
    expect((client as OnDeviceClient).hfToken, 'hf_token');

    expect(
      () => buildLlmClient(
        preset: LlmPresets.byId('ondevice'),
        baseUrl: '',
        model: 'unknown',
        apiKey: null,
        httpClient: http.Client(),
      ),
      throwsA(isA<LlmException>()),
    );
  });
}
