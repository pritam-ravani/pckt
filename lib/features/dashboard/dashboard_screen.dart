import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/icons.dart';

import '../../core/format.dart';
import '../../core/theme/palette.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import '../activity/transaction_sheet.dart';
import '../budgets/budget_widgets.dart';
import '../stats.dart';
import 'category_donut.dart';
import 'hero_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final txns = ref.watch(monthTxnsProvider);
    final sync = ref.watch(smsSyncProvider);
    final review = ref.watch(reviewCountProvider).value ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(smsSyncProvider.notifier).sync(),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(month: month, syncing: sync.running),
              ),
              ...txns.when(
                loading: () => [const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))],
                error: (e, _) => [SliverFillRemaining(child: Center(child: Text('$e')))],
                data: (list) {
                  final stats = MonthStats(list, month);
                  return [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      sliver: SliverList.list(
                        children: [
                          HeroCard(stats: stats, month: month),
                          const SizedBox(height: 12),
                          BudgetCard(hasSpending: stats.spent > 0),
                          if (review > 0) ...[const SizedBox(height: 12), _ReviewBanner(count: review)],
                          if (!sync.enabled && list.isEmpty) ...[const SizedBox(height: 12), const _ConnectSmsCard()],
                          const SizedBox(height: 20),
                          if (stats.categories.isNotEmpty) ...[
                            const SectionHeader('Where it went'),
                            CategoryDonutCard(stats: stats),
                            const SizedBox(height: 20),
                          ],
                          SectionHeader(
                            'Recent',
                            action: list.isEmpty ? null : 'See all',
                            onAction: () => context.go('/activity'),
                          ),
                        ],
                      ),
                    ),
                    if (list.isEmpty)
                      const SliverToBoxAdapter(
                        child: EmptyState(
                          icon: PhosphorIconsFill.receipt,
                          title: 'Nothing here yet',
                          message:
                              'Transactions from your bank SMS show up automatically. You can also add one with +.',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        sliver: SliverList.builder(
                          itemCount: list.length.clamp(0, 8),
                          itemBuilder: (_, i) => TransactionTile(
                            view: list[i],
                            showDate: true,
                            onTap: () => showTransactionSheet(context, list[i].txn.id),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.month, required this.syncing});

  final DateTime month;
  final bool syncing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(selectedMonthProvider.notifier);
    final isCurrent = month == monthStart(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting(), style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                const SizedBox(height: 2),
                Row(children: [Text(monthLabel(month), style: context.text.headlineSmall)]),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Previous month',
            onPressed: () => ctrl.shift(-1),
            icon: const Icon(PhosphorIconsBold.caretLeft, size: 20),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: isCurrent ? null : () => ctrl.shift(1),
            icon: const Icon(PhosphorIconsBold.caretRight, size: 20),
          ),
          _SyncButton(syncing: syncing),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Good morning'
        : h < 17
        ? 'Good afternoon'
        : 'Good evening';
  }
}

class _SyncButton extends ConsumerStatefulWidget {
  const _SyncButton({required this.syncing});
  final bool syncing;

  @override
  ConsumerState<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends ConsumerState<_SyncButton> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(_SyncButton old) {
    super.didUpdateWidget(old);
    widget.syncing ? _spin.repeat() : _spin.reset();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: 'Sync SMS',
    onPressed: widget.syncing ? null : () => ref.read(smsSyncProvider.notifier).sync(),
    icon: RotationTransition(turns: _spin, child: const Icon(PhosphorIconsBold.arrowsClockwise, size: 20)),
  );
}

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    color: Palette.amber.withValues(alpha: context.isDark ? 0.12 : 0.16),
    onTap: () => context.go('/activity?filter=review'),
    child: Row(
      children: [
        const Icon(PhosphorIconsFill.warningCircle, color: Palette.amber),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '$count transaction${count == 1 ? '' : 's'} need${count == 1 ? 's' : ''} a quick look',
            style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const Icon(PhosphorIconsBold.caretRight, size: 18),
      ],
    ),
  );
}

class _ConnectSmsCard extends ConsumerWidget {
  const _ConnectSmsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppCard(
    onTap: () => context.go('/settings'),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Palette.mint.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(PhosphorIconsFill.chatText, color: Palette.mint),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connect SMS', style: context.text.titleMedium),
              Text(
                'Track UPI & card spends automatically',
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const Icon(PhosphorIconsBold.caretRight, size: 18),
      ],
    ),
  );
}
