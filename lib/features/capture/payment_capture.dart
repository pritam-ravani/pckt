import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../ingestion/ingestion_service.dart';
import '../../ingestion/parser/parsed_txn.dart';
import '../../providers.dart';
import '../activity/quick_entry.dart';

/// A payment the native listener saw, or a category pick made after the app
/// had already taken that payment ([choiceOnly]).
class CapturedPayment {
  const CapturedPayment({
    required this.id,
    this.app = '',
    this.title = '',
    this.text = '',
    this.postedAt,
    this.amountMinor = 0,
    this.credit = false,
    this.merchant,
    this.category,
    this.choiceOnly = false,
  });

  factory CapturedPayment.fromJson(Map<String, Object?> j) => CapturedPayment(
    id: j['id']! as String,
    app: (j['app'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
    text: (j['text'] as String?) ?? '',
    postedAt: j['postedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['postedAt']! as int),
    amountMinor: (j['amountMinor'] as int?) ?? 0,
    credit: (j['credit'] as bool?) ?? false,
    merchant: j['merchant'] as String?,
    category: j['category'] as String?,
    choiceOnly: (j['choiceOnly'] as bool?) ?? false,
  );

  final String id, app, title, text;
  final DateTime? postedAt;
  final int amountMinor;
  final bool credit, choiceOnly;
  final String? merchant, category;

  String get externalId => 'notif:$id';
}

/// Native side of payment notifications (see PaymentNotificationListener.kt).
class PaymentCaptureChannel {
  static const _channel = MethodChannel('pckt/notifications');

  bool get isSupported => Platform.isAndroid;

  Future<bool> hasAccess() async => isSupported && (await _channel.invokeMethod<bool>('hasAccess') ?? false);
  Future<void> openAccessSettings() => _channel.invokeMethod('openAccessSettings');
  Future<void> openAppDetails() => _channel.invokeMethod('openAppDetails');
  Future<bool> takeOpenReview() async => isSupported && (await _channel.invokeMethod<bool>('takeOpenReview') ?? false);

  Future<List<CapturedPayment>> pending() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeMethod<String>('pending') ?? '[]';
    return [for (final j in jsonDecode(raw) as List) CapturedPayment.fromJson((j as Map).cast())];
  }

  Future<void> remove(List<String> ids) => _channel.invokeMethod('remove', ids);
}

/// Moves waiting payments into the encrypted database and refreshes the
/// category guesses the native prompt offers.
class PaymentCaptureService {
  PaymentCaptureService(this.db, this.ingestion, this.channel, this.writeHints);

  final AppDatabase db;
  final IngestionService ingestion;
  final PaymentCaptureChannel channel;
  final Future<void> Function(String json) writeHints;

  var _running = false;

  Future<IngestReport?> drain() async {
    if (_running) return null;
    _running = true;
    try {
      final items = await channel.pending();
      if (items.isEmpty) return null;
      final categories = {for (final c in await db.allCategories()) c.name.toLowerCase(): c.id};
      int? idOf(String? name) => name == null ? null : categories[name.toLowerCase()];

      final report = await ingestion.ingestParsed([
        for (final p in items)
          if (!p.choiceOnly) (_raw(p), _parsed(p, idOf(p.category))),
      ]);
      for (final p in items) {
        final category = idOf(p.category);
        if (category != null) await _applyChoice(p, category);
      }
      await channel.remove([for (final p in items) p.id]);
      await refreshHints();
      return report;
    } finally {
      _running = false;
    }
  }

  RawInput _raw(CapturedPayment p) => RawInput(
    source: SourceKind.notification,
    externalId: p.externalId,
    sender: p.app,
    body: [p.title, p.text].where((s) => s.isNotEmpty).join(' · '),
    receivedAt: p.postedAt ?? DateTime.now(),
  );

  /// Without the user's pick, low confidence sends it to Review.
  ParsedTxn _parsed(CapturedPayment p, int? category) => ParsedTxn(
    amountMinor: p.amountMinor,
    currency: 'INR',
    direction: p.credit ? TxnDirection.credit : TxnDirection.debit,
    occurredAt: p.postedAt ?? DateTime.now(),
    mode: PaymentMode.upi,
    confidence: category == null ? 0.6 : 1,
    merchant: p.merchant,
    categoryId: category,
  );

  /// Files the payment under the user's pick and teaches it for the merchant.
  /// A suspected duplicate stays in Review for the user to settle.
  Future<void> _applyChoice(CapturedPayment p, int category) async {
    final raw =
        await (db.select(db.rawMessages)
              ..where((m) => m.source.equalsValue(SourceKind.notification) & m.externalId.equals(p.externalId)))
            .getSingleOrNull();
    final id = raw?.transactionId;
    if (id == null) return;
    final txn = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    await db.setCategory(id, category, learnPattern: txn.merchant?.trim().toLowerCase());
    if (txn.duplicateOfId == null) await db.confirm(id);
  }

  /// Merchant → category for the prompt's first guess, plus the most used
  /// categories. Limited because it sits outside the encrypted database.
  Future<void> refreshHints() async {
    final names = {for (final c in await db.allCategories()) c.id: c.name};
    final rows = await db.recentWithMerchant(TxnDirection.debit);
    final merchants = <String, String>{
      for (final s in rankMerchants(rows, limit: 100))
        if (names[s.categoryId] != null) s.name.toLowerCase(): names[s.categoryId]!,
      for (final r in await db.allMerchantRules())
        if (names[r.categoryId] != null) r.pattern: names[r.categoryId]!,
    };
    final counts = <String, int>{};
    for (final t in rows) {
      final name = names[t.categoryId];
      if (name != null && name != 'Other') counts[name] = (counts[name] ?? 0) + 1;
    }
    final top = (counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!))).take(3).toList();
    await writeHints(
      jsonEncode({
        'm': merchants,
        'top': top.isEmpty ? const ['Food & Dining', 'Groceries', 'Shopping'] : top,
      }),
    );
  }
}

final paymentCaptureChannelProvider = Provider((ref) => PaymentCaptureChannel());

final paymentCaptureProvider = Provider((ref) {
  final prefs = ref.watch(prefsProvider);
  return PaymentCaptureService(
    ref.watch(databaseProvider),
    ref.watch(ingestionProvider),
    ref.watch(paymentCaptureChannelProvider),
    (json) => prefs.setString(PrefKeys.notifHints, json),
  );
});
