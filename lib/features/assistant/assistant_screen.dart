import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../llm/agent/finance_agent.dart';
import '../../llm/agent/finance_tools.dart';
import '../../llm/llm_providers.dart';
import '../../ui/widgets.dart';
import 'assistant_controller.dart';
import 'chat_markdown.dart';

const _suggestions = [
  'Where did my money go this month?',
  'Find my subscriptions',
  'Compare with last month',
  'Biggest expenses',
];

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final q = text ?? _input.text;
    if (q.trim().isEmpty) return;
    _input.clear();
    ref.read(assistantProvider.notifier).send(q);
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(llmConfigProvider);
    final chat = ref.watch(assistantProvider);
    ref.listen(assistantProvider, (_, _) => _scrollToEnd());

    final ready = config.isConfigured && config.assistant;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
              child: Row(
                children: [
                  const Icon(PhosphorIconsFill.sparkle, color: Palette.violet),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Ask Pckt', style: context.text.headlineSmall)),
                  if (chat.entries.isNotEmpty)
                    IconButton(
                      tooltip: 'New chat',
                      onPressed: chat.busy ? null : ref.read(assistantProvider.notifier).reset,
                      icon: const Icon(PhosphorIconsRegular.notePencil),
                    ),
                  IconButton(
                    tooltip: 'LLM settings',
                    onPressed: () => context.push('/llm'),
                    icon: const Icon(PhosphorIconsRegular.slidersHorizontal),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !ready
                  ? _NotReady(configured: config.isConfigured)
                  : chat.entries.isEmpty && !chat.busy
                  ? _Intro(onPick: _send)
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        for (final e in chat.entries) _Bubble(entry: e),
                        if (chat.busy) _Working(activity: chat.working!, partial: chat.partial, status: chat.status),
                        if (chat.proposal != null) _ProposalCard(proposal: chat.proposal!),
                      ],
                    ),
            ),
            if (ready) _InputBar(controller: _input, busy: chat.busy, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _NotReady extends StatelessWidget {
  const _NotReady({required this.configured});
  final bool configured;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: EmptyState(
        icon: PhosphorIconsFill.sparkle,
        title: configured ? 'Assistant is off' : 'Bring your own AI',
        message: configured
            ? 'Turn on "Assistant chat" in your LLM settings to ask questions about your spending.'
            : 'Connect OpenAI, Claude, Gemini, OpenRouter or a model on your own computer to ask questions '
                  'like "where did my money go this month?". Your data stays on this phone; the model only sees '
                  'the totals it asks for.',
        action: FilledButton.icon(
          onPressed: () => context.push('/llm'),
          icon: const Icon(PhosphorIconsBold.plugsConnected, size: 18),
          label: Text(configured ? 'Open LLM settings' : 'Connect your LLM'),
        ),
      ),
    ),
  );
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onPick});
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
    children: [
      Text('Ask anything about your money', style: context.text.titleLarge),
      const SizedBox(height: 6),
      Text(
        'Answers are computed from your transactions on this phone. Only the query results are sent to the model.',
        style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in _suggestions)
            ActionChip(
              avatar: const Icon(PhosphorIconsBold.sparkle, size: 16, color: Palette.violet),
              label: Text(s),
              onPressed: () => onPick(s),
            ),
        ],
      ),
    ],
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry});
  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final mine = entry.role == ChatRole.user;
    final error = entry.role == ChatRole.error;
    final bg = mine
        ? Palette.violet
        : error
        ? Palette.coral.withValues(alpha: 0.12)
        : context.colors.surfaceContainerHigh;
    final fg = mine ? Colors.white : (error ? Palette.coral : context.colors.onSurface);
    final style = context.text.bodyMedium?.copyWith(color: fg, height: 1.4);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (entry.activity.isNotEmpty) ...[_ActivityChips(entry.activity), const SizedBox(height: 6)],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.84),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
              ),
              child: mine || error
                  ? Text(entry.text, style: style)
                  : SelectionArea(child: ChatMarkdown(entry.text, style: style)),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _toolIcon(String tool) => switch (tool) {
  'query_transactions' => PhosphorIconsBold.magnifyingGlass,
  'spending_summary' => PhosphorIconsBold.chartPieSlice,
  'find_recurring' => PhosphorIconsBold.repeat,
  'recategorize' => PhosphorIconsBold.tag,
  _ => PhosphorIconsBold.listBullets,
};

class _ActivityChips extends StatelessWidget {
  const _ActivityChips(this.activity);
  final List<AgentActivity> activity;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final a in activity)
        InfoPill(icon: _toolIcon(a.tool), label: a.summary, color: a.isError ? Palette.coral : null),
    ],
  );
}

class _Working extends StatelessWidget {
  const _Working({required this.activity, this.partial, this.status});
  final List<AgentActivity> activity;
  final String? partial;
  final String? status;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activity.isNotEmpty) ...[_ActivityChips(activity), const SizedBox(height: 8)],
        if (partial != null) ...[
          // The answer as the on-device model writes it.
          _Bubble(entry: ChatEntry(ChatRole.assistant, partial!)),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                partial != null ? 'Writing…' : status ?? (activity.isEmpty ? 'Thinking…' : 'Working…'),
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ProposalCard extends ConsumerWidget {
  const _ProposalCard({required this.proposal});
  final RecategorizeProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(assistantProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(PhosphorIconsBold.tag, color: Palette.amber, size: 18),
                const SizedBox(width: 8),
                Text('Confirm change', style: context.text.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(proposal.description, style: context.text.bodyMedium),
            const SizedBox(height: 4),
            Text(
              '${money(proposal.total)} in total'
              '${proposal.learnMerchants.isEmpty ? '' : ' · future payments to these merchants will follow'}',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => ctrl.answerProposal(false), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => ctrl.answerProposal(true),
                  icon: const Icon(PhosphorIconsBold.check, size: 18),
                  label: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.busy, required this.onSend});
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => busy ? null : onSend(),
            decoration: InputDecoration(
              hintText: 'Ask about your spending…',
              filled: true,
              fillColor: context.colors.surfaceContainerHigh,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: busy ? null : onSend,
          tooltip: 'Send',
          icon: const Icon(PhosphorIconsBold.paperPlaneRight),
        ),
      ],
    ),
  );
}
