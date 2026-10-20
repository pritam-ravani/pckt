import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../llm_client.dart';
import 'model_catalog.dart';
import 'on_device_scheduler.dart';

void onDeviceLog(String message) => debugPrint('[pckt-ondevice] $message');

/// [LlmClient] backed by a model running inside the app (LiteRT-LM via
/// flutter_edge_ai). Nothing leaves the phone.
///
/// The contract is the same stateless one the cloud clients follow (each
/// call gets the whole transcript), but the work behind it is not repeated:
///
/// * The loaded model stays warm in [OnDeviceRuntime] between calls and is
///   unloaded after [OnDeviceRuntime.idleUnload] of disuse or on memory
///   pressure.
/// * The LiteRT conversation of the previous call is kept. When the next
///   call's transcript extends it (same system prompt and tools, earlier
///   messages identical), only the new messages — usually just tool results
///   — are fed to it, so the model never re-reads the system prompt, tool
///   schemas and earlier turns. Anything else starts a fresh conversation.
/// * Calls go through a priority queue: the user's Ask requests run before,
///   and preempt, background jobs (see [OnDeviceScheduler]).
class OnDeviceClient implements LlmClient, LlmBudget, LlmStreamingClient {
  OnDeviceClient({required this.model, this.backend, this.hfToken, this.priority = OnDevicePriority.interactive});

  final OnDeviceModel model;

  /// Null lets LiteRT choose: GPU then CPU for a generic file, the NPU for
  /// a bundle compiled for one. Set only to force a backend.
  final PreferredBackend? backend;
  final String? hfToken;
  final OnDevicePriority priority;

  /// The same model for batch work: queued behind, and stopped for, Ask.
  OnDeviceClient background() =>
      OnDeviceClient(model: model, backend: backend, hfToken: hfToken, priority: OnDevicePriority.background);

  static final runtime = OnDeviceRuntime();

  @override
  String get providerId => 'ondevice';

  @override
  int get contextTokens => model.contextTokens;

  @override
  bool get supportsTools => model.supportsTools;

  @override
  Future<LlmResponse> chat({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
  }) => runtime.generate(this, system, messages, tools, maxTokens, null);

  @override
  Future<LlmResponse> chatStreaming({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
    required void Function(String textSoFar) onText,
  }) => runtime.generate(this, system, messages, tools, maxTokens, onText);

  /// Loads (and if needed activates) this model. Activation of an installed
  /// file is instant — install() skips files it already has. flutter_edge_ai
  /// caches the built model per spec + parameters, so with the same
  /// arguments this returns the already-loaded instance.
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

// --------------------------------------------------------------- runtime

class _LiveChat {
  _LiveChat(this.chat, this.model, this.signature, this.committed);
  final InferenceChat chat;
  final InferenceModel model;
  final String signature;

  /// The transcript the conversation holds, ending with our last answer.
  final List<LlmMessage> committed;
}

/// Process-wide state for the on-device model: the queue, the loaded model
/// and the live conversation. Shared by every [OnDeviceClient].
class OnDeviceRuntime with WidgetsBindingObserver {
  OnDeviceRuntime({this.idleUnload = const Duration(minutes: 3)}) {
    scheduler = OnDeviceScheduler(idleAfter: idleUnload, onIdle: () => unload('idle ${idleUnload.inMinutes} min'));
  }

  final Duration idleUnload;
  late final OnDeviceScheduler scheduler;
  InferenceModel? _model;
  String? _modelId;
  _LiveChat? _live;
  var _attached = false;

  /// True while a model is loaded (the next answer starts without the
  /// ~30–60 s load).
  bool get isWarm => _model != null && !_model!.isClosed;

  /// Background work should yield: an Ask request is running or queued.
  bool get interactivePending => scheduler.interactivePending;

  /// Unload on memory pressure / app teardown. Call once at startup.
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didHaveMemoryPressure() => unawaited(unload('memory pressure'));

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) unawaited(unload('app detached'));
  }

  /// Frees the model (2–4 GB) unless something is using it; with [force],
  /// waits for the current job instead.
  Future<void> unload(String reason, {bool force = false}) async {
    if ((!force && scheduler.busy) || (_model == null && _live == null)) return;
    await scheduler.run(OnDevicePriority.background, (_) async {
      await _closeLive();
      final m = _model;
      _model = null;
      _modelId = null;
      if (m != null && !m.isClosed) {
        final sw = Stopwatch()..start();
        await m.close();
        onDeviceLog('unloaded the model ($reason) in ${sw.elapsedMilliseconds} ms');
      }
    });
  }

  Future<void> _closeLive() async {
    final live = _live;
    _live = null;
    if (live != null) {
      try {
        await live.chat.close();
      } catch (_) {}
    }
  }

  Future<LlmResponse> generate(
    OnDeviceClient c,
    String? system,
    List<LlmMessage> messages,
    List<LlmTool> tools,
    int maxTokens,
    void Function(String)? onText,
  ) {
    final queued = Stopwatch()..start();
    return scheduler.run(c.priority, (run) async {
      final waited = queued.elapsedMilliseconds;
      final tag = c.priority.name;
      final total = Stopwatch()..start();

      final InferenceModel loaded;
      try {
        loaded = await _load(c);
      } on NoActiveModelError {
        throw const LlmException(LlmErrorKind.notConfigured, 'The on-device model is not downloaded yet');
      } on LlmException {
        rethrow;
      } catch (e) {
        throw LlmException(LlmErrorKind.server, 'Could not load ${c.model.name}: $e');
      }
      final loadMs = total.elapsedMilliseconds;
      if (run.preempted) throw const OnDevicePreempted();

      final useTools = tools.isNotEmpty && c.model.supportsTools;
      final maxOut = maxTokens.clamp(256, c.model.contextTokens ~/ 2);
      final signature = conversationSignature(c.model.id, system, useTools ? tools : const [], maxOut);

      final live = _live;
      _live = null; // re-set only after a clean turn
      var delta = live != null && identical(live.model, loaded)
          ? continuationOf(live.committed, messages, sameSignature: live.signature == signature)
          : null;
      final InferenceChat chat;
      if (delta != null) {
        chat = live!.chat;
      } else {
        if (live != null) {
          try {
            await live.chat.close();
          } catch (_) {}
        }
        chat = await loaded.createChat(
          systemInstruction: system,
          tools: useTools ? toEdgeTools(tools) : const [],
          supportsFunctionCalls: useTools,
          modelType: c.model.modelType,
          // Low temperature: amounts and categories, not prose.
          temperature: 0.2,
          topK: 20,
          maxOutputTokens: maxOut,
        );
        delta = compactForReplay(messages);
      }
      final sessionMs = total.elapsedMilliseconds - loadMs;

      try {
        for (final m in toEdgeMessages(delta)) {
          await chat.addQueryChunk(m);
        }
        final timeout = onDeviceTurnTimeout(modelBytes: c.model.sizeBytes, priority: c.priority);
        final (res, stats) = await _collect(chat, timeout, onText, run);
        _live = _LiveChat(chat, loaded, signature, [...messages, res.message]);
        onDeviceLog(
          '$tag turn: queue ${waited}ms, load ${loadMs}ms${isWarm && loadMs < 500 ? ' (warm)' : ''}, '
          '${live != null && identical(live.chat, chat) ? 'reused conversation (+${delta.length} msg)' : 'new conversation (${delta.length} msg)'} ${sessionMs}ms, '
          'prefill ${stats.firstChunkMs ?? '-'}ms, decode ${stats.decodeMs}ms, ${stats.chars} chars, '
          '${res.toolCalls.isEmpty ? 'answer' : '${res.toolCalls.length} tool call(s)'}, total ${total.elapsedMilliseconds}ms',
        );
        return res;
      } catch (e) {
        try {
          await chat.close();
        } catch (_) {}
        if (e is OnDevicePreempted) {
          onDeviceLog('$tag turn preempted by an Ask request after ${total.elapsedMilliseconds}ms');
        } else if (e is LlmException && e.kind == LlmErrorKind.timeout) {
          onDeviceLog('$tag turn TIMED OUT after ${total.elapsedMilliseconds}ms (load ${loadMs}ms)');
        } else {
          onDeviceLog('$tag turn failed after ${total.elapsedMilliseconds}ms: $e');
        }
        if (e is LlmException) rethrow;
        throw LlmException(LlmErrorKind.server, '${c.model.name} failed: $e');
      }
    });
  }

  Future<InferenceModel> _load(OnDeviceClient c) async {
    final sw = Stopwatch()..start();
    final previous = _model;
    if (_modelId != null && _modelId != c.model.id) await _closeLive();
    final m = await c.load().timeout(
      const Duration(minutes: 4),
      onTimeout: () => throw const LlmException(LlmErrorKind.timeout, 'Loading the on-device model took too long'),
    );
    if (!identical(m, previous)) {
      // A new instance means flutter_edge_ai built (and loaded) the model.
      await _closeLive();
      onDeviceLog('loaded ${c.model.name} in ${sw.elapsedMilliseconds}ms (backend ${m.activeBackend?.name ?? '?'})');
    }
    _model = m;
    _modelId = c.model.id;
    return m;
  }

  Future<(LlmResponse, _TurnStats)> _collect(
    InferenceChat chat,
    Duration timeout,
    void Function(String)? onText,
    OnDeviceRun run,
  ) async {
    final sw = Stopwatch()..start();
    final text = StringBuffer();
    final calls = <FunctionCallResponse>[];
    int? firstChunkMs;
    var timedOut = false;
    final done = Completer<void>();
    run.onPreempt(chat.stopGeneration);

    late final StreamSubscription<ModelResponse> sub;
    sub = chat.generateChatResponseAsync().listen(
      (r) {
        firstChunkMs ??= sw.elapsedMilliseconds;
        switch (r) {
          case TextResponse(:final token):
            text.write(token);
            if (onText != null && calls.isEmpty) onText(text.toString());
          case FunctionCallResponse():
            calls.add(r);
          case ParallelFunctionCallResponse(calls: final cs):
            calls.addAll(cs);
          case ThinkingResponse():
            break;
        }
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    // Stop the model when the budget runs out; if it doesn't wind down
    // promptly, give up on the stream anyway.
    final timer = Timer(timeout, () {
      timedOut = true;
      unawaited(chat.stopGeneration().catchError((_) {}));
      Timer(const Duration(seconds: 15), () {
        if (!done.isCompleted) {
          unawaited(sub.cancel());
          done.complete();
        }
      });
    });
    try {
      await done.future;
    } catch (e) {
      if (!timedOut && !run.preempted) rethrow;
    } finally {
      timer.cancel();
      run.onPreempt(null);
    }
    if (run.preempted) throw const OnDevicePreempted();
    if (timedOut) throw const LlmException(LlmErrorKind.timeout, 'The on-device model took too long');

    final stats = _TurnStats(firstChunkMs, sw.elapsedMilliseconds - (firstChunkMs ?? 0), text.length);
    if (calls.isNotEmpty) {
      return (
        LlmResponse(
          message: AssistantMessage(
            toolCalls: [
              for (final (i, c) in calls.indexed) ToolCall(id: c.id ?? 'call_$i', name: c.name, arguments: c.args),
            ],
          ),
          stop: LlmStop.toolUse,
        ),
        stats,
      );
    }
    return (LlmResponse(message: AssistantMessage(text: text.toString().trim()), stop: LlmStop.endTurn), stats);
  }
}

class _TurnStats {
  const _TurnStats(this.firstChunkMs, this.decodeMs, this.chars);
  final int? firstChunkMs;
  final int decodeMs;
  final int chars;
}

// --------------------------------------------------------------- helpers

/// Identifies what a LiteRT conversation was created with.
String conversationSignature(String modelId, String? system, List<LlmTool> tools, int maxOutputTokens) => jsonEncode([
  modelId,
  system,
  maxOutputTokens,
  for (final t in tools) [t.name, t.description, t.parameters],
]);

/// The messages to feed a live conversation that already holds [committed],
/// or null when [next] doesn't simply extend it (then a new conversation
/// replays everything). Compared by identity: the agent passes back the very
/// objects it got.
List<LlmMessage>? continuationOf(List<LlmMessage> committed, List<LlmMessage> next, {required bool sameSignature}) {
  if (!sameSignature || committed.isEmpty || next.length <= committed.length) return null;
  for (var i = 0; i < committed.length; i++) {
    if (!identical(committed[i], next[i])) return null;
  }
  final delta = next.sublist(committed.length);
  // New model turns can't be injected into a live conversation.
  if (delta.any((m) => m is AssistantMessage)) return null;
  return delta;
}

/// A new conversation gets the transcript as one prompt, so for earlier
/// questions keep just the question and the final answer; the current
/// question keeps its tool calls and results.
List<LlmMessage> compactForReplay(List<LlmMessage> messages) {
  final lastUser = messages.lastIndexWhere((m) => m is UserMessage);
  if (lastUser <= 0) return messages;
  return [
    for (final m in messages.take(lastUser))
      if (m is UserMessage || (m is AssistantMessage && m.toolCalls.isEmpty && m.text.isNotEmpty)) m,
    ...messages.skip(lastUser),
  ];
}

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
