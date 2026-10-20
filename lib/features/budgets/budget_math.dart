import '../../data/db/database.dart';
import '../stats.dart';

enum BudgetLevel { ok, warning, over }

/// Share of a budget at which it turns amber.
const budgetWarnRatio = 0.8;

/// One budget measured against a month's spending.
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.category,
    required this.spentMinor,
    required this.daysLeft,
  });

  final Budget budget;

  /// Null for the overall budget.
  final Category? category;
  final int spentMinor;

  /// Days left in the month including today (0 for past months).
  final int daysLeft;

  bool get isOverall => budget.categoryId == null;
  int get limitMinor => budget.amountMinor;
  int get remainingMinor => limitMinor - spentMinor;
  double get ratio => limitMinor <= 0 ? 0 : spentMinor / limitMinor;

  BudgetLevel get level => ratio > 1
      ? BudgetLevel.over
      : ratio >= budgetWarnRatio
      ? BudgetLevel.warning
      : BudgetLevel.ok;

  /// What can still be spent per day to stay within the limit.
  int get perDayLeftMinor => daysLeft <= 0 || remainingMinor <= 0 ? 0 : remainingMinor ~/ daysLeft;

  /// Stable key for alert bookkeeping: `overall` or `cat<id>`.
  String get key => isOverall ? 'overall' : 'cat${budget.categoryId}';

  String get label => isOverall ? 'Monthly budget' : category?.name ?? 'Category';
}

/// Days left in [month] counting [now]'s day; full month if [month] is in
/// the future, 0 if it's over.
int daysLeftIn(DateTime month, DateTime now) {
  // UTC so a DST shift can't shave a day off.
  final start = DateTime.utc(month.year, month.month);
  final end = DateTime.utc(month.year, month.month + 1);
  final today = DateTime.utc(now.year, now.month, now.day);
  if (!today.isBefore(end)) return 0;
  if (today.isBefore(start)) return end.difference(start).inDays;
  return end.difference(today).inDays;
}

/// Measures every active budget against [txns] for [month]. Only debits
/// dated inside the month count; transfers are excluded (via [MonthStats]).
/// The overall budget (if any) comes first, then categories by how close
/// they are to their limit.
List<BudgetProgress> budgetProgress({
  required List<Budget> budgets,
  required List<TxnView> txns,
  required List<Category> categories,
  required DateTime month,
  required DateTime now,
}) {
  final inMonth = txns
      .where((v) => v.txn.occurredAt.year == month.year && v.txn.occurredAt.month == month.month)
      .toList();
  final stats = MonthStats(inMonth, month);
  final byCat = {for (final c in stats.categories) c.category?.id: c.amount};
  final cats = {for (final c in categories) c.id: c};
  final days = daysLeftIn(month, now);

  final out = <BudgetProgress>[];
  for (final b in budgets) {
    if (!b.active || b.amountMinor <= 0) continue;
    if (b.categoryId != null && !cats.containsKey(b.categoryId)) continue;
    out.add(
      BudgetProgress(
        budget: b,
        category: b.categoryId == null ? null : cats[b.categoryId],
        spentMinor: b.categoryId == null ? stats.spent : byCat[b.categoryId] ?? 0,
        daysLeft: days,
      ),
    );
  }
  out.sort((a, b) {
    if (a.isOverall != b.isOverall) return a.isOverall ? -1 : 1;
    return b.ratio.compareTo(a.ratio);
  });
  return out;
}

/// A threshold crossing that should be announced once per month.
class BudgetAlert {
  const BudgetAlert(this.progress, this.threshold);
  final BudgetProgress progress;

  /// 80 or 100.
  final int threshold;

  String get id => '${progress.key}:$threshold';

  String get title => threshold >= 100
      ? '${progress.label} ${progress.ratio > 1 ? 'exceeded' : 'used up'}'
      : '${progress.label} at ${(progress.ratio * 100).floor()}%';
}

const budgetThresholds = [80, 100];

/// Threshold crossings in [progress] not yet in [alreadySent] (ids like
/// 'cat3:80'). When a budget jumps straight past 100% only the 100%
/// alert is returned, but [markSent] still records both.
List<BudgetAlert> pendingBudgetAlerts(List<BudgetProgress> progress, Set<String> alreadySent) {
  final out = <BudgetAlert>[];
  for (final p in progress) {
    final crossed = [
      for (final t in budgetThresholds)
        if (p.ratio * 100 >= t) t,
    ];
    if (crossed.isEmpty) continue;
    final top = crossed.last;
    if (!alreadySent.contains('${p.key}:$top')) out.add(BudgetAlert(p, top));
  }
  return out;
}

/// Ids to record after sending [alerts]: each alert plus every lower threshold.
Set<String> alertIdsToMark(List<BudgetAlert> alerts) => {
  for (final a in alerts)
    for (final t in budgetThresholds)
      if (t <= a.threshold) '${a.progress.key}:$t',
};
