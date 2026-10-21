import 'package:collection/collection.dart';

import '../../data/db/database.dart';

/// A subscription or other payment that repeats at a steady cadence.
class RecurringPayment {
  const RecurringPayment({
    required this.name,
    required this.cadence,
    required this.periodDays,
    required this.typicalMinor,
    required this.count,
    required this.last,
    this.category,
    this.payments = const [],
  });

  final String name;

  /// 'weekly', 'monthly' or 'quarterly'.
  final String cadence;
  final int periodDays;

  /// Median amount of the matching payments, in home-currency minor units.
  final int typicalMinor;
  final int count;
  final DateTime last;
  final Category? category;

  /// The matching payments, oldest first.
  final List<TxnView> payments;

  DateTime get next => last.add(Duration(days: periodDays));

  /// Cost normalised to an average month (30.4 days), in home-currency
  /// minor units.
  double get monthlyCostMinor => typicalMinor * 30.4 / periodDays;

  /// True when the next payment date has already passed.
  bool isOverdue(DateTime today) => next.isBefore(DateTime(today.year, today.month, today.day));
}

/// Sum of [RecurringPayment.monthlyCostMinor], rounded to minor units.
int monthlyTotalMinor(Iterable<RecurringPayment> found) =>
    found.fold<double>(0, (s, r) => s + r.monthlyCostMinor).round();

/// Same merchant + similar amount (±20% of the median) at a steady cadence.
/// Needs 3+ similar payments, most gaps fitting the cadence, and a recent one.
/// Transfers and credits in [txns] are ignored, and so are foreign payments
/// without a home-currency amount (amounts are compared in the home currency).
List<RecurringPayment> detectRecurring(List<TxnView> txns, {required DateTime today}) {
  const cadences = [('weekly', 7, 5, 9), ('monthly', 30, 25, 36), ('quarterly', 91, 80, 100)];
  final debits = txns.where(
    (v) => !v.txn.isTransfer && v.txn.direction == TxnDirection.debit && v.txn.homeMinor != null,
  );
  final groups = groupBy(debits, (TxnView v) => (v.txn.merchant ?? v.txn.counterparty ?? '').toLowerCase().trim());
  final out = <RecurringPayment>[];
  for (final e in groups.entries) {
    if (e.key.isEmpty || e.value.length < 3) continue;
    final sorted = e.value.sortedBy((v) => v.txn.occurredAt);
    final amounts = sorted.map((v) => v.txn.homeMinor!).sorted((a, b) => a.compareTo(b));
    final median = amounts[amounts.length ~/ 2];
    // Keep payments with a similar amount (a subscription, not every Swiggy order).
    final similar = sorted.where((v) => (v.txn.homeMinor! - median).abs() <= median * 0.2).toList();
    if (similar.length < 3) continue;
    final gaps = [
      for (var i = 1; i < similar.length; i++)
        similar[i].txn.occurredAt.difference(similar[i - 1].txn.occurredAt).inHours / 24,
    ];
    for (final (label, period, lo, hi) in cadences) {
      final fitting = gaps.where((g) => g >= lo && g <= hi).length;
      if (fitting < 2 || fitting / gaps.length < 0.6) continue;
      final last = similar.last.txn.occurredAt;
      // Stale: missed more than two cycles.
      if (today.difference(last).inDays > period * 2 + hi - period) break;
      out.add(
        RecurringPayment(
          name: similar.last.txn.merchant ?? similar.last.txn.counterparty ?? e.key,
          cadence: label,
          periodDays: period,
          typicalMinor: median,
          count: similar.length,
          last: last,
          category: similar.last.category,
          payments: similar,
        ),
      );
      break;
    }
  }
  out.sort((a, b) => b.monthlyCostMinor.compareTo(a.monthlyCostMinor));
  return out;
}
