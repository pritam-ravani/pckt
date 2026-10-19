import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/icons.dart';

import '../../core/format.dart';
import '../../core/theme/palette.dart';
import '../../ui/widgets.dart';
import '../stats.dart';

/// Gradient summary card: month spend as the hero number, income/net pills,
/// and a daily-spend bar strip (single series — the title names it).
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.stats, required this.month});

  final MonthStats stats;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    final daysElapsed = isCurrent ? now.day : stats.daily.length;
    final perDay = daysElapsed == 0 ? 0 : stats.spent ~/ daysElapsed;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: Palette.heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Palette.violet.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spent in ${monthShort(month)}',
            style: context.text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              money(stats.spent),
              style: context.text.displaySmall?.copyWith(
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(icon: PhosphorIconsBold.arrowDownLeft, label: 'In ${money(stats.income)}', tint: Palette.mint),
              _Pill(icon: PhosphorIconsBold.calendarBlank, label: '${money(perDay)}/day', tint: Colors.white),
              _Pill(icon: PhosphorIconsBold.receipt, label: '${stats.count} spends', tint: Colors.white),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 64,
            child: _DailyBars(daily: stats.daily, today: isCurrent ? now.day : null),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.tint});
  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: tint),
        const SizedBox(width: 6),
        Text(
          label,
          style: context.text.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.daily, this.today});
  final List<int> daily;
  final int? today;

  @override
  Widget build(BuildContext context) {
    final maxY = daily.fold<int>(0, (m, v) => v > m ? v : m).toDouble();
    final today = this.today;
    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 1 : maxY,
        alignment: BarChartAlignment.spaceBetween,
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.black.withValues(alpha: 0.8),
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              'Day ${group.x + 1}\n${money(rod.toY.round())}',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < daily.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: daily[i] == 0 ? maxY * 0.02 : daily[i].toDouble(),
                  width: 5,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  color: i + 1 == today
                      ? Palette.mint
                      : today != null && i + 1 > today
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.55),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
