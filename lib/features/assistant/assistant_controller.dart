import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../llm/agent/finance_agent.dart';
import '../../llm/agent/finance_tools.dart';
import '../../llm/llm_client.dart';
import '../../llm/llm_providers.dart';
import '../../llm/on_device/on_device_client.dart';
import '../../providers.dart';

enum ChatRole { user, assistant, error }

class ChatEntry {
  const ChatEntry(this.role, this.text, {this.activity = const []});
  final ChatRole role;
  final String text;
  final List<AgentActivity> activity;
}

class AssistantState {
  const AssistantState({this.entries = const [], this.working, this.proposal, this.partial, this.status});

  final List<ChatEntry> entries;

  /// Tool activity of the answer in progress; null when idle.
  final List<AgentActivity>? working;

  /// A change waiting for the user's OK.
  final RecategorizeProposal? proposal;

  /// The answer as it is being written (on-device models stream).
  final String? partial;

  /// What the working indicator says, e.g. that the model is loading.
  final String? status;

  bool get busy => working != null;

  AssistantState copyWith({
    List<ChatEntry>? entries,
    List<AgentActivity>? working,
    bool clearWorking = false,
    RecategorizeProposal? proposal,
    bool clearProposal = false,
    String? partial,
    String? status,
  }) => AssistantState(
    entries: entries ?? this.entries,
    working: clearWorking ? null : working ?? this.working,
    proposal: clearProposal ? null : proposal ?? this.proposal,
    partial: clearWorking ? null : (partial == null ? this.partial : (partial.isEmpty ? null : partial)),
    status: clearWorking ? null : status ?? this.status,
  );
}

/// In-memory chat with the finance agent. History lives as long as the app.
class AssistantController extends Notifier<AssistantState> {
  final _history = <LlmMessage>[];
  Completer<bool>? _pending;

  @override
  AssistantState build() => const AssistantState();

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || state.busy) return;
    state = state.copyWith(entries: [...state.entries, ChatEntry(ChatRole.user, q)], working: const []);

    final config = ref.read(llmConfigProvider);
    LlmClient? client;
    try {
      client = await ref.read(llmClientProvider.future);
    } catch (_) {}
    if (client == null || !config.assistant) {
      _finish(
        ChatEntry(
          ChatRole.error,
          client == null
              ? 'Connect an LLM in Settings to use the assistant.'
              : 'The assistant is turned off in Settings → Connect your LLM.',
        ),
      );
      return;
    }
    if (client case LlmBudget(supportsTools: false)) {
      _finish(
        const ChatEntry(
          ChatRole.error,
          'This on-device model can\'t look up your transactions. Switch to Gemma 4 in Settings → Connect your LLM.',
        ),
      );
      return;
    }

    final onDevice = client is LlmBudget;
    if (client is OnDeviceClient && !OnDeviceClient.runtime.isWarm) {
      state = state.copyWith(status: 'Loading the on-device model… the first answer takes a minute');
    } else if (onDevice) {
      state = state.copyWith(status: 'Thinking on this phone…');
    }
    final agent = FinanceAgent(client: client, tools: FinanceTools(ref.read(databaseProvider)));
    try {
      final res = await agent.run(
        List.of(_history),
        q,
        confirm: _confirm,
        onActivity: (a) =>
            state = state.copyWith(working: [...?state.working, a], status: onDevice ? 'Working on this phone…' : null),
        onText: onDevice ? (t) => state = state.copyWith(partial: t) : null,
      );
      _history.addAll(res.newMessages);
      _finish(ChatEntry(ChatRole.assistant, res.text, activity: res.activity));
    } on LlmException catch (e) {
      _finish(
        ChatEntry(
          ChatRole.error,
          onDevice && e.kind == LlmErrorKind.timeout
              ? 'The on-device model is taking too long on this phone — try a shorter question or a smaller model.'
              : e.userMessage,
        ),
      );
    } catch (e, st) {
      debugPrint('Assistant failed: $e\n$st');
      _finish(ChatEntry(ChatRole.error, 'Something went wrong: $e'));
    }
  }

  void _finish(ChatEntry entry) =>
      state = state.copyWith(entries: [...state.entries, entry], clearWorking: true, clearProposal: true);

  Future<bool> _confirm(RecategorizeProposal p) {
    _pending?.complete(false);
    final c = _pending = Completer<bool>();
    state = state.copyWith(proposal: p);
    return c.future;
  }

  void answerProposal(bool approve) {
    _pending?.complete(approve);
    _pending = null;
    state = state.copyWith(clearProposal: true);
  }

  void reset() {
    if (state.busy) return;
    _history.clear();
    state = const AssistantState();
  }
}

final assistantProvider = NotifierProvider<AssistantController, AssistantState>(AssistantController.new);
