import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/llm/agent/finance_agent.dart';
import 'package:pckt/llm/agent/finance_tools.dart';
import 'package:pckt/llm/agent/tool_result_budget.dart';
import 'package:pckt/llm/ai_categorizer.dart';
import 'package:pckt/llm/llm_client.dart';
import 'package:pckt/llm/llm_config.dart';
import 'package:pckt/llm/llm_providers.dart';
import 'package:pckt/llm/on_device/model_catalog.dart';
import 'package:pckt/llm/on_device/on_device_client.dart';
import 'package:pckt/llm/on_device/on_device_models.dart';
import 'package:pckt/llm/on_device/on_device_scheduler.dart';
import 'package:pckt/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db_encryption_test.dart' show MemorySecretStore;

/// A small-context client like the on-device one: records requests.
class FakeSmallLlm implements LlmClient, LlmBudget, LlmStreamingClient {
  FakeSmallLlm(this.script, {this.contextTokens = 4096});
  final List<LlmResponse Function(List<LlmMessage>)> script;
  final requests = <({List<LlmMessage> messages, int maxTokens})>[];

  @override
  final int contextTokens;

  @override
  bool get supportsTools => true;

  @override
  String get providerId => 'fake-small';

  @override
  Future<LlmResponse> chat({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
  }) async {
    requests.add((messages: List.of(messages), maxTokens: maxTokens));
    return script.isEmpty ? const LlmResponse(message: AssistantMessage(text: '{}'), stop: LlmStop.endTurn) : script.removeAt(0)(messages);
  }

  @override
  Future<LlmResponse> chatStreaming({
    String? system,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
    int maxTokens = 4096,
    required void Function(String textSoFar) onText,
  }) async {
    final r = await chat(system: system, messages: messages, tools: tools, maxTokens: maxTokens);
    if (r.toolCalls.isEmpty) {
      for (var i = 1; i <= r.text.length; i += 4) {
        onText(r.text.substring(0, i));
      }
      onText(r.text);
    }
    return r;
  }

  @override
  Future<List<String>> listModels() async => const [];
}

LlmResponse _text(String t) => LlmResponse(message: AssistantMessage(text: t), stop: LlmStop.endTurn);
LlmResponse _call(String name, Map<String, dynamic> args) => LlmResponse(
  message: AssistantMessage(toolCalls: [ToolCall(id: 'c', name: name, arguments: args)]),
  stop: LlmStop.toolUse,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('scheduler', () {
    test('interactive requests jump ahead of queued background work', () async {
      final s = OnDeviceScheduler(idleAfter: const Duration(hours: 1));
      final order = <String>[];
      final gate = Completer<void>();
      final first = s.run(OnDevicePriority.background, (_) async {
        await gate.future;
        order.add('bg1');
      });
      await Future<void>.delayed(Duration.zero); // bg1 is now running
      final bg2 = s.run(OnDevicePriority.background, (_) async => order.add('bg2'));
      final ask = s.run(OnDevicePriority.interactive, (_) async => order.add('ask'));
      expect(s.interactivePending, isTrue);
      gate.complete();
      // bg1 was running and had no stop hook, so it was flagged and finishes.
      await first;
      await ask;
      await expectLater(bg2, completes);
      expect(order, ['bg1', 'ask', 'bg2']);
      expect(s.interactivePending, isFalse);
    });

    test('an Ask request stops the running background generation', () async {
      final s = OnDeviceScheduler(idleAfter: const Duration(hours: 1));
      final stopped = Completer<void>();
      final bg = s.run(OnDevicePriority.background, (run) async {
        final generation = Completer<String>();
        run.onPreempt(() {
          stopped.complete();
          generation.complete('stopped');
        });
        final r = await generation.future;
        if (run.preempted) throw const OnDevicePreempted();
        return r;
      });
      await Future<void>.delayed(Duration.zero);
      final ask = s.run(OnDevicePriority.interactive, (_) async => 'answer');
      await stopped.future;
      await expectLater(bg, throwsA(isA<OnDevicePreempted>()));
      expect(await ask, 'answer');
    });

    test('background never preempts interactive', () async {
      final s = OnDeviceScheduler(idleAfter: const Duration(hours: 1));
      var stopCalled = false;
      final gate = Completer<void>();
      final ask = s.run(OnDevicePriority.interactive, (run) async {
        run.onPreempt(() => stopCalled = true);
        await gate.future;
        return 'ok';
      });
      final bg = s.run(OnDevicePriority.background, (_) async => 'bg');
      gate.complete();
      expect(await ask, 'ok');
      expect(await bg, 'bg');
      expect(stopCalled, isFalse);
    });

    test('fires onIdle after the idle period and whenQuiet waits for it', () async {
      var idle = 0;
      final s = OnDeviceScheduler(idleAfter: const Duration(milliseconds: 50), onIdle: () => idle++);
      await s.run(OnDevicePriority.interactive, (_) async {});
      final sw = Stopwatch()..start();
      await s.whenQuiet(const Duration(milliseconds: 30));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(20));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(idle, 1);
    });

    test('turn timeouts scale with model size and job kind', () {
      final e2b = onDeviceTurnTimeout(modelBytes: ModelCatalog.gemma4E2b.sizeBytes, priority: OnDevicePriority.interactive);
      final e4b = onDeviceTurnTimeout(modelBytes: ModelCatalog.gemma4E4b.sizeBytes, priority: OnDevicePriority.interactive);
      final e2bBatch = onDeviceTurnTimeout(modelBytes: ModelCatalog.gemma4E2b.sizeBytes, priority: OnDevicePriority.background);
      expect(e2b.inSeconds, inInclusiveRange(150, 240));
      expect(e4b > e2b, isTrue);
      expect(e2bBatch, e2b * 2);
    });
  });

  group('conversation reuse', () {
    const q1 = UserMessage('How much on food?');
    final call = _call('spending_summary', {'group_by': 'category'}).message;
    const results = ToolResultsMessage([ToolResult(callId: 'c', name: 'spending_summary', content: '{}')]);

    test('a transcript that extends the live one only sends the new messages', () {
      expect(continuationOf([q1, call], [q1, call, results], sameSignature: true), [results]);
    });

    test('anything else starts over', () {
      expect(continuationOf([q1, call], [q1, call, results], sameSignature: false), isNull);
      expect(continuationOf([q1, call], [UserMessage(q1.text), call, results], sameSignature: true), isNull);
      expect(continuationOf([q1, call], [q1, call], sameSignature: true), isNull);
      expect(continuationOf([q1], [q1, const AssistantMessage(text: 'x')], sameSignature: true), isNull);
    });

    test('replaying an old chat keeps earlier questions and answers only', () {
      const a1 = AssistantMessage(text: 'You spent ₹4,200.');
      const q2 = UserMessage('And travel?');
      final compact = compactForReplay([q1, call, results, a1, q2, call, results]);
      expect(compact, [q1, a1, q2, call, results]);
    });

    test('signature changes with the system prompt, tools and output cap', () {
      const tool = LlmTool(name: 'a', description: 'd', parameters: {});
      final base = conversationSignature('m', 'sys', [tool], 1024);
      expect(conversationSignature('m', 'sys', [tool], 1024), base);
      expect(conversationSignature('m', 'sys2', [tool], 1024), isNot(base));
      expect(conversationSignature('m', 'sys', const [], 1024), isNot(base));
      expect(conversationSignature('m', 'sys', [tool], 512), isNot(base));
    });
  });

  group('tool result trimming', () {
    Map<String, dynamic> bigResult(int n) => {
      'from': '2026-09-01',
      'matched': n,
      'total_debit': 123456.0,
      'total_debit_formatted': '₹1,23,456',
      'returned': n,
      'transactions': [
        for (var i = 0; i < n; i++)
          {'id': i, 'date': '2026-09-${(i % 28 + 1).toString().padLeft(2, '0')}', 'amount': 250.0, 'merchant': 'Swiggy $i', 'note': null},
      ],
    };

    test('caps rows, keeps totals, drops raw twins of formatted numbers', () {
      final full = jsonEncode(bigResult(25));
      final out = compactToolJson(bigResult(25), ToolResultBudget.forContext(4096));
      final j = jsonDecode(out) as Map<String, dynamic>;
      expect((j['transactions'] as List).length, 10);
      expect(j['transactions_omitted'], 15);
      expect(j['returned'], 10);
      expect(j['matched'], 25);
      expect(j['total_debit_formatted'], '₹1,23,456');
      expect(j.containsKey('total_debit'), isFalse);
      expect((j['transactions'] as List).first['amount'], 250);
      expect((j['transactions'] as List).first.containsKey('note'), isFalse);
      expect(out.length, lessThan(full.length ~/ 2));
      // ignore: avoid_print
      print('tool result: ${full.length} → ${out.length} chars');
    });

    test('shrinks further to fit the character budget', () {
      final out = compactToolJson(bigResult(25), const ToolResultBudget(maxRows: 25, maxChars: 600));
      expect(out.length, lessThanOrEqualTo(600));
      expect(jsonDecode(out)['total_debit_formatted'], '₹1,23,456');
    });

    test('small results are unchanged apart from compaction', () {
      final j = jsonDecode(compactToolJson({'categories': [{'name': 'Food'}]}, ToolResultBudget.forContext(2048)));
      expect(j, {'categories': [{'name': 'Food'}]});
    });
  });

  group('agent on a small model', () {
    late AppDatabase db;
    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      for (var i = 0; i < 30; i++) {
        await db.addManual(amountMinor: 10000 + i, direction: TxnDirection.debit, at: DateTime(2026, 10, 1 + i % 18), merchant: 'Shop $i');
      }
    });
    tearDown(() => db.close());

    test('compacts tool results, caps output tokens and streams the answer', () async {
      final llm = FakeSmallLlm([
        (_) => _call('query_transactions', {'from': '2026-10-01', 'to': '2026-10-20', 'limit': 50}),
        (msgs) {
          final r = (msgs.last as ToolResultsMessage).results.single;
          final j = jsonDecode(r.content) as Map<String, dynamic>;
          expect((j['transactions'] as List).length, 10);
          expect(j['transactions_omitted'], 20);
          return _text('You spent **₹3,004** at 30 shops.');
        },
      ]);
      final drafts = <String>[];
      final agent = FinanceAgent(client: llm, tools: FinanceTools(db, now: () => DateTime(2026, 10, 20)));
      final res = await agent.run(const [], 'What did I spend?', onText: drafts.add);
      expect(res.text, 'You spent **₹3,004** at 30 shops.');
      expect(llm.requests.map((r) => r.maxTokens), everyElement(1024));
      expect(drafts, contains(''));
      expect(drafts.last, res.text);
    });

    test('stops after four steps on a small model', () async {
      final llm = FakeSmallLlm([
        for (var i = 0; i < 4; i++) (_) => _call('list_categories', const {}),
        (_) => _text('Best effort.'),
      ]);
      final res = await FinanceAgent(client: llm, tools: FinanceTools(db)).run(const [], 'loop');
      expect(res.hitStepLimit, isTrue);
      expect(llm.requests, hasLength(5));
    });
  });

  group('background jobs', () {
    late AppDatabase db;
    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      final other = (await db.allCategories()).firstWhere((c) => c.name == 'Other');
      for (var i = 0; i < 40; i++) {
        await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            amountMinor: 1000 + i,
            direction: TxnDirection.debit,
            occurredAt: DateTime(2026, 10, 1).add(Duration(hours: i)),
            mode: PaymentMode.upi,
            status: TxnStatus.confirmed,
            merchant: Value('m$i'),
            categoryId: Value(other.id),
          ),
        );
      }
    });
    tearDown(() => db.close());

    test('categoriser honours the batch cap and resumes from the cursor in id order', () async {
      final llm = FakeSmallLlm([]);
      final job = AiCategorizer(db: db, client: llm, batchSize: 8, maxBatches: 3, pause: Duration.zero);
      final r = await job.run();
      expect(llm.requests, hasLength(3));
      expect(r.stoppedEarly, isTrue);
      final ids = [for (final m in (await job.candidates())) m.id];
      expect(r.maxId, ids[23]);
      final next = await job.candidates(afterId: r.maxId!);
      expect(next.first.id, ids[24]);
    });

    test('categoriser yields to the user between batches', () async {
      var calls = 0;
      final llm = FakeSmallLlm([]);
      final job = AiCategorizer(db: db, client: llm, batchSize: 8, pause: Duration.zero, shouldStop: () => ++calls > 2);
      final r = await job.run();
      expect(llm.requests, hasLength(2));
      expect(r.stoppedEarly, isTrue);
      expect(r.error, isNull);
    });

    test('policy: every 6 h, every 30 min while charging', () {
      const p = OnDeviceJobPolicy();
      final now = DateTime(2026, 10, 20, 12);
      expect(p.shouldAutoRun(lastRun: null, now: now, charging: false), isTrue);
      expect(p.shouldAutoRun(lastRun: now.subtract(const Duration(hours: 1)), now: now, charging: false), isFalse);
      expect(p.shouldAutoRun(lastRun: now.subtract(const Duration(hours: 1)), now: now, charging: true), isTrue);
      expect(p.shouldAutoRun(lastRun: now.subtract(const Duration(hours: 7)), now: now, charging: false), isTrue);
    });

    Future<(ProviderContainer, FakeSmallLlm)> container({int? lastRunAgoMinutes, bool interactive = false}) async {
      SharedPreferences.setMockInitialValues({
        if (lastRunAgoMinutes != null)
          AiJobsController.lastAutoRunKey:
              DateTime.now().subtract(Duration(minutes: lastRunAgoMinutes)).millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      await const LlmConfig(presetId: 'ondevice', model: 'gemma-4-e2b', aiCategorise: true).save(prefs);
      final llm = FakeSmallLlm([]);
      final runtime = OnDeviceRuntime();
      final c = ProviderContainer(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          llmClientProvider.overrideWith((ref) async => llm),
          aiJobsProvider.overrideWith(
            () => AiJobsController(
              policy: const OnDeviceJobPolicy(startDelay: Duration.zero, quietBeforeStart: Duration.zero),
              isCharging: () async => false,
              isForeground: () => !interactive,
              runtime: runtime,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return (c, llm);
    }

    test('on-device auto-run is capped and records its time', () async {
      final (c, llm) = await container();
      await c.read(aiJobsProvider.notifier).runAfterSync();
      expect(llm.requests, hasLength(3));
      expect(c.read(prefsProvider).getInt(AiJobsController.lastAutoRunKey), isNotNull);
    });

    test('on-device auto-run waits for the interval', () async {
      final (c, llm) = await container(lastRunAgoMinutes: 60);
      await c.read(aiJobsProvider.notifier).runAfterSync();
      expect(llm.requests, isEmpty);
    });

    test('on-device auto-run does not start while the user needs the phone', () async {
      final (c, llm) = await container(interactive: true);
      await c.read(aiJobsProvider.notifier).runAfterSync();
      expect(llm.requests, isEmpty);
      expect(c.read(prefsProvider).getInt(AiJobsController.lastAutoRunKey), isNull);
    });
  });

  test('picking the on-device provider leaves background AI off', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await const LlmConfig(presetId: 'openai', model: 'gpt-5-mini', aiCategorise: true, aiReadUnparsed: true).save(prefs);
    final c = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs), secretStoreProvider.overrideWithValue(MemorySecretStore())],
    );
    addTearDown(c.dispose);
    await c.read(onDeviceModelsProvider.notifier).use(ModelCatalog.gemma4E2b);
    final cfg = c.read(llmConfigProvider);
    expect(cfg.presetId, 'ondevice');
    expect(cfg.aiCategorise, isFalse);
    expect(cfg.aiReadUnparsed, isFalse);
    expect(cfg.assistant, isTrue);

    // Choices made while on-device are kept when re-picking a model.
    await c.read(llmConfigProvider.notifier).change((x) => x.copyWith(aiCategorise: true));
    await c.read(onDeviceModelsProvider.notifier).use(ModelCatalog.gemma4E4b);
    expect(c.read(llmConfigProvider).aiCategorise, isTrue);
  });
}
