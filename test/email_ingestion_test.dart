import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/core/secrets.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/ingestion/email/email_source.dart';
import 'package:pckt/ingestion/email/email_sync.dart';
import 'package:pckt/ingestion/ingestion_service.dart';
import 'package:pckt/ingestion/parser/email_parser.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';
import 'package:pckt/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final t0 = DateTime(2026, 10, 12, 20, 0);
var _seq = 0;

RawInput sms(String sender, String body, DateTime at) =>
    RawInput(source: SourceKind.sms, externalId: 'sms-${_seq++}', sender: sender, body: body, receivedAt: at);

RawInput email(String from, String subject, String body, DateTime at, {String? id}) =>
    emailToRawInput(externalId: id ?? '<${_seq++}@mail>', from: from, subject: subject, date: at, plain: body);

RawInput swiggyReceipt(DateTime at, {String total = '475.00'}) => email(
  'Swiggy <noreply@swiggy.in>',
  'Your Swiggy order was successfully delivered',
  'Restaurant: Meghana Foods\nItem Total ₹420.00\nDelivery Fee ₹30.00\nOrder Total ₹$total\nPaid Via UPI',
  at,
);

void main() {
  late AppDatabase db;
  late IngestionService svc;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    svc = IngestionService(db, parsers: const {SourceKind.email: EmailParser()});
  });
  tearDown(() => db.close());

  group('SMS + email dedup', () {
    test('bank SMS + bank email with the same ref → one transaction', () async {
      await svc.ingest([
        sms('VM-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345678', t0),
        email(
          'HDFC Bank InstaAlerts <alerts@hdfcbank.net>',
          'You have done a UPI txn. Check details!',
          'Dear Customer, Rs.250.00 has been debited from account 4521 to VPA swiggy.stores@axb SWIGGY on 12-10-26. '
              'Your UPI transaction reference number is 528512345678. Never share your OTP with anyone.',
          t0.add(const Duration(hours: 3)),
        ),
      ]);
      final txns = await db.select(db.transactions).get();
      expect(txns, hasLength(1));
      final sources = await db.sourcesOf(txns.single.id);
      expect(sources.map((s) => s.source).toSet(), {SourceKind.sms, SourceKind.email});
      expect(sources.firstWhere((s) => s.source == SourceKind.email).parseStatus, ParseStatus.merged);
    });

    test('bank SMS without merchant + Swiggy receipt 20 min later → one txn named Swiggy', () async {
      await svc.ingest([
        sms(
          'VM-HDFCBK',
          'Rs.475.00 debited from A/c **4521 on 12-10-26. UPI Ref 528512345678. Not you? Call 18002586161',
          t0,
        ),
      ]);
      final before = await db.select(db.transactions).getSingle();
      expect(before.merchant, isNull);

      final r = await svc.ingest([swiggyReceipt(t0.add(const Duration(minutes: 20)))]);
      expect(r.merged, 1);
      final view = (await db.watchTxns().first).single;
      expect(view.txn.merchant, 'Swiggy');
      expect(view.txn.reference, '528512345678');
      expect(view.txn.accountHint, '4521');
      expect(view.txn.status, TxnStatus.confirmed);
      expect(view.category?.name, 'Food & Dining');
    });

    test('receipt first, bank SMS later keeps the receipt merchant', () async {
      await svc.ingest([swiggyReceipt(t0)]);
      await svc.ingest([
        sms(
          'JD-ICICIT',
          'ICICI Bank Acct XX123 debited for Rs 475.00 on 12-Oct-26; BUNDL TECHNOLOGIES credited. UPI:528598765432.',
          t0.add(const Duration(minutes: 2)),
        ),
      ]);
      final txn = await db.select(db.transactions).getSingle();
      expect(txn.merchant, 'Swiggy');
      expect(txn.reference, '528598765432');
    });

    test('bank names the legal entity; receipt renames it', () async {
      await svc.ingest([
        sms(
          'JD-ICICIT',
          'ICICI Bank Acct XX123 debited for Rs 475.00 on 12-Oct-26; BUNDL TECHNOLOGIES credited. UPI:528598765432.',
          t0,
        ),
        swiggyReceipt(t0.add(const Duration(minutes: 25))),
      ]);
      final view = (await db.watchTxns().first).single;
      expect(view.txn.merchant, 'Swiggy');
      expect(view.category?.name, 'Food & Dining');
    });

    test('same amount, hours apart, different merchants → two transactions', () async {
      await svc.ingest([
        sms(
          'JD-ICICIT',
          'ICICI Bank Acct XX123 debited for Rs 475.00 on 12-Oct-26; ZOMATO LTD credited. UPI:528598765432.',
          t0,
        ),
        swiggyReceipt(t0.add(const Duration(hours: 5))),
      ]);
      final txns = await db.select(db.transactions).get();
      expect(txns, hasLength(2));
      expect(txns.map((t) => t.merchant).toSet(), {'Zomato', 'Swiggy'});
      expect(txns.every((t) => t.duplicateOfId == null), isTrue);
    });

    test('a different merchant close in time is flagged, not merged', () async {
      await svc.ingest([
        sms(
          'JD-ICICIT',
          'ICICI Bank Acct XX123 debited for Rs 475.00 on 12-Oct-26; ZOMATO LTD credited. UPI:528598765432.',
          t0,
        ),
        swiggyReceipt(t0.add(const Duration(minutes: 10))),
      ]);
      final txns = await db.select(db.transactions).get();
      expect(txns, hasLength(2));
    });

    test('ignored emails are logged with a reason', () async {
      final r = await svc.ingest([
        email('alerts@hdfcbank.net', 'OTP', '123456 is your OTP for txn of Rs 2,000 at AMAZON.', t0),
        email('noreply@flipkart.com', 'Shipped!', 'Your order has been shipped. Order total ₹999.', t0),
      ]);
      expect(r.ignored, 2);
      final rows = await db.watchRawMessages(SourceKind.email, {ParseStatus.ignored}).first;
      expect(rows.map((m) => m.ignoreReason).toSet(), {'OTP', 'Shipping update'});
    });
  });

  group('EmailSyncController', () {
    late ProviderContainer container;
    late _FakeMailbox mailbox;
    late _MemorySecrets secrets;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      mailbox = _FakeMailbox();
      secrets = _MemorySecrets();
      container = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(secrets),
          emailSourceFactoryProvider.overrideWithValue((account, password) {
            mailbox.lastPassword = password;
            return mailbox;
          }),
        ],
      );
    });
    tearDown(() => container.dispose());

    const account = EmailAccount(provider: EmailProvider.gmail, address: 'me@gmail.com');

    test('connect imports the window, then syncs incrementally with overlap', () async {
      final now = DateTime.now();
      mailbox.messages = [swiggyReceipt(now.subtract(const Duration(days: 2)))];
      final ctrl = container.read(emailSyncProvider.notifier);

      expect(await ctrl.connect(account, password: 'app-pass', months: 3), isTrue);
      final report = await ctrl.sync(); // joins the sync connect started
      expect(report?.added, 1);
      expect(mailbox.lastPassword, 'app-pass');
      expect(await secrets.read(emailPasswordSecret), 'app-pass');
      expect(mailbox.sinces.first.isBefore(now.subtract(const Duration(days: 80))), isTrue);

      final state = container.read(emailSyncProvider);
      expect(state.enabled, isTrue);
      expect(state.account?.address, 'me@gmail.com');
      expect(state.lastSync, isNotNull);

      await ctrl.sync();
      final second = mailbox.sinces.last;
      expect(state.lastSync!.difference(second).inMinutes, const Duration(days: 1).inMinutes);
      expect(await db.select(db.transactions).get(), hasLength(1)); // same Message-ID not re-imported
    });

    test('failed sign-in reports the error and saves nothing', () async {
      mailbox.failWith = const EmailConnectException('Sign-in failed. Gmail needs an App Password');
      final ctrl = container.read(emailSyncProvider.notifier);
      expect(await ctrl.connect(account, password: 'wrong'), isFalse);
      expect(container.read(emailSyncProvider).error, contains('App Password'));
      expect(container.read(emailSyncProvider).enabled, isFalse);
      expect(await secrets.read(emailPasswordSecret), isNull);
    });

    test('parser version bump re-parses email', () async {
      final ctrl = container.read(emailSyncProvider.notifier);
      mailbox.messages = [swiggyReceipt(DateTime.now().subtract(const Duration(days: 1)))];
      await ctrl.connect(account, password: 'p');
      await ctrl.sync();
      final prefs = container.read(prefsProvider);
      await prefs.setInt(EmailPrefKeys.parserVersion, emailParserVersion - 1);
      await ctrl.sync();
      expect(await db.select(db.transactions).get(), hasLength(1));
      expect(await db.knownExternalIds(SourceKind.email), hasLength(1));
      expect(prefs.getInt(EmailPrefKeys.parserVersion), emailParserVersion);
    });

    test('disconnect forgets the password', () async {
      final ctrl = container.read(emailSyncProvider.notifier);
      await ctrl.connect(account, password: 'p');
      await ctrl.sync();
      await ctrl.disconnect();
      expect(container.read(emailSyncProvider).enabled, isFalse);
      expect(await secrets.read(emailPasswordSecret), isNull);
      expect(await ctrl.sync(), isNull);
    });
  });
}

class _FakeMailbox implements EmailSource {
  List<RawInput> messages = [];
  final sinces = <DateTime>[];
  EmailConnectException? failWith;
  String? lastPassword;

  @override
  Future<void> test() async {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<List<RawInput>> fetchSince(DateTime since, {int limit = defaultEmailFetchLimit}) async {
    sinces.add(since);
    return messages.where((m) => !m.receivedAt.isBefore(since)).toList();
  }
}

class _MemorySecrets extends SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null || value.isEmpty ? _values.remove(key) : _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
