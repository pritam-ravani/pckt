import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';

import '../../core/format.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';

/// Shows how each SMS was handled — the main tool for spotting parser gaps.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  var _status = ParseStatus.ignored;

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Message log')),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              children: [
                for (final (s, label) in const [
                  (ParseStatus.ignored, 'Ignored'),
                  (ParseStatus.pendingLlm, 'Unreadable'),
                  (ParseStatus.parsed, 'Parsed'),
                  (ParseStatus.merged, 'Merged'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: db.watchRawMessages(SourceKind.sms, {_status}),
              builder: (context, snap) {
                final list = snap.data ?? const <RawMessage>[];
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: PhosphorIconsFill.chatText,
                    title: 'Nothing here',
                    message: 'No messages in this bucket.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _MessageCard(message: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});
  final RawMessage message;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(14),
    onTap: () {
      Clipboard.setData(ClipboardData(text: '${message.sender}\n${message.body}'));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(message.sender, style: context.text.labelLarge)),
            if (message.ignoreReason != null)
              InfoPill(icon: PhosphorIconsBold.info, label: message.ignoreReason!, color: Palette.amber),
          ],
        ),
        const SizedBox(height: 8),
        Text(message.body, style: context.text.bodySmall?.copyWith(height: 1.45)),
        const SizedBox(height: 6),
        Text(
          dateTimeLabel(message.receivedAt),
          style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      ],
    ),
  );
}
