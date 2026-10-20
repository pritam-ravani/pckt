import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/icons.dart';

import '../../core/format.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import '../budgets/budget_math.dart';
import '../budgets/budget_providers.dart';
import '../recurring/recurring_detector.dart';
import '../recurring/recurring_screen.dart';
import '../stats.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final trend = ref.watch(trendTxnsProvider).value ?? const <TxnView>[];
    final ctrl = ref.read(selectedMonthProvider.notifier);

    final months = [for (var i = 5; i >= 0; i--) DateTime(month.year, month.month - i)];
    final byMonth = {
      for (final m in months)
        m: MonthStats(
          trend.where((v) => v.txn.occurredAt.year == m.year && v.txn.occurredAt.month == m.month).toList(),
          m,
        ),
    };
    final cur = byMonth[month]!;
    final prev = byMonth[months[4]]!;
    final change = prev.spent == 0 ? null : (cur.spent - prev.spent) / prev.spent;
    final monthTxns = trend
        .where((v) => v.txn.occurredAt.year == month.year && v.txn.occurredAt.month == month.month)
        .toList();
    final merchants = topMerchants(monthTxns);
    final biggest = monthTxns
        .where((v) => v.txn.direction == TxnDirection.debit && !v.txn.isTransfer)
        .fold<TxnView?>(null, (b, v) => b == null || v.txn.amountMinor > b.txn.amountMinor ? v : b);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            Row(
              children: [
                const SizedBox(width: 4),
                Expanded(child: Text('Insights', style: context.text.headlineSmall)),
                IconButton(onPressed: () => ctrl.shift(-1), icon: const Icon(PhosphorIconsBold.caretLeft, size: 20)),
                Text(monthShort(month), style: context.text.titleMedium),
                IconButton(
                  onPressed: month == monthStart(DateTime.now()) ? null : () => ctrl.shift(1),
                  icon: const Icon(PhosphorIconsBold.caretRight, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _StatTile(
                  icon: PhosphorIconsFill.trendDown,
                  label: 'vs last month',
                  value: change == null ? '—' : '${change >= 0 ? '+' : '−'}${(change.abs() * 100).round()}%',
                  tint: change == null
                      ? null
                      : change > 0
                      ? Palette.coral
                      : Palette.mint,
                ),
                _StatTile(
                  icon: PhosphorIconsFill.piggyBank,
                  label: 'Net saved',
                  value: moneyCompact(cur.net),
                  tint: cur.net >= 0 ? Palette.mint : Palette.coral,
                ),
                _StatTile(
                  icon: PhosphorIconsFill.crown,
                  label: 'Top category',
                  value: cur.categories.firstOrNull?.category?.name ?? '—',
                ),
                _StatTile(
                  icon: PhosphorIconsFill.receipt,
                  label: 'Biggest spend',
                  value: biggest == null ? '—' : moneyCompact(biggest.txn.amountMinor),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _LinkTile(
                    icon: PhosphorIconsFill.target,
                    title: 'Budgets',
                    subtitle: _budgetSummary(ref.watch(budgetProgressProvider).value),
                    onTap: () => context.push('/budgets'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LinkTile(
                    icon: PhosphorIconsFill.repeat,
                    title: 'Recurring',
                    subtitle: switch (ref.watch(recurringProvider).value) {
                      null => '…',
                      final l when l.isEmpty => 'None found',
                      final l => '${moneyCompact(monthlyTotalMinor(l))}/mo',
                    },
                    onTap: () => context.push('/recurring'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionHeader('Last 6 months'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      _LegendDot(color: Palette.violet, label: 'Spent'),
                      const SizedBox(width: 16),
                      _LegendDot(color: Palette.mint, label: 'Income'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: _TrendChart(months: months, stats: byMonth),
                  ),
                ],
              ),
            ),
            if (merchants.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionHeader('Top merchants'),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    for (final m in merchants)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: CategoryBadge(category: m.category, size: 40),
                        title: Text(m.name, style: context.text.titleSmall),
                        subtitle: Text('${m.count} payment${m.count == 1 ? '' : 's'}'),
                        trailing: Text(
                          money(m.amount),
                          style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _budgetSummary(List<BudgetProgress>? progress) {
  if (progress == null) return '…';
  if (progress.isEmpty) return 'Set a limit';
  final over = progress.where((p) => p.level == BudgetLevel.over).length;
  if (over > 0) return '$over over limit';
  final overall = progress.where((p) => p.isOverall).firstOrNull;
  if (overall != null) return '${(overall.ratio * 100).round()}% used';
  return '${progress.length} active';
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(14),
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, size: 22, color: Palette.violet),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Icon(PhosphorIconsBold.caretRight, size: 14, color: context.colors.onSurfaceVariant),
      ],
    ),
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value, this.tint});
  final IconData icon;
  final String label;
  final String value;
  final Color? tint;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: tint ?? Palette.violet),
        const Spacer(),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        Text(label, style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
      ],
    ),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 6),
      Text(label, style: context.text.labelMedium),
    ],
  );
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.months, required this.stats});
  final List<DateTime> months;
  final Map<DateTime, MonthStats> stats;

  @override
  Widget build(BuildContext context) {
    final maxV = stats.values.fold<int>(1, (m, s) => [m, s.spent, s.income].reduce((a, b) => a > b ? a : b));
    final grid = context.colors.outlineVariant;
    return BarChart(
      BarChartData(
        maxY: maxV * 1.1,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxV / 3,
          getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1, dashArray: [4, 4]),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              interval: maxV / 3,
              getTitlesWidget: (v, meta) => v == meta.max
                  ? const SizedBox.shrink()
                  : Text(
                      moneyCompact(v.round()),
                      style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  monthShort(months[v.toInt()]),
                  style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => context.colors.surfaceContainerHigh,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (g, _, rod, i) => BarTooltipItem(
              '${i == 0 ? 'Spent' : 'Income'}\n${money(rod.toY.round())}',
              context.text.labelMedium!.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        barGroups: [
          for (final (i, m) in months.indexed)
            BarChartGroupData(
              x: i,
              barsSpace: 3,
              barRods: [
                BarChartRodData(
                  toY: stats[m]!.spent.toDouble(),
                  width: 10,
                  color: Palette.violet,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
                BarChartRodData(
                  toY: stats[m]!.income.toDouble(),
                  width: 10,
                  color: Palette.mint,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
