import 'dart:async';
import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../llm_client.dart';
import 'model_catalog.dart';

/// [LlmClient] backed by a model running inside the app (LiteRT-LM via
/// flutter_edge_ai). Nothing leaves the phone. Each [chat] call opens a fresh
/// conversation, replays the transcript, and generates one turn — the same
/// stateless contract the cloud clients follow.
class OnDeviceClient implements LlmClient, LlmBudget {
  OnDeviceClient({required this.model, this.backend, this.hfToken});

  final OnDeviceModel model;

  /// Null lets LiteRT choose: GPU then CPU for a generic file, the NPU for
  /// a bundle compiled for one. Set only to force a backend.
  final PreferredBackend? backend;
  final String? hfToken;

  @override
  String get providerId => 'ondevice';

  @override
  int get contextTokens => model.contextTokens;

  @override
  bool get supportsTools => model.supportsTools;

  /// LiteRT runs one generation at a time per loaded model; queue callers.
  static Future<void> _queue = Future.value();

  @override
  Future<LlmResponse> chat({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
  }) {
    final run = _queue.then((_) => _chat(system, messages, tools, maxTokens));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<LlmResponse> _chat(String? system, List<LlmMessage> messages, List<LlmTool> tools, int maxTokens) async {
    final InferenceModel loaded;
    try {
      loaded = await load();
    } on NoActiveModelError {
      throw const LlmException(LlmErrorKind.notConfigured, 'The on-device model is not downloaded yet');
    } catch (e) {
      throw LlmException(LlmErrorKind.server, 'Could not load ${model.name}: $e');
    }
    final useTools = tools.isNotEmpty && model.supportsTools;
    final chat = await loaded.createChat(
      systemInstruction: system,
      tools: useTools ? toEdgeTools(tools) : const [],
      supportsFunctionCalls: useTools,
      modelType: model.modelType,
      // Low temperature: amounts and categories, not prose.
      temperature: 0.2,
      topK: 20,
      maxOutputTokens: maxTokens.clamp(256, model.contextTokens ~/ 2),
    );
    try {
      for (final m in toEdgeMessages(messages)) {
        await chat.addQueryChunk(m);
      }
      final response = await chat.generateChatResponse().timeout(const Duration(minutes: 3));
      return fromEdgeResponse(response);
    } on TimeoutException {
      await chat.stopGeneration();
      throw const LlmException(LlmErrorKind.timeout, 'The on-device model took too long');
    } finally {
      await chat.close();
    }
  }

  /// Loads (and if needed activates) this model. Activation of an installed
  /// file is instant — install() skips files it already has.
  Future<InferenceModel> load() async {
    final active = FlutterEdgeAi.activeModelSpec?.name;
    if (active == null || !model.file.startsWith(active)) {
      if (!await FlutterEdgeAi.isModelInstalled(model.file)) throw NoActiveModelError('${model.name} not installed');
      await FlutterEdgeAi.installModel(
        modelType: model.modelType,
        fileType: ModelFileType.litertlm,
      ).fromNetwork(model.url, token: model.gated ? hfToken : null).install();
    }
    return FlutterEdgeAi.getActiveModel(
      maxTokens: model.contextTokens,
      preferredBackend: backend,
      // Applies to the GPU path; the CPU already runs at full precision.
      activationDataType: model.f32OnGpu ? ActivationDataType.float32 : null,
    );
  }

  @override
  Future<List<String>> listModels() async {
    final installed = await FlutterEdgeAi.listInstalledModels();
    return [
      for (final m in ModelCatalog.all)
        if (installed.contains(m.file)) m.id,
    ];
  }
}

// --------------------------------------------------------------- mapping

List<Tool> toEdgeTools(List<LlmTool> tools) => [
  for (final t in tools) Tool(name: t.name, description: t.description, parameters: t.parameters),
];

/// Our provider-neutral transcript → flutter_edge_ai messages.
List<Message> toEdgeMessages(List<LlmMessage> messages) => [
  for (final m in messages)
    ...switch (m) {
      UserMessage(:final text) => [Message.text(text: text, isUser: true)],
      AssistantMessage(:final toolCalls) when toolCalls.isNotEmpty => [
        // Text written before a call is not part of it (flutter_edge_ai
        // replays only the call objects), so it is dropped here too.
        Message.toolCall(
          calls: [for (final c in toolCalls) FunctionCallResponse(name: c.name, args: c.arguments, id: c.id)],
        ),
      ],
      AssistantMessage(:final text) => [Message.text(text: text)],
      ToolResultsMessage(:final results) => [
        for (final r in results) Message.toolResponse(toolName: r.name, response: _resultMap(r), toolCallId: r.callId),
      ],
    },
];

Map<String, dynamic> _resultMap(ToolResult r) {
  Map<String, dynamic> body;
  try {
    final decoded = jsonDecode(r.content);
    body = decoded is Map<String, dynamic> ? decoded : {'result': decoded};
  } on FormatException {
    body = {'result': r.content};
  }
  return r.isError ? {'error': body} : body;
}

/// flutter_edge_ai response → our [LlmResponse]. Engines other than
/// llama.cpp give calls no id, so we number them for the tool-result pairing.
LlmResponse fromEdgeResponse(ModelResponse r) {
  List<ToolCall> calls(List<FunctionCallResponse> cs) => [
    for (final (i, c) in cs.indexed) ToolCall(id: c.id ?? 'call_$i', name: c.name, arguments: c.args),
  ];
  return switch (r) {
    TextResponse(:final token) => LlmResponse(
      message: AssistantMessage(text: token.trim()),
      stop: LlmStop.endTurn,
    ),
    FunctionCallResponse() => LlmResponse(
      message: AssistantMessage(toolCalls: calls([r])),
      stop: LlmStop.toolUse,
    ),
    ParallelFunctionCallResponse(calls: final cs) => LlmResponse(
      message: AssistantMessage(toolCalls: calls(cs)),
      stop: LlmStop.toolUse,
    ),
    ThinkingResponse() => const LlmResponse(message: AssistantMessage(), stop: LlmStop.other),
  };
}
