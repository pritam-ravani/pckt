import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../ui/widgets.dart';
import 'budget_math.dart';
import 'budget_providers.dart';

/// Bar color: the budget's own color until 80%, amber to 100%, coral past it.
Color budgetColor(BudgetProgress p, {Color? normal}) => switch (p.level) {
  BudgetLevel.over => Palette.coral,
  BudgetLevel.warning => Palette.amber,
  BudgetLevel.ok => normal ?? (p.category == null ? Palette.violet : Color(p.category!.color)),
};

class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.progress, this.height = 8});

  final BudgetProgress progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = budgetColor(progress);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: progress.ratio.clamp(0, 1).toDouble()),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: height,
            color: color,
            backgroundColor: color.withValues(alpha: context.isDark ? 0.16 : 0.14),
          ),
        ),
      ),
    );
  }
}

/// "₹X/day left for N days", "₹Y over budget" or a month-end summary.
String paceLabel(BudgetProgress p) {
  if (p.remainingMinor < 0) return '${money(-p.remainingMinor)} over';
  if (p.daysLeft <= 0) return '${money(p.remainingMinor)} left unspent';
  if (p.remainingMinor == 0) return 'Nothing left for ${p.daysLeft} day${p.daysLeft == 1 ? '' : 's'}';
  return '${money(p.perDayLeftMinor)}/day left for ${p.daysLeft} day${p.daysLeft == 1 ? '' : 's'}';
}

/// Dashboard card: overall budget progress and the 3 categories closest
/// to their limit. Shows a slim prompt when no budget is set.
class BudgetCard extends ConsumerWidget {
  const BudgetCard({super.key, required this.hasSpending});

  final bool hasSpending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider).value;
    if (progress == null) return const SizedBox.shrink();
    if (progress.isEmpty) {
      if (!hasSpending) return const SizedBox.shrink();
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () => context.push('/budgets'),
        child: Row(
          children: [
            const Icon(PhosphorIconsFill.target, color: Palette.violet),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Set a monthly budget',
                style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(PhosphorIconsBold.caretRight, size: 18),
          ],
        ),
      );
    }
    final overall = progress.where((p) => p.isOverall).firstOrNull;
    final cats = progress.where((p) => !p.isOverall).take(3).toList();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      onTap: () => context.push('/budgets'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Budget', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Icon(PhosphorIconsBold.caretRight, size: 16, color: context.colors.onSurfaceVariant),
            ],
          ),
          if (overall != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  money(overall.spentMinor),
                  style: context.text.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'of ${money(overall.limitMinor)}',
                    style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
                Text(
                  '${(overall.ratio * 100).round()}%',
                  style: context.text.titleSmall?.copyWith(
                    color: overall.level == BudgetLevel.ok ? null : budgetColor(overall),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BudgetBar(progress: overall, height: 10),
            const SizedBox(height: 8),
            Text(
              paceLabel(overall),
              style: context.text.bodySmall?.copyWith(
                color: overall.remainingMinor < 0 ? Palette.coral : context.colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (cats.isNotEmpty) ...[
            SizedBox(height: overall == null ? 8 : 14),
            for (final p in cats) _CategoryBudgetRow(progress: p),
          ],
        ],
      ),
    );
  }
}

class _CategoryBudgetRow extends StatelessWidget {
  const _CategoryBudgetRow({required this.progress});
  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        CategoryBadge(category: progress.category, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      progress.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelLarge,
                    ),
                  ),
                  Text(
                    '${moneyCompact(progress.spentMinor)} / ${moneyCompact(progress.limitMinor)}',
                    style: context.text.labelMedium?.copyWith(
                      color: progress.level == BudgetLevel.ok ? context.colors.onSurfaceVariant : budgetColor(progress),
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              BudgetBar(progress: progress, height: 6),
            ],
          ),
        ),
      ],
    ),
  );
}
