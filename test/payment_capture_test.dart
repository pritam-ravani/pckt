import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/features/capture/payment_capture.dart';
import 'package:pckt/ingestion/ingestion_service.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';

class _FakeChannel extends PaymentCaptureChannel {
  final queue = <CapturedPayment>[];

  @override
  bool get isSupported => true;

  @override
  Future<List<CapturedPayment>> pending() async => List.of(queue);

  @override
  Future<void> remove(List<String> ids) async => queue.removeWhere((p) => ids.contains(p.id));
}

void main() {
  late AppDatabase db;
  late _FakeChannel channel;
  late PaymentCaptureService service;
  String? hints;
  final at = DateTime(2026, 11, 10, 13);

  CapturedPayment payment(String id, {int minor = 25000, String? merchant = 'Swiggy', String? category, bool credit = false}) =>
      CapturedPayment(id: id, app: 'Paytm', title: 'Paid', text: 'You paid', postedAt: at, amountMinor: minor, merchant: merchant, category: category, credit: credit);

  setUp(() {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    channel = _FakeChannel();
    hints = null;
    service = PaymentCaptureService(db, IngestionService(db), channel, (json) async => hints = json);
  });
  tearDown(() => db.close());

  Future<Transaction> only() => db.select(db.transactions).getSingle();
  Future<int> categoryId(String name) async => (await db.allCategories()).firstWhere((c) => c.name == name).id;

  test('a payment with no pick is saved for review and leaves the queue', () async {
    channel.queue.add(payment('a'));
    final report = await service.drain();
    expect(report?.added, 1);
    final t = await only();
    expect(t.amountMinor, 25000);
    expect(t.status, TxnStatus.needsReview);
    expect(t.mode, PaymentMode.upi);
    expect(t.merchant, 'Swiggy');
    expect(channel.queue, isEmpty);
  });

  test('a category pick confirms it and teaches the merchant', () async {
    channel.queue.add(payment('a', category: 'Groceries'));
    await service.drain();
    final t = await only();
    expect(t.categoryId, await categoryId('Groceries'));
    expect(t.status, TxnStatus.confirmed);
    expect(t.categoryLocked, isTrue);
    expect((await db.allMerchantRules()).single.pattern, 'swiggy');
  });

  test('a pick made after the app took the payment is still applied', () async {
    channel.queue.add(payment('a'));
    await service.drain();
    channel.queue.add(const CapturedPayment(id: 'a', category: 'Shopping', choiceOnly: true));
    await service.drain();
    final t = await only();
    expect(t.categoryId, await categoryId('Shopping'));
    expect(t.status, TxnStatus.confirmed);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('money received is saved as a credit', () async {
    channel.queue.add(payment('a', credit: true, merchant: 'Neha'));
    await service.drain();
    expect((await only()).direction, TxnDirection.credit);
  });

  test('draining the same payment twice adds it once', () async {
    channel.queue.add(payment('a'));
    await service.drain();
    channel.queue.add(payment('a'));
    final report = await service.drain();
    expect(report?.added, 0);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('an unknown category name leaves it for review', () async {
    channel.queue.add(payment('a', category: 'Deleted category'));
    await service.drain();
    expect((await only()).status, TxnStatus.needsReview);
  });

  test('an SMS for the same payment merges instead of counting twice', () async {
    await IngestionService(db).ingestParsed([
      (
        RawInput(source: SourceKind.sms, externalId: 's1', sender: 'VM-AXISBK', body: 'debited', receivedAt: at),
        ParsedTxn(amountMinor: 25000, direction: TxnDirection.debit, occurredAt: at.add(const Duration(minutes: 1)), mode: PaymentMode.upi, confidence: 1, currency: 'INR', reference: '123456789012'),
      ),
    ]);
    channel.queue.add(payment('a'));
    final report = await service.drain();
    expect(report?.merged, 1);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('two separate payments of the same amount from one app stay separate', () async {
    channel.queue.add(payment('a'));
    await service.drain();
    channel.queue.add(payment('b'));
    await service.drain();
    expect(await db.select(db.transactions).get(), hasLength(2));
  });

  test('hints name each merchant\'s category and the most used ones', () async {
    final food = await categoryId('Food & Dining');
    await db.addManual(amountMinor: 100, currency: 'INR', direction: TxnDirection.debit, at: at, merchant: 'Cafe', categoryId: food);
    await service.refreshHints();
    final json = jsonDecode(hints!) as Map<String, dynamic>;
    expect(json['m'], {'cafe': 'Food & Dining'});
    expect(json['top'], ['Food & Dining']);
  });

  test('hints have sensible defaults on a new install', () async {
    await service.refreshHints();
    expect((jsonDecode(hints!) as Map)['top'], ['Food & Dining', 'Groceries', 'Shopping']);
  });
}
