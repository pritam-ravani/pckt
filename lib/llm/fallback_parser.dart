import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/db/database.dart';
import '../ingestion/ingestion_service.dart';
import '../ingestion/parser/parsed_txn.dart';
import '../ingestion/parser/senders.dart';
import '../ingestion/parser/text_utils.dart';
import 'llm_client.dart';
import 'llm_json.dart';

class FallbackReport {
  int sent = 0, added = 0, merged = 0, ignored = 0, failed = 0;
  String? error;

  /// Stopped early (batch cap or paused for the user); rows stay pending.
  bool stoppedEarly = false;

  bool get changedAnything => added + merged + ignored + failed > 0;

  @override
  String toString() => 'read $sent · added $added · merged $merged · not transactions $ignored · unreadable $failed';
}

/// Sends messages the rule parser flagged as [ParseStatus.pendingLlm] to the
/// user's LLM and feeds real transactions through the normal dedup /
/// categorise / store path via [IngestionService.applyParsed].
///
/// Idempotent: only pending rows are picked up and every row leaves the
/// pending state once the model has answered (parsed, merged, ignored with
/// an `AI:` reason, or failed). Transient errors (network, 429, 5xx) leave
/// rows pending for the next run.
class LlmFallbackParser {
  LlmFallbackParser({
    required this.db,
    required this.ingestion,
    required this.client,
    this.batchSize = 8,
    this.maxMessages = 80,
    this.pause = const Duration(milliseconds: 800),
    this.maxChars = 1800,
    this.maxBatches,
    this.shouldStop,
  });

  final AppDatabase db;
  final IngestionService ingestion;
  final LlmClient client;
  final int batchSize;
  final int maxMessages;

  /// Requests per run (null = all pending). On-device runs are capped.
  final int? maxBatches;

  /// Checked before each batch and on errors: true means stop now and leave
  /// the rest pending (an Ask request needs the on-device model).
  final bool Function()? shouldStop;

  /// Gap between requests — a crude client-side rate limit.
  final Duration pause;

  /// ₹5 crore — anything bigger from an SMS is almost certainly misread.
  static const maxAmountMinor = 5000000000;

  /// Long emails are clipped; the transaction details are near the top.
  final int maxChars;

  static const systemPrompt = '''
You read Indian bank, card, UPI and wallet alert messages (SMS or email) that a rule-based parser could not handle.
For each message decide whether it reports a COMPLETED money movement on the user's own account, card or wallet.
NOT transactions: OTPs, promotions/offers, reminders, upcoming/scheduled/due debits, failed/declined/reversed attempts, payment requests, balance-only alerts, statements, mandate/autopay setup.

Reply with ONLY JSON, no prose:
{"results":[{"id":<id>,"isTransaction":true|false,"amount":<rupees as number>,"direction":"debit"|"credit","merchant":<payee/payer display name or null>,"counterparty":<VPA or raw name or null>,"accountLast4":<last 3-4 digits of the user's account/card or null>,"reference":<UPI ref/RRN/UTR or null>,"mode":"upi"|"card"|"netbanking"|"neft"|"imps"|"rtgs"|"atm"|"wallet"|"other","reason":<few words>}]}

Rules: copy the amount exactly from the text, never compute or guess it. "debit" = money left the user's account. If unsure, set isTransaction false and say why in reason. Return one result per input id.''';

  Future<List<RawMessage>> pending() =>
      (db.select(db.rawMessages)
            ..where((m) => m.parseStatus.equalsValue(ParseStatus.pendingLlm))
            ..orderBy([(m) => OrderingTerm.desc(m.receivedAt)])
            ..limit(maxMessages))
          .get();

  Future<FallbackReport> run({void Function(int done, int total)? onProgress}) async {
    final report = FallbackReport();
    final rows = await pending();
    for (var i = 0, n = 0; i < rows.length; i += batchSize, n++) {
      if ((maxBatches != null && n >= maxBatches!) || (shouldStop?.call() ?? false)) {
        report.stoppedEarly = true;
        break;
      }
      final batch = rows.sublist(i, (i + batchSize).clamp(0, rows.length));
      if (i > 0) await Future<void>.delayed(pause);
      try {
        await _runBatch(batch, report);
      } on LlmException catch (e) {
        if (shouldStop?.call() ?? false) {
          report.stoppedEarly = true;
        } else {
          report.error = e.userMessage;
        }
        break; // stop on the first provider error; rows stay pending
      }
      onProgress?.call(i + batch.length, rows.length);
    }
    return report;
  }

  Future<void> _runBatch(List<RawMessage> batch, FallbackReport report) async {
    final input = [
      for (final m in batch)
        {
          'id': m.id,
          'source': m.source.name,
          'sender': m.sender,
          'text': m.body.length > maxChars ? m.body.substring(0, maxChars) : m.body,
        },
    ];
    report.sent += batch.length;
    final res = await client.chat(system: systemPrompt, messages: [UserMessage(jsonEncode(input))], maxTokens: 2048);
    final byId = {for (final r in extractResults(res.text)) asInt(r['id']): r};
    for (final m in batch) {
      final r = byId[m.id];
      final outcome = r == null ? const _Failed('no answer') : _interpret(r, m);
      switch (outcome) {
        case _Txn(:final txn):
          final status = await ingestion.applyParsed(m, txn);
          status == ParseStatus.merged ? report.merged++ : report.added++;
        case _NotTxn(:final reason):
          report.ignored++;
          await _mark(m.id, ParseStatus.ignored, 'AI: $reason');
        case _Failed(:final reason):
          report.failed++;
          await _mark(m.id, ParseStatus.failed, 'AI could not read it ($reason)');
      }
    }
  }

  Future<void> _mark(int id, ParseStatus status, String reason) =>
      (db.update(db.rawMessages)..where((m) => m.id.equals(id))).write(
        RawMessagesCompanion(parseStatus: Value(status), ignoreReason: Value(reason)),
      );

  /// Defensive validation of one model answer.
  static _Outcome _interpret(Map<String, dynamic> r, RawMessage m) {
    final isTxn = r['isTransaction'];
    if (isTxn != true && isTxn != 'true') {
      return _NotTxn(asString(r['reason'], max: 60) ?? 'not a transaction');
    }
    final amount = asNumber(r['amount']);
    if (amount == null || amount <= 0) return const _Failed('no amount');
    final minor = (amount * 100).round();
    if (minor > maxAmountMinor) return const _Failed('implausible amount');
    if (!amountAppearsIn(minor, m.body)) return const _Failed('amount not in message');

    final direction = switch (asString(r['direction'])?.toLowerCase()) {
      'debit' => TxnDirection.debit,
      'credit' => TxnDirection.credit,
      _ => null,
    };
    if (direction == null) return const _Failed('unknown direction');

    final mode = PaymentMode.values.firstWhere(
      (p) => p.name == asString(r['mode'])?.toLowerCase(),
      orElse: () => PaymentMode.other,
    );
    final last4 = asString(r['accountLast4'])?.replaceAll(RegExp(r'\D'), '');
    final ref = asString(r['reference'])?.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final counterparty = asString(r['counterparty'], max: 60);
    final merchantRaw = asString(r['merchant'], max: 60);
    final merchant =
        (merchantRaw == null ? null : cleanMerchant(merchantRaw)) ??
        (counterparty != null && counterparty.contains('@') ? merchantFromVpa(counterparty) : null);

    return _Txn(
      ParsedTxn(
        amountMinor: minor,
        direction: direction,
        occurredAt: m.receivedAt,
        mode: mode,
        // Below the review threshold: AI-read transactions ask the user to
        // glance at them once.
        confidence: 0.6,
        merchant: merchant,
        counterparty: counterparty,
        accountHint: last4 != null && last4.length >= 3 && last4.length <= 6 ? last4 : null,
        reference: ref != null && ref.length >= 6 && ref.length <= 30 ? ref : null,
        institution: m.source == SourceKind.sms ? Senders.parse(m.sender).institution : null,
        isPersonToPerson: counterparty != null && RegExp(r'^\d{10}@').hasMatch(counterparty),
      ),
    );
  }

  /// The integer rupee part must literally appear in the message (ignoring
  /// thousands separators) — guards against hallucinated amounts.
  static bool amountAppearsIn(int minor, String body) {
    final digits = body.replaceAll(',', '');
    final rupees = minor ~/ 100;
    return RegExp('(?<![0-9])$rupees(?![0-9])').hasMatch(digits);
  }
}

sealed class _Outcome {
  const _Outcome();
}

final class _Txn extends _Outcome {
  const _Txn(this.txn);
  final ParsedTxn txn;
}

final class _NotTxn extends _Outcome {
  const _NotTxn(this.reason);
  final String reason;
}

final class _Failed extends _Outcome {
  const _Failed(this.reason);
  final String reason;
}
