import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/features/activity/quick_entry.dart';

void main() {
  late AppDatabase db;
  final t0 = DateTime(2026, 11, 10, 13);

  setUp(() => db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true)));
  tearDown(() => db.close());

  Future<int> add(int minor, DateTime at, {String? merchant, int? categoryId, TxnDirection dir = TxnDirection.debit}) =>
      db.addManual(amountMinor: minor, currency: 'INR', direction: dir, at: at, merchant: merchant, categoryId: categoryId);

  test('manual entries keep the chosen payment type and account', () async {
    final account = await db.addAccount(name: 'HDFC', kind: AccountKind.bank, color: 0, currency: 'INR');
    final id = await db.addManual(
      amountMinor: 25000,
      currency: 'INR',
      direction: TxnDirection.debit,
      at: t0,
      mode: PaymentMode.upi,
      accountId: account,
    );
    final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    expect(row.mode, PaymentMode.upi);
    expect(row.accountId, account);
  });

  test('payment type still defaults to cash for other callers', () async {
    final id = await add(100, t0);
    final row = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    expect(row.mode, PaymentMode.cash);
  });

  group('merchant suggestions', () {
    test('most used first, ignoring case, with the latest spelling and category', () async {
      final cats = await db.allCategories();
      await add(100, t0.subtract(const Duration(days: 3)), merchant: 'chai point', categoryId: cats[1].id);
      await add(100, t0.subtract(const Duration(days: 2)), merchant: 'Chai Point', categoryId: cats[0].id);
      await add(500, t0, merchant: 'Zudio');

      final ranked = rankMerchants(await db.recentWithMerchant(TxnDirection.debit));
      expect(ranked.map((s) => s.name), ['Chai Point', 'Zudio']);
      expect(ranked.first.categoryId, cats[0].id);
      expect(ranked.last.categoryId, isNull);
    });

    test('equally used merchants are ordered by most recent', () async {
      await add(100, t0.subtract(const Duration(days: 2)), merchant: 'Older');
      await add(100, t0, merchant: 'Newer');
      final ranked = rankMerchants(await db.recentWithMerchant(TxnDirection.debit));
      expect(ranked.map((s) => s.name), ['Newer', 'Older']);
    });

    test('only the requested direction, no transfers, capped by limit', () async {
      await add(100, t0, merchant: 'Employer', dir: TxnDirection.credit);
      final transfer = await add(100, t0, merchant: 'Own account');
      await db.setTransfer(transfer, true);
      for (var i = 0; i < 12; i++) {
        await add(100 + i, t0, merchant: 'Shop $i');
      }
      final ranked = rankMerchants(await db.recentWithMerchant(TxnDirection.debit));
      expect(ranked, hasLength(8));
      expect(ranked.map((s) => s.name), isNot(contains('Employer')));
      expect(ranked.map((s) => s.name), isNot(contains('Own account')));
    });
  });

  group('duplicate warning', () {
    Future<Transaction?> find(int minor, DateTime at, {TxnDirection dir = TxnDirection.debit, String currency = 'INR'}) =>
        findLikelyDuplicate(db, amountMinor: minor, currency: currency, direction: dir, at: at);

    test('finds the closest same-amount payment within a day', () async {
      await add(45000, t0.subtract(const Duration(hours: 20)), merchant: 'Far');
      await add(45000, t0.subtract(const Duration(hours: 1)), merchant: 'Near');
      expect((await find(45000, t0))?.merchant, 'Near');
    });

    test('ignores other amounts, directions, currencies and days', () async {
      await add(45000, t0.subtract(const Duration(hours: 25)));
      await add(45000, t0, dir: TxnDirection.credit);
      await add(45001, t0);
      await db.addManual(amountMinor: 45000, currency: 'USD', direction: TxnDirection.debit, at: t0);
      expect(await find(45000, t0), isNull);
    });
  });
}
