import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/backup/data_export.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/ingestion/ingestion_service.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';

AppDatabase memoryDb() => AppDatabase(DatabaseConnection(NativeDatabase.memory()));

Future<Map<String, List<Map<String, Object?>>>> dump(AppDatabase db) async => {
  for (final t in db.allTables)
    t.actualTableName: [
      for (final r in await db.customSelect('SELECT * FROM "${t.actualTableName}" ORDER BY 1').get()) r.data,
    ],
};

void main() {
  late AppDatabase db;
  final t0 = DateTime(2026, 10, 12, 20, 0);

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = memoryDb();
    final svc = IngestionService(db);
    await svc.ingest([
      RawInput(
        source: SourceKind.sms,
        externalId: '1',
        sender: 'VM-HDFCBK',
        body: 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345678',
        receivedAt: t0,
      ),
      RawInput(
        source: SourceKind.email,
        externalId: 'e1',
        sender: 'alerts@hdfcbank.net',
        body:
            'Dear Customer, Rs.250.00 has been debited from account **4521 to VPA swiggy@icici SWIGGY on 12-10-26. '
            'Your UPI transaction reference number is 528512345678.',
        receivedAt: t0.add(const Duration(hours: 1)),
      ),
      RawInput(
        source: SourceKind.sms,
        externalId: '2',
        sender: 'VM-HDFCBK',
        body: 'Your OTP is 123456',
        receivedAt: t0,
      ),
    ]);
    final cats = await db.allCategories();
    await db.addManual(
      amountMinor: 12345,
      direction: TxnDirection.debit,
      at: t0.add(const Duration(days: 1)),
      merchant: 'Chai, "Kadak" & Co',
      categoryId: cats.first.id,
      note: 'line one\nline two',
    );
    await db.into(db.merchantRules).insert(MerchantRulesCompanion.insert(pattern: 'swiggy', categoryId: cats.first.id));
  });
  tearDown(() => db.close());

  group('CSV', () {
    test('has the documented header and one row per transaction', () async {
      final rows = decodeCsv(await DataExport(db).transactionsCsv());
      expect(rows.first, DataExport.csvHeader);
      expect(rows, hasLength(1 + 2));
      final swiggy = rows[1];
      expect(swiggy[0], '2026-10-12 20:00:00');
      expect(swiggy[1], '250.00');
      expect(swiggy[2], 'debit');
      expect(swiggy[3], 'Swiggy');
      expect(swiggy[5], contains('4521'));
      expect(PaymentMode.values.map((m) => m.name), contains(swiggy[6]));
      expect(swiggy[7], '528512345678');
      expect(swiggy[9].split(';').toSet(), {'sms', 'email'});
    });

    test('quotes, commas and newlines survive a round trip', () async {
      final rows = decodeCsv(await DataExport(db).transactionsCsv());
      final manual = rows[2];
      expect(manual[1], '123.45');
      expect(manual[3], 'Chai, "Kadak" & Co');
      expect(manual[8], 'line one\nline two');
      expect(manual[9], 'manual');
    });

    test('encode/decode are inverses', () {
      final rows = [
        ['a', 'b,c', '"q"'],
        ['', ' lead', 'multi\r\nline'],
      ];
      expect(decodeCsv(encodeCsv(rows)), rows);
    });
  });

  group('JSON backup', () {
    test('round-trips every table exactly into a fresh database', () async {
      final json = await DataExport(db).backupJson();
      final fresh = memoryDb();
      addTearDown(fresh.close);
      final summary = await DataExport(fresh).restore(json);
      expect(summary.transactions, 2);
      expect(await dump(fresh), await dump(db));
    });

    test('restore replaces existing data', () async {
      final json = await DataExport(db).backupJson();
      final other = memoryDb();
      addTearDown(other.close);
      await other.addManual(amountMinor: 1, direction: TxnDirection.credit, at: t0, merchant: 'Old');
      await DataExport(other).restore(json);
      final merchants = (await other.select(other.transactions).get()).map((t) => t.merchant);
      expect(merchants, isNot(contains('Old')));
      expect(await dump(other), await dump(db));
    });

    test('ingestion keeps working after restore (ids continue)', () async {
      final json = await DataExport(db).backupJson();
      final fresh = memoryDb();
      addTearDown(fresh.close);
      await DataExport(fresh).restore(json);
      final id = await fresh.addManual(amountMinor: 500, direction: TxnDirection.debit, at: t0, merchant: 'New');
      final before = (await db.select(db.transactions).get()).map((t) => t.id);
      expect(before, isNot(contains(id)));
    });

    test('summary counts rows', () async {
      final s = DataExport(db).inspect(await DataExport(db).backupJson());
      expect(s.transactions, 2);
      expect(s.counts['raw_messages'], 4);
      expect(s.counts['merchant_rules'], 1);
      expect(s.schemaVersion, db.schemaVersion);
    });

    group('rejects', () {
      Future<void> rejects(String json) async {
        final before = await dump(db);
        await expectLater(DataExport(db).restore(json), throwsA(isA<BackupFormatException>()));
        expect(await dump(db), before, reason: 'nothing may change on a rejected restore');
      }

      test('non-JSON', () => rejects('hello'));
      test('other JSON', () => rejects('{"foo": 1}'));
      test('newer schema', () async {
        final m = jsonDecode(await DataExport(db).backupJson()) as Map<String, Object?>;
        m['schemaVersion'] = 999;
        await rejects(jsonEncode(m));
      });
      test('missing table', () async {
        final m = jsonDecode(await DataExport(db).backupJson()) as Map<String, Object?>;
        (m['tables']! as Map).remove('transactions');
        await rejects(jsonEncode(m));
      });
      test('broken foreign key rolls back', () async {
        final m = jsonDecode(await DataExport(db).backupJson()) as Map<String, Object?>;
        final rules = ((m['tables']! as Map)['merchant_rules'] as List).cast<Map<String, Object?>>();
        rules.first['category_id'] = 99999;
        final before = await dump(db);
        await expectLater(DataExport(db).restore(jsonEncode(m)), throwsA(anything));
        expect(await dump(db), before);
      });
    });
  });
}
