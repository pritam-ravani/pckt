import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/core/currency.dart';
import 'package:pckt/data/backup/data_export.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/features/budgets/budget_math.dart';
import 'package:pckt/features/stats.dart';
import 'package:pckt/ingestion/ingestion_service.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';
import 'package:pckt/llm/agent/finance_agent.dart';
import 'package:pckt/llm/agent/finance_tools.dart';
import 'package:pckt/llm/llm_client.dart';
import 'package:pckt/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase memoryDb() => AppDatabase(DatabaseConnection(NativeDatabase.memory()));

Future<Map<String, List<Map<String, Object?>>>> dump(AppDatabase db) async => {
  for (final t in db.allTables)
    t.actualTableName: [
      for (final r in await db.customSelect('SELECT * FROM "${t.actualTableName}" ORDER BY 1').get()) r.data,
    ],
};

void main() {
  final t0 = DateTime(2026, 10, 12, 20, 0);
  var seq = 0;
  RawInput sms(String sender, String body, DateTime at) =>
      RawInput(source: SourceKind.sms, externalId: '${seq++}', sender: sender, body: body, receivedAt: at);

  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDown(() => Currencies.home = 'INR');

  test('v3 → v4 migration keeps every row and marks it INR', () async {
    final dir = await Directory.systemTemp.createTemp('pckt_mig4');
    final file = File('${dir.path}/db.sqlite');
    try {
      var db = AppDatabase(NativeDatabase(file));
      final acct = await db.addAccount(name: 'HDFC', kind: AccountKind.bank, color: 1);
      final id = await db.addManual(amountMinor: 25000, direction: TxnDirection.debit, at: t0, accountId: acct);
      await db.setBudget(amountMinor: 1000000);
      // Strip back to the v3 shape.
      for (final (table, col) in const [
        ('transactions', 'currency'),
        ('transactions', 'converted_minor'),
        ('transactions', 'converted_currency'),
        ('accounts', 'currency'),
        ('budgets', 'currency'),
      ]) {
        await db.customStatement('ALTER TABLE $table DROP COLUMN $col');
      }
      await db.customStatement('PRAGMA user_version = 3');
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      final t = (await db.select(db.transactions).get()).single;
      expect(t.id, id);
      expect((t.amountMinor, t.currency, t.convertedMinor, t.convertedCurrency), (25000, 'INR', null, null));
      expect((await db.allAccounts()).single.currency, 'INR');
      expect((await db.allBudgets()).single.currency, 'INR');
      expect(await db.customSelect('PRAGMA user_version').map((r) => r.data.values.first).getSingle(), 4);
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  group('ingestion', () {
    late AppDatabase db;
    setUp(() => db = memoryDb());
    tearDown(() => db.close());

    test('an Indian card spend abroad is stored in its currency and kept out of rupee totals', () async {
      await IngestionService(db).ingest([
        sms('VM-HDFCBK', 'Spent USD 12.50 On HDFC Bank Card 1234 At AMAZON WEB SERVICES On 2026-10-12:20:01:07.', t0),
        sms('VM-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345678', t0),
      ]);
      final views = await db.watchTxns().first;
      final usd = views.firstWhere((v) => v.txn.currency == 'USD').txn;
      expect(usd.amountMinor, 1250);
      expect(usd.homeMinor, isNull);
      expect(usd.isForeign, isTrue);
      expect(views.firstWhere((v) => v.txn.currency == 'INR').account?.currency, 'INR');

      var stats = MonthStats(views, DateTime(2026, 10));
      expect((stats.spent, stats.unconverted), (25000, 1));

      // The user enters what the bank charged; now it counts.
      await db.setConversion(usd.id, minor: 104530, currency: 'INR');
      stats = MonthStats(await db.watchTxns().first, DateTime(2026, 10));
      expect((stats.spent, stats.unconverted), (25000 + 104530, 0));
    });

    test('a stated equivalent counts at once, and a rupee-only alert for it is found by dedup', () async {
      await IngestionService(db).ingest([
        sms(
          'JD-SBICRD-S',
          'Transaction of USD 12.50 (INR 1,045.30) done on your SBI Card ending 5678 at NETFLIX.COM on 12/10/26.',
          t0,
        ),
      ]);
      final t = (await db.select(db.transactions).get()).single;
      expect((t.currency, t.amountMinor, t.convertedMinor, t.convertedCurrency), ('USD', 1250, 104530, 'INR'));
      expect(t.homeMinor, 104530);
      final found = await db.candidatesFor(
        amountMinor: 104530,
        currency: 'INR',
        direction: TxnDirection.debit,
        at: t0.add(const Duration(hours: 2)),
      );
      expect(found.map((c) => c.id), [t.id]);
      // Same number in another currency is not a duplicate.
      expect(
        await db.candidatesFor(amountMinor: 1250, currency: 'INR', direction: TxnDirection.debit, at: t0),
        isEmpty,
      );
    });

    test('a non-INR home reads bare amounts in it and creates accounts in it', () async {
      Currencies.home = 'AED';
      await IngestionService(db, homeCurrency: 'AED').ingest([
        sms('ENBD', 'Purchase of AED 120.50 with Debit Card ending 4321 at CARREFOUR on 12/10/2026.', t0),
        sms('ENBD', 'Your account XXXX4321 was debited for 75.00 at ADNOC on 12/10/2026.', t0),
      ]);
      final txns = await db.select(db.transactions).get();
      expect(txns.map((t) => (t.amountMinor, t.currency)).toSet(), {(12050, 'AED'), (7500, 'AED')});
      expect(txns.every((t) => t.status == TxnStatus.needsReview), isTrue, reason: 'unknown sender');
      expect((await db.allAccounts()).single.currency, 'AED');
    });

    test('messages v1.0 skipped (foreign amounts, "was used for") are picked up without a re-import', () async {
      final body = 'Spent USD 12.50 On HDFC Bank Card 1234 At AWS On 2026-10-12:20:01:07.';
      await db
          .into(db.rawMessages)
          .insert(
            RawMessagesCompanion.insert(
              source: SourceKind.sms,
              externalId: 'old',
              sender: 'VM-HDFCBK',
              body: body,
              receivedAt: t0,
              parseStatus: ParseStatus.ignored,
              ignoreReason: const Value('No amount'),
            ),
          );
      await db
          .into(db.rawMessages)
          .insert(
            RawMessagesCompanion.insert(
              source: SourceKind.sms,
              externalId: 'otp',
              sender: 'VM-HDFCBK',
              body: 'Pay Rs 500 later',
              receivedAt: t0,
              parseStatus: ParseStatus.ignored,
              ignoreReason: const Value('Not a transaction'),
            ),
          );
      await db
          .into(db.rawMessages)
          .insert(
            RawMessagesCompanion.insert(
              source: SourceKind.sms,
              externalId: 'kotak',
              sender: 'AX-KOTAKB',
              body: 'Your Kotak Bank Debit Card XX1234 was used for Rs.640.00 at ZOMATO on 12/10/2026.',
              receivedAt: t0,
              parseStatus: ParseStatus.pendingLlm,
              ignoreReason: const Value('Could not tell debit from credit'),
            ),
          );
      expect(await IngestionService(db).reparseSkipped(), 2);
      final txns = await db.select(db.transactions).get();
      expect(txns.map((t) => (t.amountMinor, t.currency)).toSet(), {(1250, 'USD'), (64000, 'INR')});
      final raws = {for (final r in await db.select(db.rawMessages).get()) r.externalId: r.parseStatus};
      expect(raws, {'old': ParseStatus.parsed, 'otp': ParseStatus.ignored, 'kotak': ParseStatus.parsed});
    });
  });

  test('assistant tools total in the home currency and flag foreign rows', () async {
    final db = memoryDb();
    addTearDown(db.close);
    await db.addManual(amountMinor: 25000, direction: TxnDirection.debit, at: t0, merchant: 'Swiggy');
    await db.addManual(amountMinor: 1250, currency: 'USD', direction: TxnDirection.debit, at: t0, merchant: 'AWS');
    await db.addManual(
      amountMinor: 999,
      currency: 'USD',
      convertedMinor: 83000,
      direction: TxnDirection.debit,
      at: t0,
      merchant: 'Netflix',
    );
    final tools = FinanceTools(db, now: () => t0);
    final q = (await tools.queryTransactions({'from': '2026-10-01', 'to': '2026-10-31'})).json;
    expect(q['currency'], 'INR');
    expect(q['total_debit'], 250 + 830);
    expect(q['total_debit_formatted'], '₹1,080');
    expect(q['not_in_totals'], 1);
    final rows = {for (final r in (q['transactions'] as List).cast<Map<String, dynamic>>()) r['merchant']: r};
    expect(rows['Swiggy']!.containsKey('currency'), isFalse);
    expect((rows['AWS']!['amount'], rows['AWS']!['currency'], rows['AWS']!['in_totals']), (12.5, 'USD', false));
    expect((rows['Netflix']!['currency'], rows['Netflix']!['home_amount']), ('USD', 830.0));
    final s = (await tools.spendingSummary({'from': '2026-10-01', 'to': '2026-10-31', 'group_by': 'merchant'})).json;
    expect((s['total'], s['not_in_totals']), (1080.0, 1));
    expect(
      FinanceAgent(client: _NoClient(), tools: tools, now: () => t0).systemPrompt(),
      contains('Indian Rupee (INR)'),
    );
    Currencies.home = 'AED';
    expect(FinanceAgent(client: _NoClient(), tools: tools, now: () => t0).systemPrompt(), isNot(contains('₹')));
  });

  test('budgets only apply in the currency they were set in', () async {
    final b = Budget(id: 1, categoryId: null, amountMinor: 1000000, currency: 'INR', active: true, createdAt: t0);
    List<BudgetProgress> run() =>
        budgetProgress(budgets: [b], txns: const [], categories: const [], month: DateTime(2026, 10), now: t0);
    expect(run(), hasLength(1));
    Currencies.home = 'USD';
    expect(run(), isEmpty);
  });

  group('backup', () {
    late AppDatabase db;
    setUp(() async {
      db = memoryDb();
      await IngestionService(db).ingest([
        sms(
          'JD-SBICRD-S',
          'Transaction of USD 12.50 (INR 1,045.30) done on your SBI Card ending 5678 at NETFLIX.COM on 12/10/26.',
          t0,
        ),
      ]);
      await db.addManual(amountMinor: 1200, currency: 'JPY', direction: TxnDirection.debit, at: t0, merchant: 'Lawson');
      await db.addAccount(name: 'Wise USD', kind: AccountKind.wallet, color: 1, currency: 'USD');
      await db.setBudget(amountMinor: 50000, currency: 'INR');
    });
    tearDown(() => db.close());

    test('round-trips currencies exactly', () async {
      final json = await DataExport(db).backupJson();
      final fresh = memoryDb();
      addTearDown(fresh.close);
      await DataExport(fresh).restore(json);
      expect(await dump(fresh), await dump(db));
      final txns = await fresh.select(fresh.transactions).get();
      expect(txns.map((t) => t.currency).toSet(), {'USD', 'JPY'});
    });

    test('a v1.0 (schema 3) backup restores with everything in INR', () async {
      final m = jsonDecode(await DataExport(db).backupJson()) as Map<String, Object?>;
      m['schemaVersion'] = 3;
      final tables = (m['tables']! as Map).cast<String, Object?>();
      for (final name in ['transactions', 'accounts', 'budgets']) {
        for (final row in (tables[name]! as List).cast<Map<String, Object?>>()) {
          row
            ..remove('currency')
            ..remove('converted_minor')
            ..remove('converted_currency');
        }
      }
      final fresh = memoryDb();
      addTearDown(fresh.close);
      final summary = await DataExport(fresh).restore(jsonEncode(m));
      expect(summary.schemaVersion, 3);
      final txns = await fresh.select(fresh.transactions).get();
      expect(txns, hasLength(2));
      expect(txns.every((t) => t.currency == 'INR' && t.convertedMinor == null), isTrue);
      expect((await fresh.allAccounts()).every((a) => a.currency == 'INR'), isTrue);
      expect((await fresh.allBudgets()).single.currency, 'INR');
    });

    test('CSV has the currency columns, with per-currency decimals', () async {
      final rows = decodeCsv(await DataExport(db).transactionsCsv());
      final h = rows.first;
      expect(h.sublist(h.length - 3), ['currency', 'converted_amount', 'converted_currency']);
      final byCurrency = {for (final r in rows.skip(1)) r[h.indexOf('currency')]: r};
      expect(byCurrency['USD']![1], '12.50');
      expect(byCurrency['USD']![h.indexOf('converted_amount')], '1045.30');
      expect(byCurrency['USD']![h.indexOf('converted_currency')], 'INR');
      expect(byCurrency['JPY']![1], '1200');
      expect(byCurrency['JPY']![h.indexOf('converted_amount')], '');
    });
  });

  group('home currency setting', () {
    Future<ProviderContainer> container(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(await SharedPreferences.getInstance())]);
      addTearDown(c.dispose);
      return c;
    }

    test('an existing install keeps INR and pins it', () async {
      final c = await container({PrefKeys.onboarded: true});
      expect(c.read(homeCurrencyProvider), 'INR');
      expect(c.read(prefsProvider).getString(PrefKeys.homeCurrency), 'INR');
    });

    test('a new install starts from the device locale', () async {
      final c = await container({});
      expect(c.read(homeCurrencyProvider), defaultCurrencyForLocale(PlatformDispatcher.instance.locale.toString()));
      expect(c.read(prefsProvider).getString(PrefKeys.homeCurrency), isNull, reason: 'pinned at onboarding');
      c.read(onboardedProvider.notifier).complete();
      expect(c.read(prefsProvider).getString(PrefKeys.homeCurrency), c.read(homeCurrencyProvider));
    });

    test('changing it updates formatting', () async {
      final c = await container({PrefKeys.homeCurrency: 'INR', PrefKeys.onboarded: true});
      expect(c.read(homeCurrencyProvider), 'INR');
      await c.read(homeCurrencyProvider.notifier).set('GBP');
      expect(Currencies.home, 'GBP');
      expect(formatMoney(1250), '£12.50');
      expect(c.read(prefsProvider).getString(PrefKeys.homeCurrency), 'GBP');
    });
  });
}

class _NoClient implements LlmClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
