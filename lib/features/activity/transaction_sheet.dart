import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';

import '../../core/format.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import 'category_picker.dart';

Future<void> showTransactionSheet(BuildContext context, int id) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    maxChildSize: 0.95,
    builder: (_, scroll) => TransactionSheet(id: id, scroll: scroll),
  ),
);

class TransactionSheet extends ConsumerWidget {
  const TransactionSheet({super.key, required this.id, required this.scroll});

  final int id;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(txnProvider(id)).value;
    if (view == null) return const SizedBox(height: 200);
    final t = view.txn;
    final db = ref.read(databaseProvider);
    final credit = t.direction == TxnDirection.credit;
    final sources = ref.watch(txnSourcesProvider(id)).value ?? const [];

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Center(
          child: CategoryBadge(category: view.category, isTransfer: t.isTransfer, size: 64),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            '${credit ? '+' : '−'}${money(t.amountMinor, forceDecimals: true)}',
            style: context.text.displaySmall?.copyWith(
              color: credit && !t.isTransfer ? Palette.income : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(txnTitle(t), style: context.text.titleMedium, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            dateTimeLabel(t.occurredAt),
            style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            InfoPill(icon: modeIcon(t.mode), label: modeLabel(t.mode)),
            if (view.account != null)
              InfoPill(icon: PhosphorIconsBold.bank, label: '${view.account!.name} ••${view.account!.last4}')
            else if (t.accountHint != null)
              InfoPill(icon: PhosphorIconsBold.bank, label: '••${t.accountHint}'),
            if (t.reference != null) InfoPill(icon: PhosphorIconsBold.hash, label: t.reference!),
            if (t.counterparty != null && t.counterparty != t.merchant)
              InfoPill(icon: PhosphorIconsBold.at, label: t.counterparty!),
          ],
        ),
        if (t.duplicateOfId != null) ...[
          const SizedBox(height: 18),
          _DuplicatePanel(id: id, otherId: t.duplicateOfId!),
        ] else if (t.status == TxnStatus.needsReview) ...[
          const SizedBox(height: 18),
          AppCard(
            color: Palette.amber.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(PhosphorIconsFill.warningCircle, color: Palette.amber),
                const SizedBox(width: 12),
                const Expanded(child: Text('Parsed with low confidence. Does this look right?')),
                TextButton(onPressed: () => db.confirm(id), child: const Text('Looks right')),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        const SectionHeader('Category'),
        CategoryPicker(
          selectedId: t.categoryId,
          income: credit,
          onSelected: (c) => db.setCategory(id, c.id, learnPattern: t.merchant?.toLowerCase()),
        ),
        if (t.merchant != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Future ${t.merchant} transactions will use the category you pick.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: t.isTransfer,
          onChanged: (v) => db.setTransfer(id, v),
          title: const Text('Transfer between my accounts'),
          subtitle: const Text('Excluded from spending and income'),
          secondary: const Icon(PhosphorIconsRegular.arrowsLeftRight),
        ),
        const SizedBox(height: 12),
        SectionHeader('Sources (${sources.length})'),
        for (final s in sources) _SourceCard(message: s),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Palette.coral,
            minimumSize: const Size.fromHeight(50),
            side: BorderSide(color: Palette.coral.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Delete transaction?'),
                content: const Text('The source message stays hidden so it won\'t be re-imported.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              Navigator.pop(context);
              await db.deleteTxn(id);
            }
          },
          icon: const Icon(PhosphorIconsRegular.trash),
          label: const Text('Delete'),
        ),
      ],
    );
  }
}

class _DuplicatePanel extends ConsumerWidget {
  const _DuplicatePanel({required this.id, required this.otherId});
  final int id;
  final int otherId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final other = ref.watch(txnProvider(otherId)).value;
    final db = ref.read(databaseProvider);
    return AppCard(
      color: Palette.amber.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsFill.copy, color: Palette.amber, size: 20),
              const SizedBox(width: 10),
              Text('Possible duplicate', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          if (other == null)
            const Text('The matching transaction no longer exists.')
          else
            TransactionTile(view: other, showDate: true),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => db.confirm(id), child: const Text('Keep both')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: other == null
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await db.mergeInto(id, otherId);
                        },
                  child: const Text('Merge'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.message});
  final RawMessage message;

  @override
  Widget build(BuildContext context) {
    final icon = switch (message.source) {
      SourceKind.sms => PhosphorIconsFill.chatText,
      SourceKind.email => PhosphorIconsFill.envelopeSimple,
      SourceKind.manual => PhosphorIconsFill.pencilSimple,
      SourceKind.shortcut => PhosphorIconsFill.lightning,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: context.colors.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: context.colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(message.sender, style: context.text.labelLarge)),
                if (message.parseStatus == ParseStatus.merged)
                  const InfoPill(icon: PhosphorIconsBold.gitMerge, label: 'merged', color: Palette.mint),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(message.body, style: context.text.bodySmall?.copyWith(height: 1.45)),
            const SizedBox(height: 6),
            Text(
              dateTimeLabel(message.receivedAt),
              style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
