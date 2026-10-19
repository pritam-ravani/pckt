import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/database.dart';
import '../../providers.dart';
import '../ingestion_service.dart';
import 'email_source.dart';
import 'gmail_api_source.dart';
import 'imap_source.dart';

/// Bump when email parsing changes should apply to already-imported mail.
const emailParserVersion = 1;

abstract final class EmailPrefKeys {
  static const enabled = 'email.enabled';
  static const provider = 'email.provider';
  static const address = 'email.address';
  static const host = 'email.host';
  static const port = 'email.port';
  static const ssl = 'email.ssl';
  static const lastSync = 'email.lastSyncMillis';
  static const importFrom = 'email.importFromMillis';
  static const parserVersion = 'email.parserVersion';
}

/// SecretStore key for the IMAP app password.
const emailPasswordSecret = 'email.password';

typedef EmailSourceFactory = EmailSource Function(EmailAccount account, String? password);

EmailSource defaultEmailSourceFactory(EmailAccount account, String? password) =>
    account.provider == EmailProvider.gmailOAuth ? GmailApiSource() : ImapEmailSource(account, password ?? '');

/// Overridden in tests with a fake mailbox.
final emailSourceFactoryProvider = Provider<EmailSourceFactory>((ref) => defaultEmailSourceFactory);

final emailStatsProvider = StreamProvider<Map<ParseStatus, int>>(
  (ref) => ref.watch(databaseProvider).watchParseStats(SourceKind.email),
);

class EmailSyncState {
  const EmailSyncState({
    this.enabled = false,
    this.running = false,
    this.account,
    this.lastSync,
    this.lastReport,
    this.error,
  });

  final bool enabled;
  final bool running;
  final EmailAccount? account;
  final DateTime? lastSync;
  final IngestReport? lastReport;
  final String? error;

  EmailSyncState copyWith({
    bool? enabled,
    bool? running,
    EmailAccount? account,
    DateTime? lastSync,
    IngestReport? lastReport,
    String? error,
  }) => EmailSyncState(
    enabled: enabled ?? this.enabled,
    running: running ?? this.running,
    account: account ?? this.account,
    lastSync: lastSync ?? this.lastSync,
    lastReport: lastReport ?? this.lastReport,
    error: error,
  );
}

/// Mirrors SmsSyncController: connect once with an import window, then
/// incremental syncs with a one-day overlap (already-seen Message-IDs are
/// skipped by the pipeline, so the overlap is free).
class EmailSyncController extends Notifier<EmailSyncState> {
  SharedPreferences get _prefs => ref.read(prefsProvider);
  Future<IngestReport?>? _inflight;

  @override
  EmailSyncState build() {
    final last = _prefs.getInt(EmailPrefKeys.lastSync);
    return EmailSyncState(
      enabled: _prefs.getBool(EmailPrefKeys.enabled) ?? false,
      account: _loadAccount(),
      lastSync: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  EmailAccount? _loadAccount() {
    final address = _prefs.getString(EmailPrefKeys.address);
    final provider = EmailProvider.values.asNameMap()[_prefs.getString(EmailPrefKeys.provider)];
    if (address == null || provider == null) return null;
    return EmailAccount(
      provider: provider,
      address: address,
      host: _prefs.getString(EmailPrefKeys.host),
      port: _prefs.getInt(EmailPrefKeys.port) ?? 993,
      ssl: _prefs.getBool(EmailPrefKeys.ssl) ?? true,
    );
  }

  /// Signs in without saving anything. Returns an error message or null.
  Future<String?> testConnection(EmailAccount account, String? password) async {
    try {
      await ref.read(emailSourceFactoryProvider)(account, password).test();
      return null;
    } on EmailConnectException catch (e) {
      return e.message;
    } catch (e) {
      return 'Connection failed: $e';
    }
  }

  /// Verifies the mailbox, stores the settings (password in the keystore)
  /// and starts importing the last [months]. The import continues in the
  /// background; returns false with [EmailSyncState.error] set on failure.
  Future<bool> connect(EmailAccount account, {String? password, int months = 3}) async {
    final error = await testConnection(account, password);
    if (error != null) {
      state = state.copyWith(error: error);
      return false;
    }
    await _save(account, password, months);
    unawaited(sync());
    return true;
  }

  /// Sign in with Google (Gmail API, `gmail.readonly`).
  Future<bool> connectGoogle({int months = 3}) async {
    try {
      final address = await GoogleGmailAuth.instance.signIn();
      await _save(EmailAccount(provider: EmailProvider.gmailOAuth, address: address), null, months);
      unawaited(sync());
      return true;
    } on EmailConnectException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: 'Google sign-in failed: $e');
      return false;
    }
  }

  Future<void> _save(EmailAccount account, String? password, int months) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - months, now.day);
    final previous = state.account;
    await _prefs.setString(EmailPrefKeys.provider, account.provider.name);
    await _prefs.setString(EmailPrefKeys.address, account.address);
    await _prefs.setString(EmailPrefKeys.host, account.host);
    await _prefs.setInt(EmailPrefKeys.port, account.port);
    await _prefs.setBool(EmailPrefKeys.ssl, account.ssl);
    await _prefs.setInt(EmailPrefKeys.importFrom, from.millisecondsSinceEpoch);
    await _prefs.setBool(EmailPrefKeys.enabled, true);
    await _prefs.remove(EmailPrefKeys.lastSync);
    final secrets = ref.read(secretStoreProvider);
    await secrets.write(emailPasswordSecret, account.provider.isImap ? password : null);
    if (previous?.provider == EmailProvider.gmailOAuth && account.provider != EmailProvider.gmailOAuth) {
      await GoogleGmailAuth.instance.signOut();
    }
    state = EmailSyncState(enabled: true, account: account);
  }

  /// Stops syncing and forgets the password. Imported transactions stay.
  Future<void> disconnect() async {
    final account = state.account;
    await _prefs.setBool(EmailPrefKeys.enabled, false);
    await ref.read(secretStoreProvider).delete(emailPasswordSecret);
    if (account?.provider == EmailProvider.gmailOAuth) {
      try {
        await GoogleGmailAuth.instance.signOut();
      } catch (e) {
        debugPrint('Google sign-out failed: $e');
      }
    }
    state = state.copyWith(enabled: false);
  }

  /// Incremental sync; concurrent callers share the running sync.
  Future<IngestReport?> sync() {
    if (!state.enabled || state.account == null) return Future.value();
    return _inflight ??= _sync().whenComplete(() => _inflight = null);
  }

  Future<IngestReport?> _sync() async {
    final account = state.account!;
    state = state.copyWith(running: true);
    try {
      final password = account.provider.isImap ? await ref.read(secretStoreProvider).read(emailPasswordSecret) : null;
      if (account.provider.isImap && (password == null || password.isEmpty)) {
        state = state.copyWith(running: false, error: 'Email password missing — reconnect in Settings');
        return null;
      }
      // Parser improved since the last import → re-parse everything once.
      if ((_prefs.getInt(EmailPrefKeys.parserVersion) ?? 0) != emailParserVersion) {
        await ref.read(databaseProvider).resetSource(SourceKind.email);
        await _prefs.remove(EmailPrefKeys.lastSync);
      }
      final last = _prefs.getInt(EmailPrefKeys.lastSync);
      final importFrom = _prefs.getInt(EmailPrefKeys.importFrom) ?? 0;
      final since = last == null
          ? DateTime.fromMillisecondsSinceEpoch(importFrom)
          : DateTime.fromMillisecondsSinceEpoch(last).subtract(const Duration(days: 1));
      final started = DateTime.now();
      final messages = await ref.read(emailSourceFactoryProvider)(account, password).fetchSince(since);
      final report = await ref.read(ingestionProvider).ingest(messages);
      await _prefs.setInt(EmailPrefKeys.lastSync, started.millisecondsSinceEpoch);
      await _prefs.setInt(EmailPrefKeys.parserVersion, emailParserVersion);
      state = state.copyWith(running: false, lastSync: started, lastReport: report);
      return report;
    } on EmailConnectException catch (e) {
      state = state.copyWith(running: false, error: e.message);
      return null;
    } catch (e, st) {
      debugPrint('Email sync failed: $e\n$st');
      state = state.copyWith(running: false, error: 'Sync failed: $e');
      return null;
    }
  }
}

final emailSyncProvider = NotifierProvider<EmailSyncController, EmailSyncState>(EmailSyncController.new);
