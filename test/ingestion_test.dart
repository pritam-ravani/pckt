import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/ingestion/ingestion_service.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';

void main() {
  late AppDatabase db;
  late IngestionService svc;
  var seq = 0;

  RawInput msg(String sender, String body, DateTime at, {SourceKind source = SourceKind.sms}) =>
      RawInput(source: source, externalId: '${seq++}', sender: sender, body: body, receivedAt: at);

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    svc = IngestionService(db);
  });
  tearDown(() => db.close());

  final t0 = DateTime(2026, 10, 12, 20, 0);

  test('same UPI ref from SMS and email merges into one transaction', () async {
    await svc.ingest([
      msg('VM-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345678', t0),
      msg(
        'alerts@hdfcbank.net',
        'Dear Customer, Rs.250.00 has been debited from account **4521 to VPA swiggy@icici SWIGGY on 12-10-26. '
            'Your UPI transaction reference number is 528512345678.',
        t0.add(const Duration(hours: 2)),
        source: SourceKind.email,
      ),
    ]);
    final txns = await db.select(db.transactions).get();
    expect(txns, hasLength(1));
    expect(txns.single.status, TxnStatus.confirmed);
    expect(await db.sourcesOf(txns.single.id), hasLength(2));
  });

  test('two identical chai payments from the same bank stay separate', () async {
    await svc.ingest([
      msg('VM-KOTAKB', 'Sent Rs.20.00 from Kotak Bank AC X5555 to chaiwala@ybl on 12-10-26.', t0),
      msg(
        'VM-KOTAKB',
        'Sent Rs.20.00 from Kotak Bank AC X5555 to chaiwala@ybl on 12-10-26.',
        t0.add(const Duration(minutes: 3)),
      ),
    ]);
    expect(await db.select(db.transactions).get(), hasLength(2));
  });

  test('different refs never merge', () async {
    await svc.ingest([
      msg('VM-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345678', t0),
      msg('VM-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345679', t0),
    ]);
    expect(await db.select(db.transactions).get(), hasLength(2));
  });

  test('ref-less SMS + email close in time with same account merge', () async {
    await svc.ingest([
      msg('AD-HDFCBK', 'Spent Rs.1,299 On HDFC Bank Card 7788 At AMAZON On 2026-10-12:20:00:07.', t0),
      msg(
        'noreply@amazon.in',
        'Payment of Rs.1,299.00 debited from card ending 7788 at Amazon.',
        t0.add(const Duration(minutes: 4)),
        source: SourceKind.email,
      ),
    ]);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('candidates without a merchant do not crash dedup', () async {
    await svc.ingest([
      msg('VM-SBIINB', 'Rs.2000 withdrawn at SBI ATM from A/cX3456 on 12Oct26.', t0),
      msg('VM-SBIINB', 'Rs.2000 withdrawn at SBI ATM from A/cX3456 on 12Oct26.', t0.add(const Duration(hours: 1))),
      msg('VM-HDFCBK', 'Rs.2000.00 debited from A/c **4521 on 12-10-26.', t0.add(const Duration(hours: 2))),
    ]);
    expect(await db.select(db.transactions).get(), hasLength(3));
  });

  test('re-ingesting the same message is a no-op', () async {
    final m = msg('VM-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345678', t0);
    await svc.ingest([m]);
    final r = await svc.ingest([m]);
    expect(r.seen, 0);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('debit from one own account + credit to another is a self-transfer', () async {
    await svc.ingest([
      msg(
        'VM-HDFCBK',
        'Rs.10,000.00 debited from A/c **4521 on 12-10-26 via IMPS to ASHA K. IMPS Ref 628512345678',
        t0,
      ),
      msg(
        'VM-ICICIB',
        'Your A/c XX123 has been credited with INR 10,000.00 on 12-Oct-26 by IMPS from ASHA K.',
        t0.add(const Duration(minutes: 1)),
      ),
    ]);
    final txns = await db.select(db.transactions).get();
    expect(txns, hasLength(2));
    expect(txns.every((t) => t.isTransfer), isTrue);
    expect(await db.select(db.accounts).get(), hasLength(2));
  });

  test('resetSource drops SMS-only transactions but keeps manual ones', () async {
    await svc.ingest([
      msg('VM-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345678', t0),
    ]);
    await db.addManual(amountMinor: 5000, direction: TxnDirection.debit, at: t0, merchant: 'Chai');
    await db.resetSource(SourceKind.sms);
    final left = await db.select(db.transactions).get();
    expect(left.map((t) => t.merchant), ['Chai']);
    expect(await db.knownExternalIds(SourceKind.sms), isEmpty);
  });

  test('ignored and categorised', () async {
    final r = await svc.ingest([
      msg('VM-HDFCBK', '123456 is your OTP for txn of Rs.2,000 at AMAZON.', t0),
      msg(
        'JD-ICICIT',
        'ICICI Bank Acct XX123 debited for Rs 180.00 on 12-Oct-26; ZOMATO LTD credited. UPI:528598765432.',
        t0,
      ),
    ]);
    expect(r.ignored, 1);
    final view = (await db.watchTxns().first).single;
    expect(view.category?.name, 'Food & Dining');
    expect(view.account?.name, 'ICICI Bank');
  });
}
