import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/db/database.dart';
import '../ingestion/email/email_sync.dart';
import '../providers.dart';
import 'ai_categorizer.dart';
import 'fallback_parser.dart';
import 'llm_client.dart';
import 'llm_config.dart';
import 'on_device/device_profile.dart';
import 'on_device/on_device_client.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

// ---------------------------------------------------------------- config

class LlmConfigNotifier extends Notifier<LlmConfig> {
  @override
  LlmConfig build() => LlmConfig.load(ref.read(prefsProvider));

  Future<String?> readKey(String presetId) => ref.read(secretStoreProvider).read(LlmConfig.keyName(presetId));

  /// Persists the connection. [apiKey] goes to the secure store only.
  Future<void> save(LlmConfig config, {String? apiKey}) async {
    if (config.presetId != null && apiKey != null) {
      await ref.read(secretStoreProvider).write(LlmConfig.keyName(config.presetId!), apiKey);
    }
    await config.save(ref.read(prefsProvider));
    state = config;
  }

  Future<void> change(LlmConfig Function(LlmConfig c) edit) => save(edit(state));

  /// Forgets the provider and its key; nothing is sent anywhere afterwards.
  Future<void> disconnect() async {
    final id = state.presetId;
    if (id != null) await ref.read(secretStoreProvider).delete(LlmConfig.keyName(id));
    await save(state.copyWith(clearPreset: true, model: ''));
  }
}

final llmConfigProvider = NotifierProvider<LlmConfigNotifier, LlmConfig>(LlmConfigNotifier.new);

/// The configured client, or null when no LLM is connected.
final llmClientProvider = FutureProvider<LlmClient?>((ref) async {
  final c = ref.watch(llmConfigProvider);
  if (!c.isConfigured) return null;
  final key = await ref.read(secretStoreProvider).read(LlmConfig.keyName(c.presetId!));
  try {
    return buildLlmClient(
      preset: c.preset,
      baseUrl: c.baseUrl,
      model: c.model,
      apiKey: key,
      httpClient: ref.watch(httpClientProvider),
    );
  } on LlmException {
    return null;
  }
});

/// Messages (any source) waiting for the AI reader.
final pendingLlmCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  final c = db.rawMessages.id.count();
  final q = db.selectOnly(db.rawMessages)
    ..addColumns([c])
    ..where(db.rawMessages.parseStatus.equalsValue(ParseStatus.pendingLlm));
  return q.watchSingle().map((r) => r.read(c) ?? 0);
});

// ---------------------------------------------------------------- jobs

class AiJobsState {
  const AiJobsState({this.running, this.progress, this.lastResult, this.error});

  /// Label of the job in progress, null when idle.
  final String? running;
  final (int, int)? progress;
  final String? lastResult;
  final String? error;
}

/// When background AI may run by itself with an on-device model. On a phone
/// a batch takes a minute or more and heats the device, so it runs rarely,
/// a few batches at a time, and more often while charging. Cloud providers
/// keep running after every sync.
class OnDeviceJobPolicy {
  const OnDeviceJobPolicy({
    this.interval = const Duration(hours: 6),
    this.chargingInterval = const Duration(minutes: 30),
    this.maxBatchesPerRun = 3,
    this.startDelay = const Duration(seconds: 20),
    this.quietBeforeStart = const Duration(seconds: 45),
    this.maxResumesPerSession = 3,
  });

  final Duration interval;
  final Duration chargingInterval;
  final int maxBatchesPerRun;

  /// Wait after a sync before starting, so the app settles first.
  final Duration startDelay;

  /// Don't start until the model has been unused (no Ask) for this long.
  final Duration quietBeforeStart;
  final int maxResumesPerSession;

  bool shouldAutoRun({required DateTime? lastRun, required DateTime now, required bool charging}) =>
      lastRun == null || now.difference(lastRun) >= (charging ? chargingInterval : interval);
}

/// Background AI work: reading unreadable messages and categorising.
/// Cloud: runs after each sync when the matching privacy toggle is on.
/// On-device: see [OnDeviceJobPolicy]; it always yields to Ask requests and
/// pauses while the app is in the background, resuming later.
class AiJobsController extends Notifier<AiJobsState> {
  AiJobsController({
    this.policy = const OnDeviceJobPolicy(),
    Future<bool> Function()? isCharging,
    bool Function()? isForeground,
    OnDeviceRuntime? runtime,
  }) : _isCharging = isCharging ?? DeviceProfile.isCharging,
       _isForeground = isForeground ?? _appInForeground,
       _runtime = runtime ?? OnDeviceClient.runtime;

  final OnDeviceJobPolicy policy;
  final Future<bool> Function() _isCharging;
  final bool Function() _isForeground;
  final OnDeviceRuntime _runtime;

  static const _cursorKey = 'llm.categoriseCursor';
  static const lastAutoRunKey = 'llm.onDevice.lastAutoRun';
  DateTime? _backoffUntil;
  var _autoRunPending = false;
  var _resumes = 0;

  /// Set when a run stopped because the user needed the model.
  var _yielded = false;

  static bool _appInForeground() {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  @override
  AiJobsState build() {
    ref.listen(smsSyncProvider, (prev, next) {
      if (prev?.running == true && !next.running) runAfterSync();
    });
    ref.listen(emailSyncProvider, (prev, next) {
      if (prev?.running == true && !next.running) runAfterSync();
    });
    return const AiJobsState();
  }

  bool get _busy => state.running != null;

  Future<LlmClient?> _client() async {
    try {
      final c = await ref.read(llmClientProvider.future);
      // Batch work on the phone queues behind, and is stopped for, Ask.
      return c is OnDeviceClient ? c.background() : c;
    } catch (_) {
      return null;
    }
  }

  /// For on-device runs: stop between (or in the middle of) batches when an
  /// Ask request needs the model or the app left the foreground.
  bool _shouldYield() {
    final y = _runtime.interactivePending || !_isForeground();
    if (y) _yielded = true;
    return y;
  }

  /// Hook for any source's sync (SMS today, email too) — cheap no-op when
  /// nothing is configured, toggled on, or pending.
  Future<void> runAfterSync() async {
    final config = ref.read(llmConfigProvider);
    if (!config.isConfigured || _busy) return;
    if (!config.aiReadUnparsed && !config.aiCategorise) return;
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) return;
    if (await _client() is LlmBudget) return _autoRunOnDevice();
    if (config.aiReadUnparsed) await readUnparsed();
    if (config.aiCategorise) await categorise();
  }

  Future<void> _autoRunOnDevice({bool resuming = false}) async {
    if (_autoRunPending) return;
    final prefs = ref.read(prefsProvider);
    final last = prefs.getInt(lastAutoRunKey);
    final charging = await _isCharging();
    if (!resuming &&
        !policy.shouldAutoRun(
          lastRun: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
          now: DateTime.now(),
          charging: charging,
        )) {
      return;
    }
    _autoRunPending = true;
    try {
      await Future<void>.delayed(policy.startDelay);
      await _runtime.scheduler.whenQuiet(policy.quietBeforeStart);
      if (_busy || _shouldYield()) {
        _scheduleResume();
        return;
      }
      _yielded = false;
      final config = ref.read(llmConfigProvider);
      var stopped = false;
      if (config.aiReadUnparsed) {
        final r = await readUnparsed(maxBatches: policy.maxBatchesPerRun);
        stopped = _yielded || r?.error != null;
      }
      if (config.aiCategorise && !stopped) await categorise(maxBatches: policy.maxBatchesPerRun);
      if (_yielded) {
        debugPrint('[pckt-ondevice] background AI paused for the user; will resume');
        _scheduleResume();
      } else {
        await prefs.setInt(lastAutoRunKey, DateTime.now().millisecondsSinceEpoch);
      }
    } finally {
      _autoRunPending = false;
    }
  }

  /// After a pause for the user, try again once the model has been quiet.
  void _scheduleResume() {
    if (_resumes >= policy.maxResumesPerSession) return;
    _resumes++;
    unawaited(
      _runtime.scheduler.whenQuiet(policy.quietBeforeStart).then((_) {
        if (_isForeground()) return _autoRunOnDevice(resuming: true);
      }),
    );
  }

  Future<FallbackReport?> readUnparsed({int? maxBatches}) async {
    final config = ref.read(llmConfigProvider);
    if (!config.aiReadUnparsed || _busy) return null;
    final client = await _client();
    if (client == null) return null;
    final onDevice = client is LlmBudget;
    final parser = LlmFallbackParser(
      db: ref.read(databaseProvider),
      ingestion: ref.read(ingestionProvider),
      client: client,
      // A phone-sized context window fits one or two messages per request.
      batchSize: onDevice ? 2 : 8,
      maxChars: onDevice ? 700 : 1800,
      pause: onDevice ? Duration.zero : const Duration(milliseconds: 800),
      maxBatches: maxBatches,
      shouldStop: onDevice ? _shouldYield : null,
    );
    if ((await parser.pending()).isEmpty) return null;
    state = const AiJobsState(running: 'Reading messages');
    try {
      final report = await parser.run(
        onProgress: (d, t) => state = AiJobsState(running: 'Reading messages', progress: (d, t)),
      );
      _noteError(report.error);
      state = AiJobsState(
        lastResult: 'AI reader: $report${report.stoppedEarly ? ' · more later' : ''}',
        error: report.error,
      );
      return report;
    } catch (e, st) {
      debugPrint('AI reader failed: $e\n$st');
      state = AiJobsState(error: 'AI reader failed: $e');
      return null;
    }
  }

  /// [all] re-checks every eligible transaction; otherwise only ones added
  /// since the last run.
  Future<CategoriseReport?> categorise({bool all = false, int? maxBatches}) async {
    final config = ref.read(llmConfigProvider);
    if (!config.aiCategorise || _busy) return null;
    final client = await _client();
    if (client == null) return null;
    final onDevice = client is LlmBudget;
    final prefs = ref.read(prefsProvider);
    final cursor = all ? 0 : prefs.getInt(_cursorKey) ?? 0;
    final job = AiCategorizer(
      db: ref.read(databaseProvider),
      client: client,
      batchSize: onDevice ? 8 : 40,
      maxBatches: maxBatches,
      shouldStop: onDevice ? _shouldYield : null,
    );
    if ((await job.candidates(afterId: cursor)).isEmpty) {
      if (all) state = const AiJobsState(lastResult: 'Nothing left in "Other" to categorise');
      return null;
    }
    state = const AiJobsState(running: 'Categorising');
    try {
      final report = await job.run(
        afterId: cursor,
        onProgress: (d, t) => state = AiJobsState(running: 'Categorising', progress: (d, t)),
      );
      final maxId = report.maxId;
      if (maxId != null && maxId > (prefs.getInt(_cursorKey) ?? 0)) await prefs.setInt(_cursorKey, maxId);
      _noteError(report.error);
      state = AiJobsState(
        lastResult: 'AI categories: $report${report.stoppedEarly ? ' · more later' : ''}',
        error: report.error,
      );
      return report;
    } catch (e, st) {
      debugPrint('AI categorise failed: $e\n$st');
      state = AiJobsState(error: 'AI categorisation failed: $e');
      return null;
    }
  }

  void _noteError(String? error) =>
      _backoffUntil = error == null ? null : DateTime.now().add(const Duration(minutes: 5));
}

final aiJobsProvider = NotifierProvider<AiJobsController, AiJobsState>(AiJobsController.new);
