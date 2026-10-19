import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/db/database.dart';
import '../ingestion/email/email_sync.dart';
import '../providers.dart';
import 'ai_categorizer.dart';
import 'fallback_parser.dart';
import 'llm_client.dart';
import 'llm_config.dart';

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

/// Background AI work: reading unreadable messages and categorising.
/// Runs after each sync when the matching privacy toggle is on, or on demand.
class AiJobsController extends Notifier<AiJobsState> {
  static const _cursorKey = 'llm.categoriseCursor';
  DateTime? _backoffUntil;

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
      return await ref.read(llmClientProvider.future);
    } catch (_) {
      return null;
    }
  }

  /// Hook for any source's sync (SMS today, email too) — cheap no-op when
  /// nothing is configured, toggled on, or pending.
  Future<void> runAfterSync() async {
    final config = ref.read(llmConfigProvider);
    if (!config.isConfigured || _busy) return;
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) return;
    if (config.aiReadUnparsed) await readUnparsed();
    if (config.aiCategorise) await categorise();
  }

  Future<FallbackReport?> readUnparsed() async {
    final config = ref.read(llmConfigProvider);
    if (!config.aiReadUnparsed || _busy) return null;
    final client = await _client();
    if (client == null) return null;
    final parser = LlmFallbackParser(
      db: ref.read(databaseProvider),
      ingestion: ref.read(ingestionProvider),
      client: client,
    );
    if ((await parser.pending()).isEmpty) return null;
    state = const AiJobsState(running: 'Reading messages');
    try {
      final report = await parser.run(
        onProgress: (d, t) => state = AiJobsState(running: 'Reading messages', progress: (d, t)),
      );
      _noteError(report.error);
      state = AiJobsState(lastResult: 'AI reader: $report', error: report.error);
      return report;
    } catch (e, st) {
      debugPrint('AI reader failed: $e\n$st');
      state = AiJobsState(error: 'AI reader failed: $e');
      return null;
    }
  }

  /// [all] re-checks every eligible transaction; otherwise only ones added
  /// since the last run.
  Future<CategoriseReport?> categorise({bool all = false}) async {
    final config = ref.read(llmConfigProvider);
    if (!config.aiCategorise || _busy) return null;
    final client = await _client();
    if (client == null) return null;
    final prefs = ref.read(prefsProvider);
    final cursor = all ? 0 : prefs.getInt(_cursorKey) ?? 0;
    final job = AiCategorizer(db: ref.read(databaseProvider), client: client);
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
      state = AiJobsState(lastResult: 'AI categories: $report', error: report.error);
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
