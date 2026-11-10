import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../providers.dart';

/// A merchant offered as a one-tap shortcut when adding a transaction.
class MerchantSuggestion {
  const MerchantSuggestion(this.name, this.categoryId);
  final String name;

  /// The category most recently used with this merchant, if any.
  final int? categoryId;
}

/// Most-used merchants first, ties broken by the most recent. [newestFirst]
/// must be ordered newest to oldest. Names are matched ignoring case and the
/// latest spelling is the one shown.
List<MerchantSuggestion> rankMerchants(List<Transaction> newestFirst, {int limit = 8}) {
  final groups = groupBy(newestFirst.where((t) => t.merchant?.trim().isNotEmpty ?? false), (t) {
    return t.merchant!.trim().toLowerCase();
  }).values.toList();
  // A stable sort, so equally used merchants stay in most-recent order.
  final ranked = groups.sortedByCompare((g) => g.length, (a, b) => b.compareTo(a));
  return [
    for (final g in ranked.take(limit))
      MerchantSuggestion(g.first.merchant!.trim(), g.map((t) => t.categoryId).nonNulls.firstOrNull),
  ];
}

final merchantSuggestionsProvider = FutureProvider.autoDispose.family<List<MerchantSuggestion>, TxnDirection>((
  ref,
  direction,
) async {
  return rankMerchants(await ref.watch(databaseProvider).recentWithMerchant(direction));
});

/// The existing transaction closest in time to [at] with the same amount,
/// currency and direction within a day, or null. Used to warn before saving
/// a manual entry that SMS, email or an earlier entry already recorded.
Future<Transaction?> findLikelyDuplicate(
  AppDatabase db, {
  required int amountMinor,
  required String currency,
  required TxnDirection direction,
  required DateTime at,
}) async {
  final matches = await db.candidatesFor(
    amountMinor: amountMinor,
    currency: currency,
    direction: direction,
    at: at,
    window: const Duration(hours: 24),
  );
  return minBy<Transaction, Duration>(matches, (t) => t.occurredAt.difference(at).abs());
}
