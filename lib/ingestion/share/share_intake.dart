import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/db/database.dart';
import '../ingestion_service.dart';
import '../parser/parsed_txn.dart';
import '../parser/senders.dart';

/// Text handed to Pckt from outside: the Android share sheet, or a
/// `pckt://ingest?text=…&sender=…` link (e.g. from an iOS Shortcuts
/// automation).
class SharedText {
  const SharedText({required this.text, this.sender, this.via = 'share'});

  final String text;
  final String? sender;

  /// "share" or "link" — informational only.
  final String via;

  /// Parses `pckt://ingest?text=…&sender=…`; null for any other URI.
  static SharedText? fromUri(Uri uri) {
    if (uri.scheme != 'pckt' || uri.host != 'ingest') return null;
    final text = uri.queryParameters['text']?.trim();
    if (text == null || text.isEmpty) return null;
    final sender = uri.queryParameters['sender']?.trim();
    return SharedText(text: text, sender: sender == null || sender.isEmpty ? null : sender, via: 'link');
  }

  /// The message as a pipeline input. A missing sender is guessed from the
  /// bank named in the text so the parser still knows the institution. The
  /// external id is a content hash, so sharing the same message twice is a
  /// no-op.
  RawInput toRawInput(DateTime now) {
    final body = text.trim();
    final s = sender?.trim();
    final guess = Senders.headerInText(body);
    final resolved = s != null && s.isNotEmpty ? s : (guess == null ? 'Shared' : 'SHARED-$guess');
    return RawInput(
      source: SourceKind.shortcut,
      externalId: 'share-${sha1.convert(utf8.encode('${resolved.toUpperCase()}\n$body')).toString().substring(0, 20)}',
      sender: resolved,
      body: body,
      receivedAt: now,
    );
  }
}

enum ShareOutcomeKind { added, merged, duplicate, ignored, unreadable }

class ShareOutcome {
  const ShareOutcome(this.kind, {this.txn, this.reason});

  final ShareOutcomeKind kind;
  final Transaction? txn;
  final String? reason;
}

/// Runs one shared text through the normal pipeline and reports what happened.
Future<ShareOutcome> ingestShared(IngestionService svc, SharedText shared, {DateTime? now}) async {
  final db = svc.db;
  final input = shared.toRawInput(now ?? DateTime.now());
  final report = await svc.ingest([input]);
  final raw = await (db.select(
    db.rawMessages,
  )..where((m) => m.source.equalsValue(SourceKind.shortcut) & m.externalId.equals(input.externalId))).getSingleOrNull();
  final txn = raw?.transactionId == null
      ? null
      : await (db.select(db.transactions)..where((t) => t.id.equals(raw!.transactionId!))).getSingleOrNull();
  if (report.seen == 0) return ShareOutcome(ShareOutcomeKind.duplicate, txn: txn);
  return switch (raw?.parseStatus) {
    ParseStatus.parsed => ShareOutcome(ShareOutcomeKind.added, txn: txn),
    ParseStatus.merged => ShareOutcome(ShareOutcomeKind.merged, txn: txn),
    ParseStatus.ignored => ShareOutcome(ShareOutcomeKind.ignored, reason: raw?.ignoreReason),
    _ => ShareOutcome(ShareOutcomeKind.unreadable, reason: raw?.ignoreReason),
  };
}

/// Collects shared texts from the platform before the UI is ready.
///
/// * Android: MainActivity queues ACTION_SEND / pckt://ingest intents and
///   pings `pckt/share` → `pending`; we pull them with `takePending`.
/// * iOS: Flutter's deep linking delivers pckt:// URLs as route pushes, which
///   this observer claims before the router sees them.
class IncomingShares with WidgetsBindingObserver {
  IncomingShares._();
  static final instance = IncomingShares._();

  static const _channel = MethodChannel('pckt/share');

  final _queue = <SharedText>[];
  final _controller = StreamController<void>.broadcast();
  bool _started = false;

  /// Fires whenever new items are queued; read them with [drain].
  Stream<void> get onPending => _controller.stream;

  /// Call once from main(), before runApp, so this observer precedes the router's.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'pending') await _pull();
      });
      unawaited(_pull());
    }
  }

  List<SharedText> drain() {
    final items = List.of(_queue);
    _queue.clear();
    return items;
  }

  bool get hasPending => _queue.isNotEmpty;

  void add(SharedText s) {
    _queue.add(s);
    _controller.add(null);
  }

  Future<void> _pull() async {
    try {
      final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('takePending') ?? const [];
      for (final r in rows) {
        final text = r['text'] as String?;
        if (text == null || text.trim().isEmpty) continue;
        add(SharedText(text: text, sender: r['sender'] as String?, via: r['via'] as String? ?? 'share'));
      }
    } on MissingPluginException {
      // Not running inside MainActivity (tests, other embedders).
    } catch (e) {
      debugPrint('Could not read shared text: $e');
    }
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final s = SharedText.fromUri(routeInformation.uri);
    if (s == null) return false;
    add(s);
    return true;
  }
}
