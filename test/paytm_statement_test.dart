import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/ingestion/ingestion_service.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';
import 'package:pckt/ingestion/statement/paytm_statement.dart';
import 'package:pckt/ingestion/statement/statement_import.dart';

const _header = [
  'Date',
  'Time',
  'Transaction Details',
  'Other Transaction Details (UPI ID or A/c No)',
  'Your Account',
  'Amount',
  'UPI Ref No.',
  'Order ID',
  'Remarks',
  'Tags',
  'Comment',
];

List<int> xlsx(List<List<String>> rows, {List<String> header = _header}) {
  final strings = <String>[];
  String sheet(List<List<String>> data) {
    final out = StringBuffer('<worksheet xmlns="m"><sheetData>');
    for (final (r, row) in data.indexed) {
      out.write('<row r="${r + 1}">');
      for (final (c, value) in row.indexed) {
        if (value.isEmpty) continue;
        strings.add(value);
        out.write('<c r="${String.fromCharCode(65 + c)}${r + 1}" t="s"><v>${strings.length - 1}</v></c>');
      }
      out.write('</row>');
    }
    return '$out</sheetData></worksheet>';
  }

  final summary = sheet([
    ['Summary of your payments'],
  ]);
  final history = sheet([header, ...rows]);
  final shared = strings.map((s) => '<si><t>${const HtmlEscape().convert(s)}</t></si>').join();
  void add(Archive a, String name, String text) => a.addFile(ArchiveFile.bytes(name, utf8.encode(text)));
  final archive = Archive();
  add(archive, 'xl/sharedStrings.xml', '<sst xmlns="m">$shared</sst>');
  add(archive, 'xl/worksheets/sheet1.xml', summary);
  add(archive, 'xl/worksheets/sheet2.xml', history);
  return ZipEncoder().encode(archive);
}

List<String> row(
  String amount,
  String details,
  String tag, {
  String ref = '111111111111',
  String date = '15/10/2026',
  String time = '13:45:10',
  String remarks = '',
}) => [date, time, details, 'shop@ybl on PhonePe', 'Axis Bank - 42', amount, ref, '', remarks, tag, ''];

void main() {
  group('parsing', () {
    test('reads the history sheet by column name, keeping exact paise', () {
      final file = PaytmStatement.parse(xlsx([row('-1,234.50', 'Paid to Chai & Co', '#🥘 Food', remarks: '👔 Team')]));
      expect(file.skipped, 0);
      final r = file.rows.single;
      expect(r.occurredAt, DateTime(2026, 10, 15, 13, 45, 10));
      expect(r.amountMinor, 123450);
      expect(r.remarks, '👔 Team');
      expect(PaytmStatement.tagKey(r.tag), 'food');
    });

    test('maps a row to a UPI transaction', () {
      final txn = PaytmStatement.toParsed(PaytmStatement.parse(xlsx([row('-20.00', 'Paid to Chai', '#🥘 Food')])).rows.single);
      expect(txn.direction, TxnDirection.debit);
      expect(txn.mode, PaymentMode.upi);
      expect(txn.currency, 'INR');
      expect(txn.merchant, 'Chai');
      expect(txn.counterparty, 'shop@ybl');
      expect(txn.accountHint, '42');
      expect(txn.institution, 'Axis Bank');
      expect(txn.reference, '111111111111');
      expect(txn.transferHint, isFalse);
    });

    test('credits have +, and an unsigned amount is a transfer between own accounts', () {
      final rows = PaytmStatement.parse(
        xlsx([
          row('+500.00', 'Received from Friend', '#💵 Money Received', ref: '1'),
          row('15,000.00', 'Self transfer', '#💵 Self Transfer', ref: '2'),
        ]),
      ).rows;
      expect(rows[0].isCredit, isTrue);
      expect(rows[0].isSelfTransfer, isFalse);
      expect(rows[1].isSelfTransfer, isTrue);
    });

    test('counts unreadable rows without losing the others', () {
      final file = PaytmStatement.parse(xlsx([row('abc', 'Paid to A', '', ref: '1'), row('-1.00', 'Paid to B', '', ref: '2')]));
      expect(file.rows, hasLength(1));
      expect(file.skipped, 1);
    });

    test('rejects other files with a clear message', () {
      expect(() => PaytmStatement.parse(utf8.encode('%PDF-1.7')), throwsA(isA<StatementFormatException>()));
      expect(
        () => PaytmStatement.parse(xlsx([], header: ['Name', 'Value'])),
        throwsA(isA<StatementFormatException>()),
      );
    });
  });

  group('import', () {
    late AppDatabase db;
    late PaytmStatementImporter importer;

    setUp(() {
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
      importer = PaytmStatementImporter(db, IngestionService(db));
    });
    tearDown(() => db.close());

    Future<Transaction> byRef(String ref) => (db.select(db.transactions)..where((t) => t.reference.equals(ref))).getSingle();
    Future<String?> categoryOf(Transaction t) async =>
        (await db.allCategories()).where((c) => c.id == t.categoryId).firstOrNull?.name;

    test('tags choose categories, and money transfers count as spending', () async {
      await importer.import(
        xlsx([
          row('-100.00', 'Paid to Cafe', '#🥘 Food', ref: '1'),
          row('-2000.00', 'Money sent to Asha', '#💵 Money Transfer', ref: '2'),
        ]),
      );
      final food = await byRef('1');
      final sent = await byRef('2');
      expect(await categoryOf(food), 'Food & Dining');
      expect(await categoryOf(sent), 'People');
      expect(sent.isTransfer, isFalse);
      expect(sent.status, TxnStatus.confirmed);
    });

    test('an unknown tag becomes its own category', () async {
      final result = await importer.import(xlsx([row('-1000.00', 'Paid to Store', '#🛏️ Furniture EMI', ref: '1')]));
      expect(result.newCategories, ['Furniture EMI']);
      expect(await categoryOf(await byRef('1')), 'Furniture EMI');
    });

    test('self transfers are kept out of spending and income', () async {
      await importer.import(xlsx([row('15,000.00', 'Self transfer', '#💵 Self Transfer', ref: '1')]));
      final t = await byRef('1');
      expect(t.isTransfer, isTrue);
      expect(await categoryOf(t), 'Transfers');
    });

    test('importing the same file twice adds nothing', () async {
      final bytes = xlsx([row('-20.00', 'Paid to Chai', '#🥘 Food', ref: '1'), row('-20.00', 'Paid to Chai', '#🥘 Food', ref: '2')]);
      final first = await importer.import(bytes);
      final second = await importer.import(bytes);
      expect(first.added, 2);
      expect(second.added, 0);
      expect(second.alreadyImported, 2);
      expect(await db.select(db.transactions).get(), hasLength(2));
    });

    test('a payment already read from SMS merges by reference and takes the tag', () async {
      final at = DateTime(2026, 10, 15, 13, 45);
      await IngestionService(db).ingestParsed([
        (
          RawInput(source: SourceKind.sms, externalId: 's1', sender: 'VM-AXISBK', body: 'debited', receivedAt: at),
          ParsedTxn(amountMinor: 45000, direction: TxnDirection.debit, occurredAt: at, mode: PaymentMode.upi, confidence: 1, reference: '999', currency: 'INR'),
        ),
      ]);
      final result = await importer.import(xlsx([row('-450.00', 'Paid to Cafe', '#🥘 Food', ref: '999', remarks: 'Lunch')]));
      expect(result.merged, 1);
      expect(result.added, 0);
      final all = await db.select(db.transactions).get();
      expect(all, hasLength(1));
      expect(await categoryOf(all.single), 'Food & Dining');
      expect(all.single.note, 'Lunch');
    });

    test('a category the user set by hand is not overwritten', () async {
      final at = DateTime(2026, 10, 15, 13, 45);
      final cats = await db.allCategories();
      final shopping = cats.firstWhere((c) => c.name == 'Shopping');
      await IngestionService(db).ingestParsed([
        (
          RawInput(source: SourceKind.sms, externalId: 's1', sender: 'VM-AXISBK', body: 'debited', receivedAt: at),
          ParsedTxn(amountMinor: 45000, direction: TxnDirection.debit, occurredAt: at, mode: PaymentMode.upi, confidence: 1, reference: '999', currency: 'INR'),
        ),
      ]);
      final id = (await db.select(db.transactions).getSingle()).id;
      await db.setCategory(id, shopping.id);
      await importer.import(xlsx([row('-450.00', 'Paid to Cafe', '#🥘 Food', ref: '999')]));
      expect((await db.select(db.transactions).getSingle()).categoryId, shopping.id);
    });
  });
}
