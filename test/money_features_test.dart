import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/features/budgets/budget_math.dart';
import 'package:pckt/features/recurring/recurring_detector.dart';
import 'package:pckt/ingestion/categorizer.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';
import 'package:pckt/ui/amount_field.dart';

var _id = 0;

Category cat(int id, String name, {bool income = false}) =>
    Category(id: id, name: name, icon: 'other', color: 0, isIncome: income, sortOrder: id);

TxnView txn(
  int minor,
  DateTime at, {
  Category? category,
  bool transfer = false,
  TxnDirection dir = TxnDirection.debit,
  String? merchant,
}) => TxnView(
  Transaction(
    id: ++_id,
    amountMinor: minor,
    direction: dir,
    occurredAt: at,
    merchant: merchant,
    categoryId: category?.id,
    mode: PaymentMode.upi,
    status: TxnStatus.confirmed,
    isTransfer: transfer,
    categoryLocked: false,
    createdAt: at,
  ),
  category,
  null,
);

Budget budget(int id, int minor, {int? categoryId, bool active = true}) =>
    Budget(id: id, categoryId: categoryId, amountMinor: minor, active: active, createdAt: DateTime(2026));

void main() {
  final food = cat(1, 'Food');
  final shop = cat(2, 'Shopping');
  final oct = DateTime(2026, 10);

  group('budget math', () {
    List<BudgetProgress> run(List<Budget> b, List<TxnView> t, {DateTime? now}) => budgetProgress(
      budgets: b,
      txns: t,
      categories: [food, shop],
      month: oct,
      now: now ?? DateTime(2026, 10, 20, 15),
    );

    test('only counts debits inside the month', () {
      final p = run(
        [budget(1, 1000000)],
        [
          txn(100000, DateTime(2026, 9, 30, 23, 59), category: food), // previous month
          txn(200000, DateTime(2026, 10, 1), category: food), // first instant
          txn(300000, DateTime(2026, 10, 31, 23, 59, 59), category: shop), // last second
          txn(400000, DateTime(2026, 11, 1), category: food), // next month
          txn(500000, DateTime(2026, 10, 5), dir: TxnDirection.credit), // income
        ],
      ).single;
      expect(p.isOverall, isTrue);
      expect(p.spentMinor, 500000);
      expect(p.level, BudgetLevel.ok);
    });

    test('transfers are excluded', () {
      final p = run(
        [budget(1, 1000000), budget(2, 100000, categoryId: food.id)],
        [
          txn(50000, DateTime(2026, 10, 3), category: food),
          txn(900000, DateTime(2026, 10, 4), category: food, transfer: true),
        ],
      );
      expect(p.first.spentMinor, 50000);
      expect(p.last.spentMinor, 50000);
      expect(p.last.ratio, 0.5);
    });

    test('per-category limits, warning and over budget', () {
      final p = run(
        [budget(1, 100000, categoryId: food.id), budget(2, 100000, categoryId: shop.id), budget(3, 1000000)],
        [txn(80000, DateTime(2026, 10, 2), category: food), txn(130000, DateTime(2026, 10, 2), category: shop)],
      );
      // Overall first, then categories nearest (or past) their limit.
      expect(p.map((x) => x.key), ['overall', 'cat2', 'cat1']);
      final shopP = p[1], foodP = p[2];
      expect(foodP.level, BudgetLevel.warning);
      expect(shopP.level, BudgetLevel.over);
      expect(shopP.remainingMinor, -30000);
      expect(shopP.perDayLeftMinor, 0);
      expect(p[0].spentMinor, 210000);
    });

    test('exactly at the limit is a warning, not over', () {
      final p = run([budget(1, 100000)], [txn(100000, DateTime(2026, 10, 2))]).single;
      expect(p.level, BudgetLevel.warning);
      expect(p.remainingMinor, 0);
    });

    test('inactive budgets and deleted categories are skipped', () {
      final p = run(
        [budget(1, 100000, active: false), budget(2, 100000, categoryId: 99)],
        [txn(1000, DateTime(2026, 10, 2))],
      );
      expect(p, isEmpty);
    });

    test('pace: per-day allowance for the rest of the month', () {
      final p = run([budget(1, 1200000)], [txn(600000, DateTime(2026, 10, 2))]).single;
      expect(p.daysLeft, 12); // 20th..31st inclusive
      expect(p.perDayLeftMinor, 50000);
    });

    test('days left at month boundaries', () {
      expect(daysLeftIn(oct, DateTime(2026, 10, 1)), 31);
      expect(daysLeftIn(oct, DateTime(2026, 10, 31, 23)), 1);
      expect(daysLeftIn(oct, DateTime(2026, 11, 1)), 0);
      expect(daysLeftIn(oct, DateTime(2026, 9, 15)), 31);
      expect(daysLeftIn(DateTime(2028, 2), DateTime(2028, 2, 1)), 29); // leap year
    });
  });

  group('budget alerts', () {
    BudgetProgress at(int spent, {int? categoryId}) => BudgetProgress(
      budget: budget(1, 100000, categoryId: categoryId),
      category: categoryId == null ? null : food,
      spentMinor: spent,
      daysLeft: 10,
    );

    test('fires 80% then 100% once each', () {
      expect(pendingBudgetAlerts([at(79000)], {}), isEmpty);
      final first = pendingBudgetAlerts([at(85000)], {});
      expect(first.map((a) => a.id), ['overall:80']);
      final sent = alertIdsToMark(first);
      expect(pendingBudgetAlerts([at(90000)], sent), isEmpty);
      final second = pendingBudgetAlerts([at(100000)], sent);
      expect(second.map((a) => a.id), ['overall:100']);
      expect(pendingBudgetAlerts([at(150000)], {...sent, ...alertIdsToMark(second)}), isEmpty);
    });

    test('jumping straight past 100% sends one alert and marks both', () {
      final a = pendingBudgetAlerts([at(120000, categoryId: food.id)], {});
      expect(a.map((x) => x.id), ['cat1:100']);
      expect(a.single.title, 'Food exceeded');
      expect(alertIdsToMark(a), {'cat1:80', 'cat1:100'});
    });
  });

  group('recurring detector', () {
    final today = DateTime(2026, 10, 19);

    test('detects weekly and quarterly cadences with monthly equivalents', () {
      final views = [
        for (var i = 0; i < 6; i++) txn(10000, DateTime(2026, 9, 1 + i * 7), merchant: 'Gym'),
        for (var i = 0; i < 3; i++) txn(150000, DateTime(2026, 2 + i * 3, 10), merchant: 'Insurance'),
      ];
      final found = detectRecurring(views, today: today);
      final byName = {for (final r in found) r.name: r};
      expect(byName['Gym']!.cadence, 'weekly');
      expect(byName['Insurance']!.cadence, 'quarterly');
      expect(byName['Gym']!.monthlyCostMinor, closeTo(10000 * 30.4 / 7, 0.01));
      expect(monthlyTotalMinor(found), (10000 * 30.4 / 7 + 150000 * 30.4 / 91).round());
    });

    test('ignores transfers, credits, stale and irregular payments', () {
      final views = [
        for (var i = 0; i < 4; i++) txn(500000, DateTime(2026, 6 + i, 1), merchant: 'Rent', transfer: true),
        for (var i = 0; i < 4; i++)
          txn(5000000, DateTime(2026, 6 + i, 1), merchant: 'Salary', dir: TxnDirection.credit),
        for (var i = 0; i < 4; i++) txn(19900, DateTime(2025, 10 + i, 3), merchant: 'Old app'),
        for (final d in [1, 4, 19, 20, 28]) txn(30000, DateTime(2026, 9, d), merchant: 'Swiggy'),
      ];
      expect(detectRecurring(views, today: today), isEmpty);
    });

    test('tolerates ±20% price changes and keeps the matching payments', () {
      final views = [
        txn(19900, DateTime(2026, 6, 15), merchant: 'Spotify'),
        txn(19900, DateTime(2026, 7, 15), merchant: 'Spotify'),
        txn(22900, DateTime(2026, 8, 15), merchant: 'spotify'),
        txn(22900, DateTime(2026, 9, 15), merchant: 'Spotify'),
        txn(99900, DateTime(2026, 9, 20), merchant: 'Spotify'), // annual gift card, not the plan
      ];
      final r = detectRecurring(views, today: today).single;
      expect(r.cadence, 'monthly');
      expect(r.payments, hasLength(4));
      expect(r.next, DateTime(2026, 10, 15));
      expect(r.isOverdue(today), isTrue);
    });
  });

  group('amount input', () {
    test('formats and parses Indian grouping', () {
      expect(amountInputText(12345600), '1,23,456');
      expect(amountInputText(150), '1.5');
      expect(amountInputText(105), '1.05');
      expect(parseAmountInput('1,23,456.5'), 12345650);
      expect(parseAmountInput(''), isNull);
      const f = IndianAmountFormatter();
      String type(String s) => f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: s)).text;
      expect(type('1234567'), '12,34,567');
      expect(type('0012.345'), '12.34');
      expect(type('.5'), '0.5');
    });
  });

  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(DatabaseConnection(NativeDatabase.memory())));
    tearDown(() => db.close());

    Future<Category> named(String n) async => (await db.allCategories()).firstWhere((c) => c.name == n);

    test('delete category moves transactions, rules and drops its budget', () async {
      final custom = await db.addCategory(name: 'Hobbies', icon: 'gaming', color: 1);
      final target = await named('Shopping');
      final t1 = await db.addManual(
        amountMinor: 1000,
        direction: TxnDirection.debit,
        at: DateTime(2026, 10, 1),
        categoryId: custom,
        merchant: 'Lego',
      );
      final t2 = await db.addManual(
        amountMinor: 2000,
        direction: TxnDirection.debit,
        at: DateTime(2026, 10, 2),
        categoryId: custom,
      );
      await db.setCategory(t1, custom, learnPattern: 'lego');
      await db.setBudget(categoryId: custom, amountMinor: 5000);
      expect(await db.countTxnsInCategory(custom), 2);

      await db.deleteCategory(custom, moveTo: target.id);

      final txns = await db.select(db.transactions).get();
      expect(txns.where((t) => t.id == t1 || t.id == t2).map((t) => t.categoryId), everyElement(target.id));
      expect(txns.where((t) => t.categoryId == custom), isEmpty);
      expect((await db.allMerchantRules()).single.categoryId, target.id);
      expect(await db.allBudgets(), isEmpty);
      expect((await db.allCategories()).any((c) => c.id == custom), isFalse);
    });

    test('Transfers and Other cannot be deleted; target must differ', () async {
      final transfers = await named('Transfers');
      final other = await named('Other');
      final food = await named('Food & Dining');
      await expectLater(db.deleteCategory(transfers.id, moveTo: food.id), throwsStateError);
      await expectLater(db.deleteCategory(other.id, moveTo: food.id), throwsStateError);
      await expectLater(db.deleteCategory(food.id, moveTo: food.id), throwsArgumentError);
      expect((await db.allCategories()).map((c) => c.id), containsAll([transfers.id, other.id, food.id]));
    });

    test('seeded categories remember their seed name after a rename', () async {
      final food = await named('Food & Dining');
      await db.updateCategory(food.id, name: 'Eating out');
      final renamed = (await db.allCategories()).firstWhere((c) => c.id == food.id);
      expect(renamed.seedName, 'Food & Dining');
      expect(AppDatabase.isProtected(await named('Other')), isTrue);
      // Built-in keywords still land in the renamed category.
      final categorizer = Categorizer(await db.allCategories(), const []);
      final parsed = ParsedTxn(
        amountMinor: 100,
        direction: TxnDirection.debit,
        occurredAt: DateTime(2026, 10, 1),
        mode: PaymentMode.upi,
        confidence: 1,
        merchant: 'Swiggy',
      );
      expect(categorizer.categorize(parsed, ''), food.id);
    });

    test('reorder writes a full ordering', () async {
      final ids = (await db.allCategories()).map((c) => c.id).toList().reversed.toList();
      await db.reorderCategories(ids);
      final ordered = await db.watchCategories().first;
      expect(ordered.map((c) => c.id), ids);
    });

    test('setBudget upserts one overall budget', () async {
      await db.setBudget(amountMinor: 1000);
      await db.setBudget(amountMinor: 2000);
      final b = await db.allBudgets();
      expect(b, hasLength(1));
      expect(b.single.amountMinor, 2000);
      expect(b.single.categoryId, isNull);
    });

    test('editing keeps source evidence; rename-all carries the rule', () async {
      final food = await named('Food & Dining');
      final a = await db.addManual(
        amountMinor: 1000,
        direction: TxnDirection.debit,
        at: DateTime(2026, 10, 1),
        merchant: 'SWIGGY LTD',
      );
      final b = await db.addManual(
        amountMinor: 2000,
        direction: TxnDirection.debit,
        at: DateTime(2026, 10, 2),
        merchant: 'swiggy ltd',
      );
      await db.setCategory(a, food.id, learnPattern: 'swiggy ltd');

      expect(await db.renameMerchant('SWIGGY LTD', 'Swiggy'), 2);
      await db.updateTxn(
        b,
        amountMinor: 2500,
        direction: TxnDirection.debit,
        occurredAt: DateTime(2026, 10, 3, 9),
        merchant: 'Swiggy',
        accountId: null,
        note: 'lunch',
      );
      final rows = await db.select(db.transactions).get();
      expect(rows.map((t) => t.merchant), everyElement('Swiggy'));
      final edited = rows.firstWhere((t) => t.id == b);
      expect(edited.amountMinor, 2500);
      expect(edited.note, 'lunch');
      expect(edited.occurredAt, DateTime(2026, 10, 3, 9));
      expect((await db.sourcesOf(b)).single.body, 'Added manually');
      final rules = {for (final r in await db.allMerchantRules()) r.pattern: r.categoryId};
      expect(rules, {'swiggy ltd': food.id, 'swiggy': food.id});
    });

    test('accounts: add cash, rename, archive', () async {
      final id = await db.addAccount(name: 'Cash', kind: AccountKind.cash, color: 1);
      await db.updateAccount(id, name: 'Wallet cash', archived: true);
      expect(await db.watchAccounts().first, isEmpty);
      final all = await db.watchAllAccounts().first;
      expect(all.single.name, 'Wallet cash');
      expect(all.single.kind, AccountKind.cash);
    });
  });

  test('v2 → v3 migration adds budgets and backfills seed names', () async {
    final dir = await Directory.systemTemp.createTemp('pckt_mig');
    final file = File('${dir.path}/db.sqlite');
    try {
      // Build a fresh DB, then strip it back to the v2 shape.
      var db = AppDatabase(NativeDatabase(file));
      await db.addCategory(name: 'Custom', icon: 'other', color: 1);
      await db.customStatement('DROP TABLE budgets');
      await db.customStatement('ALTER TABLE categories DROP COLUMN seed_name');
      await db.customStatement('PRAGMA user_version = 2');
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      final cats = await db.allCategories();
      expect(cats.firstWhere((c) => c.name == 'Transfers').seedName, 'Transfers');
      expect(cats.firstWhere((c) => c.name == 'Custom').seedName, isNull);
      expect(cats.map((c) => c.name).toSet().length, cats.length, reason: 'no seed duplicated');
      await db.setBudget(amountMinor: 100);
      expect(await db.allBudgets(), hasLength(1));
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
