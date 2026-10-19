import '../data/db/database.dart';

class CategoryTotal {
  const CategoryTotal(this.category, this.amount);
  final Category? category;
  final int amount;
}

/// Aggregates for one month. Transfers are excluded everywhere.
class MonthStats {
  MonthStats(List<TxnView> txns, DateTime month)
    : daily = List.filled(DateTime(month.year, month.month + 1, 0).day, 0) {
    final byCat = <int?, CategoryTotal>{};
    for (final v in txns) {
      final t = v.txn;
      if (t.isTransfer) continue;
      if (t.direction == TxnDirection.credit) {
        income += t.amountMinor;
        continue;
      }
      spent += t.amountMinor;
      count++;
      if (t.occurredAt.year == month.year && t.occurredAt.month == month.month) {
        daily[t.occurredAt.day - 1] += t.amountMinor;
      }
      final prev = byCat[t.categoryId];
      byCat[t.categoryId] = CategoryTotal(v.category, (prev?.amount ?? 0) + t.amountMinor);
    }
    categories = byCat.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
  }

  int spent = 0;
  int income = 0;
  int count = 0;
  final List<int> daily;
  late final List<CategoryTotal> categories;

  int get net => income - spent;
}

class MerchantTotal {
  const MerchantTotal(this.name, this.amount, this.count, this.category);
  final String name;
  final int amount;
  final int count;
  final Category? category;
}

List<MerchantTotal> topMerchants(List<TxnView> txns, {int take = 5}) {
  final m = <String, (int, int, Category?)>{};
  for (final v in txns) {
    final t = v.txn;
    if (t.isTransfer || t.direction == TxnDirection.credit || t.merchant == null) continue;
    final p = m[t.merchant!];
    m[t.merchant!] = ((p?.$1 ?? 0) + t.amountMinor, (p?.$2 ?? 0) + 1, v.category);
  }
  final list = [for (final e in m.entries) MerchantTotal(e.key, e.value.$1, e.value.$2, e.value.$3)]
    ..sort((a, b) => b.amount.compareTo(a.amount));
  return list.take(take).toList();
}
