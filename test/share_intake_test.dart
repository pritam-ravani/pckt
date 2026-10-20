import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/ingestion/ingestion_service.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';
import 'package:pckt/ingestion/share/share_intake.dart';

const hdfc = 'Sent Rs.250.00\nFrom HDFC Bank A/C *4521\nTo SWIGGY\nOn 12/10/26\nRef 528512345678\nNot You?';

void main() {
  group('pckt://ingest links', () {
    test('parses text and sender (percent-encoded)', () {
      final uri = Uri.parse(
        'pckt://ingest?text=${Uri.encodeQueryComponent(hdfc)}&sender=${Uri.encodeQueryComponent('JD-HDFCBK-S')}',
      );
      final s = SharedText.fromUri(uri)!;
      expect(s.text, hdfc.trim());
      expect(s.sender, 'JD-HDFCBK-S');
      expect(s.via, 'link');
    });

    test('rejects other schemes, hosts and empty text', () {
      expect(SharedText.fromUri(Uri.parse('https://ingest?text=hi')), isNull);
      expect(SharedText.fromUri(Uri.parse('pckt://other?text=hi')), isNull);
      expect(SharedText.fromUri(Uri.parse('pckt://ingest?text=')), isNull);
      expect(SharedText.fromUri(Uri.parse('pckt://ingest')), isNull);
    });

    test('IncomingShares claims pckt links ahead of the router', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final shares = IncomingShares.instance;
      shares.drain();
      final claimed = await shares.didPushRouteInformation(
        RouteInformation(uri: Uri.parse('pckt://ingest?text=Rs%20100%20debited')),
      );
      expect(claimed, isTrue);
      expect(await shares.didPushRouteInformation(RouteInformation(uri: Uri.parse('/activity'))), isFalse);
      expect(shares.drain().single.text, 'Rs 100 debited');
    });
  });

  group('raw input', () {
    final now = DateTime(2026, 10, 12, 20);

    test('uses the shortcut source and a stable content id', () {
      final a = const SharedText(text: hdfc).toRawInput(now);
      final b = const SharedText(text: '  $hdfc  ').toRawInput(now.add(const Duration(hours: 1)));
      expect(a.source, SourceKind.shortcut);
      expect(a.externalId, b.externalId);
      expect(a.externalId, isNot(const SharedText(text: '$hdfc!').toRawInput(now).externalId));
    });

    test('guesses the bank from the text when no sender is given', () {
      expect(const SharedText(text: hdfc).toRawInput(now).sender, 'SHARED-HDFC');
      expect(
        const SharedText(text: 'Rs 10 spent on your SBI Card XX1234 at AMAZON').toRawInput(now).sender,
        'SHARED-SBICRD',
      );
      expect(const SharedText(text: 'hello').toRawInput(now).sender, 'Shared');
      expect(const SharedText(text: hdfc, sender: 'AX-HDFCBK').toRawInput(now).sender, 'AX-HDFCBK');
    });
  });

  group('pipeline', () {
    late AppDatabase db;
    late IngestionService svc;
    final t0 = DateTime(2026, 10, 12, 20);

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      svc = IngestionService(db);
    });
    tearDown(() => db.close());

    test('adds a shared bank SMS as a transaction', () async {
      final o = await ingestShared(svc, const SharedText(text: hdfc), now: t0);
      expect(o.kind, ShareOutcomeKind.added);
      expect(o.txn!.amountMinor, 25000);
      expect(o.txn!.merchant, 'Swiggy');
      final raw = await db.select(db.rawMessages).getSingle();
      expect(raw.source, SourceKind.shortcut);
    });

    test('the same text twice is reported as a duplicate', () async {
      await ingestShared(svc, const SharedText(text: hdfc), now: t0);
      final o = await ingestShared(svc, const SharedText(text: hdfc), now: t0);
      expect(o.kind, ShareOutcomeKind.duplicate);
      expect(o.txn, isNotNull);
      expect(await db.select(db.transactions).get(), hasLength(1));
    });

    test('merges with the same payment already read from SMS', () async {
      await svc.ingest([
        RawInput(source: SourceKind.sms, externalId: '1', sender: 'VM-HDFCBK', body: hdfc, receivedAt: t0),
      ]);
      final o = await ingestShared(
        svc,
        const SharedText(text: hdfc, sender: 'VM-HDFCBK'),
        now: t0.add(const Duration(minutes: 5)),
      );
      expect(o.kind, ShareOutcomeKind.merged);
      expect(await db.select(db.transactions).get(), hasLength(1));
    });

    test('non-transactions are ignored with a reason', () async {
      final o = await ingestShared(svc, const SharedText(text: '123456 is your OTP for login'), now: t0);
      expect(o.kind, ShareOutcomeKind.ignored);
      expect(o.reason, 'OTP');
      expect(await db.select(db.transactions).get(), isEmpty);
    });
  });
}
