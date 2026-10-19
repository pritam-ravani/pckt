import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/format.dart';
import 'core/secrets.dart';
import 'data/db/database.dart';
import 'ingestion/ingestion_service.dart';
import 'ingestion/parser/email_parser.dart';
import 'ingestion/sms/sms_source.dart';

// ------------------------------------------------------------------ infra

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('overridden in main'));

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Bump whenever parser/categoriser changes should apply to already-imported
/// SMS. The next sync re-parses everything (manual entries and learned
/// merchant rules are kept).
const smsParserVersion = 3;

final ingestionProvider = Provider(
  (ref) => IngestionService(ref.watch(databaseProvider), parsers: const {SourceKind.email: EmailParser()}),
);
final smsSourceProvider = Provider((ref) => SmsSource());
final secretStoreProvider = Provider((ref) => SecretStore());

// --------------------------------------------------------------- settings

abstract final class PrefKeys {
  static const onboarded = 'onboarded';
  static const smsEnabled = 'sms.enabled';
  static const smsLastSync = 'sms.lastSyncMillis';
  static const smsImportFrom = 'sms.importFromMillis';
  static const smsParserVersion = 'sms.parserVersion';
  static const themeMode = 'themeMode';
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.values[ref.read(prefsProvider).getInt(PrefKeys.themeMode) ?? ThemeMode.dark.index];

  void set(ThemeMode mode) {
    ref.read(prefsProvider).setInt(PrefKeys.themeMode, mode.index);
    state = mode;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class OnboardedNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsProvider).getBool(PrefKeys.onboarded) ?? false;

  void complete() {
    ref.read(prefsProvider).setBool(PrefKeys.onboarded, true);
    state = true;
  }
}

final onboardedProvider = NotifierProvider<OnboardedNotifier, bool>(OnboardedNotifier.new);

// -------------------------------------------------------------- SMS sync

class SmsSyncState {
  const SmsSyncState({this.running = false, this.lastSync, this.lastReport, this.error, this.enabled = false});

  final bool running;
  final bool enabled;
  final DateTime? lastSync;
  final IngestReport? lastReport;
  final String? error;

  SmsSyncState copyWith({bool? running, bool? enabled, DateTime? lastSync, IngestReport? lastReport, String? error}) =>
      SmsSyncState(
        running: running ?? this.running,
        enabled: enabled ?? this.enabled,
        lastSync: lastSync ?? this.lastSync,
        lastReport: lastReport ?? this.lastReport,
        error: error,
      );
}

class SmsSyncController extends Notifier<SmsSyncState> {
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  SmsSyncState build() {
    final last = _prefs.getInt(PrefKeys.smsLastSync);
    return SmsSyncState(
      enabled: _prefs.getBool(PrefKeys.smsEnabled) ?? false,
      lastSync: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  /// Asks for permission and imports the last [months] of messages.
  Future<bool> connect({int months = 6}) async {
    final sms = ref.read(smsSourceProvider);
    if (!sms.isSupported) {
      state = state.copyWith(error: 'SMS access is only available on Android');
      return false;
    }
    if (!await sms.requestPermission()) {
      state = state.copyWith(error: 'SMS permission was denied');
      return false;
    }
    final from = DateTime(DateTime.now().year, DateTime.now().month - months, DateTime.now().day);
    await _prefs.setBool(PrefKeys.smsEnabled, true);
    await _prefs.setInt(PrefKeys.smsImportFrom, from.millisecondsSinceEpoch);
    await _prefs.remove(PrefKeys.smsLastSync);
    state = state.copyWith(enabled: true);
    await sync();
    return true;
  }

  Future<void> disconnect() async {
    await _prefs.setBool(PrefKeys.smsEnabled, false);
    state = state.copyWith(enabled: false);
  }

  /// Incremental sync. Re-reads a one-day overlap; already-seen message ids
  /// are skipped by the ingestion pipeline, so overlap is free.
  Future<IngestReport?> sync() async {
    if (state.running || !state.enabled) return null;
    final sms = ref.read(smsSourceProvider);
    if (!await sms.hasPermission()) {
      state = state.copyWith(error: 'SMS permission missing — reconnect in Settings');
      return null;
    }
    state = state.copyWith(running: true);
    try {
      // Parser improved since the last import → re-parse everything once.
      if ((_prefs.getInt(PrefKeys.smsParserVersion) ?? 0) != smsParserVersion) {
        await ref.read(databaseProvider).resetSource(SourceKind.sms);
        await _prefs.remove(PrefKeys.smsLastSync);
      }
      final last = _prefs.getInt(PrefKeys.smsLastSync);
      final importFrom = _prefs.getInt(PrefKeys.smsImportFrom) ?? 0;
      final since = last == null
          ? DateTime.fromMillisecondsSinceEpoch(importFrom)
          : DateTime.fromMillisecondsSinceEpoch(last).subtract(const Duration(days: 1));
      final started = DateTime.now();
      final messages = await sms.readSince(since);
      final report = await ref.read(ingestionProvider).ingest(messages);
      await _prefs.setInt(PrefKeys.smsLastSync, started.millisecondsSinceEpoch);
      await _prefs.setInt(PrefKeys.smsParserVersion, smsParserVersion);
      state = state.copyWith(running: false, lastSync: started, lastReport: report);
      return report;
    } catch (e, st) {
      debugPrint('SMS sync failed: $e\n$st');
      state = state.copyWith(running: false, error: 'Sync failed: $e');
      return null;
    }
  }
}

final smsSyncProvider = NotifierProvider<SmsSyncController, SmsSyncState>(SmsSyncController.new);

// ------------------------------------------------------------------ data

class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() => monthStart(DateTime.now());

  void shift(int delta) => state = DateTime(state.year, state.month + delta);
  bool get isCurrent => state == monthStart(DateTime.now());
}

final selectedMonthProvider = NotifierProvider<SelectedMonth, DateTime>(SelectedMonth.new);

final monthTxnsProvider = StreamProvider<List<TxnView>>((ref) {
  final m = ref.watch(selectedMonthProvider);
  return ref.watch(databaseProvider).watchTxns(from: m, to: nextMonth(m));
});

/// Last 6 months ending with the selected month — for trend charts.
final trendTxnsProvider = StreamProvider<List<TxnView>>((ref) {
  final m = ref.watch(selectedMonthProvider);
  return ref.watch(databaseProvider).watchTxns(from: DateTime(m.year, m.month - 5), to: nextMonth(m));
});

final allTxnsProvider = StreamProvider<List<TxnView>>((ref) => ref.watch(databaseProvider).watchTxns(limit: 2000));

final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(databaseProvider).watchCategories());

final accountsProvider = StreamProvider<List<Account>>((ref) => ref.watch(databaseProvider).watchAccounts());

final reviewCountProvider = StreamProvider<int>((ref) => ref.watch(databaseProvider).watchReviewCount());

final txnProvider = StreamProvider.family<TxnView?, int>((ref, id) => ref.watch(databaseProvider).watchTxn(id));

final txnSourcesProvider = StreamProvider.family<List<RawMessage>, int>(
  (ref, id) => ref.watch(databaseProvider).watchSourcesFor(id),
);

final smsStatsProvider = StreamProvider<Map<ParseStatus, int>>(
  (ref) => ref.watch(databaseProvider).watchParseStats(SourceKind.sms),
);
