import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/ingestion/ingestion_service.dart';
import 'package:pckt/ingestion/parser/parsed_txn.dart';
import 'package:pckt/llm/agent/finance_agent.dart';
import 'package:pckt/llm/agent/finance_tools.dart';
import 'package:pckt/llm/ai_categorizer.dart';
import 'package:pckt/llm/fallback_parser.dart';
import 'package:pckt/llm/llm_client.dart';

/// Replays scripted responses and records every request.
class FakeLlm implements LlmClient {
  FakeLlm(this.script);
  final List<LlmResponse Function(List<LlmMessage> messages)> script;
  final calls = <({String? system, List<LlmMessage> messages, List<LlmTool> tools})>[];

  @override
  String get providerId => 'fake';

  @override
  Future<LlmResponse> chat({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
  }) async {
    calls.add((system: system, messages: List.of(messages), tools: tools));
    return script.removeAt(0)(messages);
  }

  @override
  Future<List<String>> listModels() async => const ['fake'];
}

LlmResponse text(String t) => LlmResponse(
  message: AssistantMessage(text: t),
  stop: LlmStop.endTurn,
);

LlmResponse toolCall(String name, Map<String, dynamic> args, {String id = 'c1'}) => LlmResponse(
  message: AssistantMessage(
    toolCalls: [ToolCall(id: id, name: name, arguments: args)],
  ),
  stop: LlmStop.toolUse,
);

void main() {
  late AppDatabase db;
  late IngestionService svc;
  var seq = 0;
  final t0 = DateTime(2026, 10, 12, 20, 0);

  RawInput sms(String sender, String body, DateTime at) =>
      RawInput(source: SourceKind.sms, externalId: 's${seq++}', sender: sender, body: body, receivedAt: at);

  Future<RawMessage> pendingRow(
    String body, {
    SourceKind source = SourceKind.email,
    String sender = 'alerts@bank.in',
  }) async {
    final id = await db
        .into(db.rawMessages)
        .insert(
          RawMessagesCompanion.insert(
            source: source,
            externalId: 'p${seq++}',
            sender: sender,
            body: body,
            receivedAt: t0.add(const Duration(minutes: 30)),
            parseStatus: ParseStatus.pendingLlm,
            ignoreReason: const Value('no amount pattern'),
          ),
        );
    return (db.select(db.rawMessages)..where((m) => m.id.equals(id))).getSingle();
  }

  Future<RawMessage> row(int id) => (db.select(db.rawMessages)..where((m) => m.id.equals(id))).getSingle();

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    svc = IngestionService(db);
  });
  tearDown(() => db.close());

  group('LLM fallback parsing', () {
    test('applies to the existing raw row and dedups against an SMS transaction', () async {
      await svc.ingest([
        sms('VM-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345678', t0),
      ]);
      final merged = await pendingRow(
        'Hello! Your payment of INR 250.00 to Swiggy was successful. UPI transaction ID: 528512345678.',
      );
      final fresh = await pendingRow('Your a/c 4521 was charged two hundred rupees ... Rs 1,999 for Myntra order.');
      final otp = await pendingRow('Use 123456 to log in. Rs 500 cashback offer inside!');
      final hallucinated = await pendingRow('Your statement for card ending 7788 is ready.');
      final rawsBefore = (await db.select(db.rawMessages).get()).length;

      final llm = FakeLlm([
        (msgs) {
          final input = jsonDecode((msgs.single as UserMessage).text) as List;
          expect(input.map((e) => e['id']), [merged.id, fresh.id, otp.id, hallucinated.id]);
          expect(input.first['text'], contains('Swiggy'));
          return text(
            jsonEncode({
              'results': [
                {
                  'id': merged.id,
                  'isTransaction': true,
                  'amount': 250,
                  'direction': 'debit',
                  'merchant': 'Swiggy',
                  'reference': '528512345678',
                  'mode': 'upi',
                  'reason': 'payment',
                },
                {
                  'id': fresh.id,
                  'isTransaction': true,
                  'amount': '1,999',
                  'direction': 'debit',
                  'merchant': 'Myntra',
                  'accountLast4': '4521',
                  'mode': 'card',
                  'reason': 'purchase',
                },
                {'id': otp.id, 'isTransaction': false, 'reason': 'OTP/promo'},
                {'id': hallucinated.id, 'isTransaction': true, 'amount': 4200, 'direction': 'debit'},
              ],
            }),
          );
        },
      ]);

      final report = await LlmFallbackParser(db: db, ingestion: svc, client: llm, pause: Duration.zero).run();

      expect(report.merged, 1);
      expect(report.added, 1);
      expect(report.ignored, 1);
      expect(report.failed, 1);

      // No new raw rows — existing ones were updated in place.
      expect((await db.select(db.rawMessages).get()).length, rawsBefore);

      final txns = await db.select(db.transactions).get();
      expect(txns, hasLength(2)); // the SMS one + Myntra
      final swiggy = txns.firstWhere((t) => t.reference == '528512345678');
      expect((await row(merged.id)).parseStatus, ParseStatus.merged);
      expect((await row(merged.id)).transactionId, swiggy.id);
      expect(await db.sourcesOf(swiggy.id), hasLength(2));

      final myntra = txns.firstWhere((t) => t.merchant == 'Myntra');
      expect(myntra.amountMinor, 199900);
      expect(myntra.status, TxnStatus.needsReview); // AI-read → user glances once
      expect(myntra.categoryId, isNotNull);
      expect((await row(fresh.id)).parseStatus, ParseStatus.parsed);
      expect((await row(fresh.id)).transactionId, myntra.id);

      expect((await row(otp.id)).parseStatus, ParseStatus.ignored);
      expect((await row(otp.id)).ignoreReason, 'AI: OTP/promo');
      expect((await row(hallucinated.id)).parseStatus, ParseStatus.failed);

      // Idempotent: nothing pending, so a second run makes no request.
      final again = await LlmFallbackParser(db: db, ingestion: svc, client: FakeLlm([])).run();
      expect(again.sent, 0);
    });

    test('provider errors leave rows pending', () async {
      final m = await pendingRow('Rs 99 debited');
      final failing = _ThrowingLlm(const LlmException(LlmErrorKind.rateLimit, 'slow'));
      final report = await LlmFallbackParser(db: db, ingestion: svc, client: failing).run();
      expect(report.error, isNotNull);
      expect((await row(m.id)).parseStatus, ParseStatus.pendingLlm);
    });
  });

  group('AI categorisation', () {
    test('applies valid names, rejects unknown ones, learns confident merchant rules', () async {
      await svc.ingest([
        sms('VM-HDFCBK', 'Sent Rs.640.00 From HDFC Bank A/C *4521 To ZORBLAXHUB On 12/10/26 Ref 528500000001', t0),
        sms('VM-HDFCBK', 'Sent Rs.300.00 From HDFC Bank A/C *4521 To QWIKFOO On 12/10/26 Ref 528500000002', t0),
        sms('VM-HDFCBK', 'Sent Rs.120.00 From HDFC Bank A/C *4521 To PLINKOXYZ On 12/10/26 Ref 528500000003', t0),
      ]);
      final txns = await db.select(db.transactions).get();
      final cats = {for (final c in await db.allCategories()) c.id: c.name};
      expect(txns.map((t) => cats[t.categoryId]).toSet(), {'Other'});
      int idOf(String m) => txns.firstWhere((t) => t.merchant!.toLowerCase().contains(m)).id;

      final llm = FakeLlm([
        (msgs) {
          final payload = jsonDecode((msgs.single as UserMessage).text) as List;
          expect(payload.first.keys, containsAll(['id', 'amount', 'direction', 'mode', 'date']));
          expect(payload.first.containsKey('body'), isFalse);
          return text(
            '```json\n${jsonEncode({
              'results': [
                {'id': idOf('zorblax'), 'category': 'Coffee & Snacks', 'confidence': 0.95, 'merchantLevel': true},
                {'id': idOf('qwikfoo'), 'category': 'Snacks & Stuff', 'confidence': 0.9, 'merchantLevel': true},
                {'id': idOf('plinko'), 'category': 'salary', 'confidence': 0.9, 'merchantLevel': true},
              ],
            })}\n```',
          );
        },
      ]);
      final report = await AiCategorizer(db: db, client: llm, pause: Duration.zero).run();
      expect(llm.calls.single.system, contains('Coffee & Snacks'));
      expect(report.updated, 1);
      expect(report.rejected, 2); // unknown name + income category on a debit
      expect(report.rulesLearned, 1);

      final after = {for (final t in await db.select(db.transactions).get()) t.id: t};
      expect(cats[after[idOf('zorblax')]!.categoryId], 'Coffee & Snacks');
      expect(after[idOf('zorblax')]!.categoryLocked, isFalse);
      expect(cats[after[idOf('qwikfoo')]!.categoryId], 'Other');
      expect(cats[after[idOf('plinko')]!.categoryId], 'Other');
      final rules = await db.allMerchantRules();
      expect(rules.single.pattern, 'zorblaxhub');

      // Future rule-based ingestion learns from it.
      await svc.ingest([
        sms('VM-HDFCBK', 'Sent Rs.90.00 From HDFC Bank A/C *4521 To ZORBLAXHUB On 13/10/26 Ref 528500000009', t0),
      ]);
      final newest = (await db.watchTxns().first).first;
      expect(newest.category?.name, 'Coffee & Snacks');
    });
  });

  group('Agent', () {
    test('tool call → result → final answer', () async {
      await svc.ingest([
        sms('VM-HDFCBK', 'Sent Rs.250.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345678', t0),
        sms('VM-HDFCBK', 'Sent Rs.100.00 From HDFC Bank A/C *4521 To SWIGGY On 12/10/26 Ref 528512345679', t0),
      ]);
      final llm = FakeLlm([
        (_) => toolCall('spending_summary', {'group_by': 'category', 'from': '2026-10-01', 'to': '2026-10-19'}),
        (msgs) {
          final results = (msgs.last as ToolResultsMessage).results.single;
          final json = jsonDecode(results.content) as Map<String, dynamic>;
          expect(json['total'], 350.0);
          expect(json['groups'][0]['key'], 'Food & Dining');
          return text('You spent **${json['total_formatted']}**, all on food.');
        },
      ]);
      final activity = <String>[];
      final agent = FinanceAgent(
        client: llm,
        tools: FinanceTools(db, now: () => DateTime(2026, 10, 19)),
        now: () => DateTime(2026, 10, 19),
      );
      final res = await agent.run(const [], 'Where did my money go?', onActivity: (a) => activity.add(a.summary));

      expect(res.text, 'You spent **₹350**, all on food.');
      expect(activity, ['Summarised 2 transactions by category']);
      expect(res.newMessages.first, isA<UserMessage>());
      expect(res.newMessages, hasLength(4)); // user, tool call, tool results, answer
      expect(llm.calls.first.system, contains('2026-10-19'));
      expect(llm.calls.first.tools.map((t) => t.name), contains('find_recurring'));
    });

    test('recategorize waits for user confirmation', () async {
      await svc.ingest([
        sms('VM-HDFCBK', 'Sent Rs.199.00 From HDFC Bank A/C *4521 To BLORPTV On 12/10/26 Ref 528500000011', t0),
      ]);
      final tools = FinanceTools(db, now: () => DateTime(2026, 10, 19));
      RecategorizeProposal? asked;

      final declined = await tools.execute(
        const ToolCall(id: 'a', name: 'recategorize', arguments: {'merchant': 'blorp', 'category': 'Subscriptions'}),
        confirm: (p) async {
          asked = p;
          return false;
        },
      );
      expect(asked!.txns, hasLength(1));
      expect(jsonDecode(declined.content)['applied'], isFalse);
      expect((await db.watchTxns().first).single.category?.name, 'Other');

      final ok = await tools.execute(
        const ToolCall(id: 'b', name: 'recategorize', arguments: {'merchant': 'blorp', 'category': 'Subscriptions'}),
        confirm: (_) async => true,
      );
      expect(jsonDecode(ok.content)['applied'], isTrue);
      expect((await db.watchTxns().first).single.category?.name, 'Subscriptions');
      expect((await db.allMerchantRules()).single.pattern, 'blorptv');

      final bad = await tools.execute(
        const ToolCall(id: 'c', name: 'recategorize', arguments: {'merchant': 'blorp', 'category': 'Nope'}),
        confirm: (_) async => true,
      );
      expect(bad.isError, isTrue);
    });

    test('find_recurring spots a monthly subscription', () async {
      final views = <TxnView>[
        for (var i = 0; i < 4; i++)
          TxnView(
            Transaction(
              id: i,
              amountMinor: 64900,
              direction: TxnDirection.debit,
              occurredAt: DateTime(2026, 6 + i, 5),
              merchant: 'Netflix',
              mode: PaymentMode.card,
              status: TxnStatus.confirmed,
              isTransfer: false,
              categoryLocked: false,
              createdAt: DateTime(2026),
            ),
            null,
            null,
          ),
        for (var i = 0; i < 5; i++)
          TxnView(
            Transaction(
              id: 10 + i,
              amountMinor: 20000 + i * 15000,
              direction: TxnDirection.debit,
              occurredAt: DateTime(2026, 9, 1 + i * 3),
              merchant: 'Swiggy',
              mode: PaymentMode.upi,
              status: TxnStatus.confirmed,
              isTransfer: false,
              categoryLocked: false,
              createdAt: DateTime(2026),
            ),
            null,
            null,
          ),
      ];
      final found = detectRecurring(views, today: DateTime(2026, 10, 19));
      expect(found.map((r) => r.name), ['Netflix']);
      expect(found.single.cadence, 'monthly');
      expect(found.single.next, DateTime(2026, 10, 5));
    });
  });
}

class _ThrowingLlm implements LlmClient {
  _ThrowingLlm(this.error);
  final LlmException error;

  @override
  String get providerId => 'x';

  @override
  Future<LlmResponse> chat({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
  }) => throw error;

  @override
  Future<List<String>> listModels() async => const [];
}
