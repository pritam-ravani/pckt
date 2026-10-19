import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/palette.dart';
import '../../ui/widgets.dart';
import '../stats.dart';

/// Top categories as a donut + full legend. Five slices max; the rest fold
/// into a neutral "Everything else" so we never invent extra hues.
class CategoryDonutCard extends StatefulWidget {
  const CategoryDonutCard({super.key, required this.stats});
  final MonthStats stats;

  @override
  State<CategoryDonutCard> createState() => _CategoryDonutCardState();
}

class _CategoryDonutCardState extends State<CategoryDonutCard> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final total = widget.stats.spent;
    final top = widget.stats.categories.take(5).toList();
    final rest = widget.stats.categories.skip(5).fold<int>(0, (s, c) => s + c.amount);
    final slices = [
      for (final c in top)
        (c.category?.name ?? 'Uncategorised', c.amount, Color(c.category?.color ?? Palette.neutral.toARGB32()), c),
      if (rest > 0) ('Everything else', rest, Palette.neutral, null),
    ];
    final focus = _touched != null && _touched! < slices.length ? slices[_touched!] : null;

    return AppCard(
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 64,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, resp) => setState(() {
                        _touched = event.isInterestedForInteractions ? resp?.touchedSection?.touchedSectionIndex : null;
                        if (_touched == -1) _touched = null;
                      }),
                    ),
                    sections: [
                      for (final (i, s) in slices.indexed)
                        PieChartSectionData(
                          value: s.$2.toDouble(),
                          color: s.$3,
                          radius: i == _touched ? 30 : 24,
                          showTitle: false,
                          borderSide: BorderSide(color: context.colors.surfaceContainer, width: 0),
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      focus?.$1 ?? 'Total spent',
                      style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      moneyCompact(focus?.$2 ?? total),
                      style: context.text.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    if (focus != null && total > 0)
                      Text(
                        '${(focus.$2 * 100 / total).round()}%',
                        style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final s in slices)
            _LegendRow(
              label: s.$1,
              amount: s.$2,
              share: total == 0 ? 0 : s.$2 / total,
              color: s.$3,
              badge: s.$4 == null ? null : CategoryBadge(category: s.$4!.category, size: 34),
            ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.label, required this.amount, required this.share, required this.color, this.badge});

  final String label;
  final int amount;
  final double share;
  final Color color;
  final Widget? badge;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        badge ??
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
            ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    money(amount),
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 6,
                        color: color,
                        backgroundColor: context.colors.surfaceContainerHigh,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${(share * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
