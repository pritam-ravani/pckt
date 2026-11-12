import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/ingestion/ingestion_service.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';
import 'package:pckt/ingestion/parser/sms_parser.dart';

void main() {
  group('bank-reported balance in SMS', () {
    int? bal(String sms) => SmsParser.reportedBalance(sms.toLowerCase(), 'INR');

    test('reads the common formats', () {
      expect(bal('Rs.250.00 debited from A/c XX1234 on 12-11-26. Avl Bal Rs.12,345.60'), 1234560);
      expect(bal('INR 500 spent. Avl Bal: INR 9,000'), 900000);
      expect(bal('Rs 100 credited to a/c **9733. Available balance is Rs 2,100.50'), 210050);
      expect(bal('Debited INR 80. A/c Bal INR 1,500'), 150000);
      expect(bal('Rs 20 debited. Bal Rs 980'), 98000);
    });

    test('a card\'s available limit is not a balance', () {
      expect(bal('Rs 500 spent on card XX1111. Avl Limit Rs 45,000'), isNull);
      expect(bal('Rs 500 spent. Available credit limit: Rs 45,000'), isNull);
    });

    test('no balance mentioned', () => expect(bal('Rs 250 debited from A/c XX1234 to Swiggy'), isNull));

    test('the parser keeps the payment amount and records the balance', () {
      final r = SmsParser(home: 'INR').parse(
        RawInput(
          source: SourceKind.sms,
          externalId: '1',
          sender: 'VM-AXISBK',
          body: 'INR 250.00 debited from A/c XX9733 on 12-11-26 to VPA shop@ybl. Avl Bal INR 12,000.00',
          receivedAt: DateTime(2026, 11, 12),
        ),
      );
      final txn = (r as Parsed).txn;
      expect(txn.amountMinor, 25000);
      expect(txn.balanceAfterMinor, 1200000);
    });
  });

  group('running balance', () {
    late AppDatabase db;
    late int account;
    final day = DateTime(2026, 11, 10, 12);

    setUp(() async {
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
      account = await db.addAccount(name: 'Axis', kind: AccountKind.bank, color: 0, currency: 'INR');
    });
    tearDown(() => db.close());

    Future<int> txn(int minor, DateTime at, {bool credit = false, int? reported, bool transfer = false, String currency = 'INR', int? converted}) async {
      final id = await db.addManual(
        amountMinor: minor,
        currency: currency,
        convertedMinor: converted,
        direction: credit ? TxnDirection.credit : TxnDirection.debit,
        at: at,
        accountId: account,
      );
      await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(balanceAfterMinor: Value(reported), isTransfer: Value(transfer)),
      );
      return id;
    }

    Future<AccountBalance> balance() async => (await db.balances()).firstWhere((b) => b.account.id == account);

    test('unknown until an opening balance is set', () async {
      await txn(100, day);
      expect((await balance()).isSet, isFalse);
    });

    test('opening balance plus credits minus debits after it', () async {
      await txn(99900, day.subtract(const Duration(days: 1)));
      await db.setOpeningBalance(account, 1000000, at: day);
      await txn(25000, day.add(const Duration(hours: 1)));
      await txn(500000, day.add(const Duration(hours: 2)), credit: true);
      expect((await balance()).balanceMinor, 1000000 - 25000 + 500000);
    });

    test('transfers between your own accounts move the balance too', () async {
      await db.setOpeningBalance(account, 1000000, at: day);
      await txn(300000, day.add(const Duration(hours: 1)), transfer: true);
      expect((await balance()).balanceMinor, 700000);
    });

    test('a foreign spend counts by its rupee amount, or is left out until converted', () async {
      await db.setOpeningBalance(account, 1000000, at: day);
      await txn(1250, day.add(const Duration(hours: 1)), currency: 'USD', converted: 104530);
      await txn(800, day.add(const Duration(hours: 2)), currency: 'USD');
      final b = await balance();
      expect(b.balanceMinor, 1000000 - 104530);
      expect(b.unconverted, 1);
    });

    test('compares with the latest balance the bank reported', () async {
      await db.setOpeningBalance(account, 1000000, at: day);
      await txn(25000, day.add(const Duration(hours: 1)), reported: 975000);
      expect((await balance()).differenceMinor, 0);
      // A ₹100 spend PennyWise never saw, then a reported balance.
      await txn(5000, day.add(const Duration(hours: 3)), reported: 960000);
      final b = await balance();
      expect(b.differenceMinor, -10000);
      expect(b.reported?.balanceAfterMinor, 960000);
    });

    test('using the bank\'s balance as the starting point makes them agree', () async {
      final id = await txn(25000, day, reported: 500000);
      final at = (await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle()).occurredAt;
      await db.setOpeningBalance(account, 500000, at: at);
      await txn(10000, day.add(const Duration(hours: 1)), reported: 490000);
      final b = await balance();
      expect(b.balanceMinor, 490000);
      expect(b.differenceMinor, 0);
    });

    test('a card balance goes negative as it is used and back up when paid', () async {
      final card = await db.addAccount(name: 'Card', kind: AccountKind.creditCard, color: 0, currency: 'INR');
      account = card;
      await db.setOpeningBalance(card, -200000, at: day);
      await txn(50000, day.add(const Duration(hours: 1)));
      await txn(200000, day.add(const Duration(hours: 2)), credit: true);
      expect((await balance()).balanceMinor, -50000);
    });

    test('clearing the opening balance stops tracking', () async {
      await db.setOpeningBalance(account, 1000000, at: day);
      await db.setOpeningBalance(account, null);
      expect((await balance()).isSet, isFalse);
    });

    test('an SMS balance is stored with the transaction and kept on merge', () async {
      final ingest = IngestionService(db);
      final at = day.add(const Duration(hours: 5));
      await ingest.ingestParsed([
        (
          RawInput(source: SourceKind.email, externalId: 'e1', sender: 'alerts@axisbank.com', body: 'debited', receivedAt: at),
          ParsedTxn(amountMinor: 7000, direction: TxnDirection.debit, occurredAt: at, mode: PaymentMode.upi, confidence: 1, currency: 'INR', reference: '111122223333'),
        ),
        (
          RawInput(source: SourceKind.sms, externalId: 's1', sender: 'VM-AXISBK', body: 'debited', receivedAt: at),
          ParsedTxn(amountMinor: 7000, direction: TxnDirection.debit, occurredAt: at, mode: PaymentMode.upi, confidence: 1, currency: 'INR', reference: '111122223333', balanceAfterMinor: 123400),
        ),
      ]);
      final rows = await (db.select(db.transactions)..where((t) => t.reference.equals('111122223333'))).get();
      expect(rows, hasLength(1));
      expect(rows.single.balanceAfterMinor, 123400);
    });
  });
}
