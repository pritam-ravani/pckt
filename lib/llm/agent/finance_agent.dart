import 'package:intl/intl.dart';

import '../llm_client.dart';
import 'finance_tools.dart';
import 'tool_result_budget.dart';

/// Something the agent did while working on an answer, for the chat UI.
class AgentActivity {
  const AgentActivity(this.tool, this.summary, {this.isError = false});
  final String tool;
  final String summary;
  final bool isError;
}

class AgentResult {
  const AgentResult({required this.text, required this.newMessages, required this.activity, this.hitStepLimit = false});

  final String text;

  /// Everything to append to the conversation history (user turn included).
  final List<LlmMessage> newMessages;
  final List<AgentActivity> activity;
  final bool hitStepLimit;
}

/// Tool-using loop over the local finance database: ask the model, run the
/// tools it calls, feed results back, until it answers or [maxSteps].
class FinanceAgent {
  FinanceAgent({required this.client, required this.tools, this.maxSteps = 8, DateTime Function()? now})
    : now = now ?? DateTime.now;

  final LlmClient client;
  final FinanceTools tools;
  final int maxSteps;
  final DateTime Function() now;

  String systemPrompt() {
    final today = now();
    return '''
You are Pckt's money assistant for a user in India. Their transactions were read from bank/UPI/card SMS and emails and are stored only on their phone; you can query them with tools.

Today is ${DateFormat('EEEE, d MMMM yyyy').format(today)} (${DateFormat('yyyy-MM-dd').format(today)}).

- Never invent or estimate numbers. Every amount, count or date you state must come from a tool result in this conversation. If the data doesn't answer the question, say so.
- Use spending_summary for totals and breakdowns, query_transactions for specific payments, find_recurring for subscriptions. Transfers between the user's own accounts are not spending.
- Write amounts in rupees with Indian digit grouping, e.g. ₹1,23,456 (drop paise unless they matter). Prefer the *_formatted fields.
- "This month" means from the 1st of the current month to today; "last month" is the full previous calendar month.
- Be concise: lead with the answer, then at most a few bullets. Use **bold** for key figures. No tables, no headings.
- Only use recategorize when the user asks to change categories; the app will ask them to confirm.
- You can give general, practical budgeting suggestions, but you are not a licensed financial adviser.''';
  }

  /// Small-context (on-device) clients get compact tool results, a tighter
  /// output cap and fewer steps: every token is computed on the phone.
  LlmBudget? get _budget => client is LlmBudget ? client as LlmBudget : null;

  /// Output cap per turn. A tool-planning turn emits one short call and
  /// answers are asked to be concise; on a phone the cap mostly stops a
  /// small model that starts rambling from burning minutes.
  int get _maxTokens => _budget == null ? 4096 : 1024;

  int get _steps => _budget == null ? maxSteps : maxSteps.clamp(1, 4);

  String _resultContent(ToolOutcome out) {
    final b = _budget;
    return b == null ? out.content : compactToolJson(out.json, ToolResultBudget.forContext(b.contextTokens));
  }

  Future<LlmResponse> _ask(String system, List<LlmMessage> messages, int maxTokens, void Function(String)? onText) {
    if ((onText, client) case (final onText?, final LlmStreamingClient c)) {
      return c.chatStreaming(
        system: system,
        messages: messages,
        tools: tools.specs,
        maxTokens: maxTokens,
        onText: onText,
      );
    }
    return client.chat(system: system, messages: messages, tools: tools.specs, maxTokens: maxTokens);
  }

  /// [onText] receives the answer as it is written on clients that stream
  /// (on-device). It is called with '' when a turn turns out to be a tool
  /// call, so the UI can drop the draft.
  Future<AgentResult> run(
    List<LlmMessage> history,
    String userText, {
    ConfirmRecategorize? confirm,
    void Function(AgentActivity activity)? onActivity,
    void Function(String textSoFar)? onText,
  }) async {
    final added = <LlmMessage>[UserMessage(userText)];
    final activity = <AgentActivity>[];
    final system = systemPrompt();

    for (var step = 0; step < _steps; step++) {
      final res = await _ask(system, [...history, ...added], _maxTokens, onText);
      added.add(res.message);
      if (res.toolCalls.isNotEmpty) onText?.call('');
      if (res.toolCalls.isEmpty) {
        final text = res.text.trim();
        return AgentResult(
          text: text.isEmpty
              ? (res.stop == LlmStop.maxTokens ? 'The answer was cut off — try a narrower question.' : '…')
              : text,
          newMessages: added,
          activity: activity,
        );
      }
      final results = <ToolResult>[];
      for (final call in res.toolCalls) {
        final out = await tools.execute(call, confirm: confirm);
        final a = AgentActivity(call.name, out.summary, isError: out.isError);
        activity.add(a);
        onActivity?.call(a);
        results.add(ToolResult(callId: call.id, name: call.name, content: _resultContent(out), isError: out.isError));
      }
      added.add(ToolResultsMessage(results));
    }

    // Out of steps: ask once more for a best-effort answer. Tools stay
    // declared (some providers require it when history has tool calls), but
    // any further calls are dropped and only the text is kept.
    final last = await _ask(
      '$system\n\nYou have used all your tool calls. Do not call tools; answer now from the results you have.',
      [...history, ...added],
      _budget == null ? 2048 : 1024,
      onText,
    );
    final text = last.text.trim().isEmpty
        ? 'I couldn\'t finish that — try asking something more specific.'
        : last.text.trim();
    added.add(last.toolCalls.isEmpty ? last.message : AssistantMessage(text: text));
    return AgentResult(text: text, newMessages: added, activity: activity, hitStepLimit: true);
  }
}
