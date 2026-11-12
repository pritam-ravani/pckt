import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/data/seed/category_aliases.dart';
import 'package:pckt/data/seed/default_categories.dart';
import 'package:pckt/features/activity/category_search.dart';

void main() {
  late AppDatabase db;
  late List<Category> cats;

  setUp(() async {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    cats = await db.allCategories();
  });
  tearDown(() => db.close());

  String? top(String q, {List<MerchantRule> rules = const []}) =>
      searchCategories(q, cats, rules: rules).firstOrNull?.category.name;

  test('finds a category by its name, start of a word, or part of it', () {
    expect(top('Groceries'), 'Groceries');
    expect(top('groc'), 'Groceries');
    expect(top('laund'), 'Laundry & Ironing');
    expect(top('footwear'), 'Clothes & Footwear');
  });

  test('everyday words find the category they belong under', () {
    expect(top('pharmacy'), 'Medicines');
    expect(top('chai'), 'Coffee & Snacks');
    expect(top('dhobi'), 'Laundry & Ironing');
    expect(top('petrol'), 'Fuel');
    expect(top('sutta'), 'Smoking & Paan');
    expect(top('bijli'), 'Electricity');
    expect(top('kiraya'), 'Rent & Home');
    expect(top('light bill'), 'Electricity');
  });

  test('merchant names find their category', () {
    expect(top('uber'), 'Cab & Auto');
    expect(top('swiggy'), 'Food Delivery');
    expect(top('zerodha'), 'Investments');
  });

  test('says which word matched, but not for a name match', () {
    final m = searchCategories('dhobi', cats).first;
    expect(m.via, 'dhobi');
    expect(searchCategories('Fuel', cats).first.via, isNull);
  });

  test('a name match ranks above an everyday word', () {
    // "fuel" is a category and also an alias; the category comes first.
    expect(searchCategories('fuel', cats).first.category.name, 'Fuel');
  });

  test('a renamed category is still found by its everyday words and old name', () async {
    final meds = cats.firstWhere((c) => c.name == 'Medicines');
    await db.updateCategory(meds.id, name: 'Dawa');
    cats = await db.allCategories();
    expect(top('pharmacy'), 'Dawa');
    expect(top('medicines'), 'Dawa');
  });

  test('a merchant you filed somewhere finds that category', () async {
    final health = cats.firstWhere((c) => c.name == 'Medicines');
    final t = await db.addManual(amountMinor: 18400, currency: 'INR', direction: TxnDirection.debit, at: DateTime(2026, 11, 12), merchant: 'Sharma Stores');
    await db.setCategory(t, health.id, learnPattern: 'sharma stores');
    final m = searchCategories('sharma', cats, rules: await db.allMerchantRules()).first;
    expect(m.category.name, 'Medicines');
    expect(m.via, 'sharma stores');
  });

  test('custom categories are searchable by name', () async {
    await db.addCategory(name: 'Cricket Kit', icon: 'other', color: 0);
    cats = await db.allCategories();
    expect(top('cricket'), 'Cricket Kit');
  });

  test('ignores case and punctuation, and an empty search finds nothing', () {
    expect(top('  PHARMACY!! '), 'Medicines');
    expect(searchCategories('   ', cats), isEmpty);
    expect(searchCategories('zzqx', cats), isEmpty);
  });

  test('every alias belongs to a real seed category', () {
    final names = {for (final s in defaultCategories) s.name};
    expect(categoryAliases.keys.where((k) => !names.contains(k)), isEmpty);
  });
}
