import 'package:drift/drift.dart';

import '../core/theme/palette.dart';
import '../data/db/database.dart';
import 'categorizer.dart';
import 'dedup/dedup_engine.dart';
import 'parser/email_senders.dart';
import 'parser/parsed_txn.dart';
import 'parser/sms_parser.dart';

class IngestReport {
  int seen = 0, added = 0, merged = 0, flagged = 0, ignored = 0, unparsed = 0;

  @override
  String toString() => 'seen $seen · added $added · merged $merged · review $flagged · ignored $ignored';
}

/// Source-agnostic pipeline: raw message → parse → dedup → categorise → store.
/// SMS, email and anything else just produce [RawInput]s.
class IngestionService {
  IngestionService(
    this.db, {
    this.homeCurrency = 'INR',
    Map<SourceKind, MessageParser> parsers = const {},
    this.dedup = const DedupEngine(),
  }) : parsers = {SourceKind.sms: SmsParser(home: homeCurrency), ...parsers};

  final AppDatabase db;

  /// Assumed for amounts whose source names no currency; new accounts are
  /// held in it.
  final String homeCurrency;

  /// Parser per source. Sources without their own parser fall back to SMS
  /// rules, which also read most plain-text bank alert emails.
  final Map<SourceKind, MessageParser> parsers;
  final DedupEngine dedup;

  MessageParser _parserFor(SourceKind s) => parsers[s] ?? parsers[SourceKind.sms]!;

  Future<IngestReport> ingest(List<RawInput> inputs) async {
    final report = IngestReport();
    if (inputs.isEmpty) return report;

    final known = <SourceKind, Set<String>>{};
    for (final s in inputs.map((i) => i.source).toSet()) {
      known[s] = await db.knownExternalIds(s);
    }
    final fresh = inputs.where((i) => !known[i.source]!.contains(i.externalId)).toList()
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    report.seen = fresh.length;
    if (fresh.isEmpty) return report;

    final categorizer = Categorizer(await db.allCategories(), await db.allMerchantRules());
    final accounts = await db.allAccounts();

    // Chunked transactions keep the UI responsive during big first imports.
    for (var i = 0; i < fresh.length; i += 200) {
      final chunk = fresh.sublist(i, (i + 200).clamp(0, fresh.length));
      await db.transaction(() async {
        for (final input in chunk) {
          await _ingestOne(input, categorizer, accounts, report);
        }
      });
    }
    return report;
  }

  Future<void> _ingestOne(RawInput input, Categorizer categorizer, List<Account> accounts, IngestReport report) async {
    RawMessagesCompanion raw(ParseStatus status, {String? reason, int? txnId, double? score}) =>
        RawMessagesCompanion.insert(
          source: input.source,
          externalId: input.externalId,
          sender: input.sender,
          body: input.body,
          receivedAt: input.receivedAt,
          parseStatus: status,
          ignoreReason: Value(reason),
          transactionId: Value(txnId),
          mergeScore: Value(score),
        );

    switch (_parserFor(input.source).parse(input)) {
      case Ignored(:final reason):
        report.ignored++;
        await db.into(db.rawMessages).insert(raw(ParseStatus.ignored, reason: reason), mode: InsertMode.insertOrIgnore);
      case Unparsed(:final reason):
        report.unparsed++;
        await db
            .into(db.rawMessages)
            .insert(raw(ParseStatus.pendingLlm, reason: reason), mode: InsertMode.insertOrIgnore);
      case Parsed(:final txn):
        await _store(
          txn,
          source: input.source,
          sender: input.sender,
          body: input.body,
          categorizer: categorizer,
          accounts: accounts,
          report: report,
          writeRaw: (status, {txnId, score}) => db
              .into(db.rawMessages)
              .insert(
                raw(status, txnId: txnId, score: score),
                mode: InsertMode.insertOrIgnore,
              ),
        );
    }
  }

  /// Re-reads stored messages that an older parser skipped for want of an
  /// amount or a direction ("USD 12.50 spent", "card was used for Rs.640"),
  /// so they appear without a destructive full re-import. Rows that still
  /// don't parse are left exactly as they were. Returns how many became
  /// (or merged into) transactions.
  Future<int> reparseSkipped() async {
    final rows =
        await (db.select(db.rawMessages)..where(
              (m) =>
                  (m.parseStatus.equalsValue(ParseStatus.ignored) &
                      m.ignoreReason.isIn(const ['No amount', 'Not a transaction'])) |
                  (m.parseStatus.equalsValue(ParseStatus.pendingLlm) &
                      m.ignoreReason.isIn(const ['Could not read amount', 'Could not tell debit from credit'])),
            ))
            .get();
    var n = 0;
    for (final m in rows) {
      final input = RawInput(
        source: m.source,
        externalId: m.externalId,
        sender: m.sender,
        body: m.body,
        receivedAt: m.receivedAt,
      );
      if (_parserFor(m.source).parse(input) case Parsed(:final txn)) {
        await applyParsed(m, txn);
        n++;
      }
    }
    return n;
  }

  /// Applies a transaction extracted out-of-band (e.g. by the LLM fallback)
  /// to a raw message that is already stored. Runs the same dedup →
  /// categorise → store path as [ingest], but updates the existing raw row
  /// instead of inserting a new one. Returns the resulting raw status
  /// ([ParseStatus.parsed] or [ParseStatus.merged]).
  Future<ParseStatus> applyParsed(RawMessage message, ParsedTxn txn, {IngestReport? report}) async {
    final categorizer = Categorizer(await db.allCategories(), await db.allMerchantRules());
    final accounts = await db.allAccounts();
    late ParseStatus result;
    await db.transaction(() async {
      await _store(
        txn,
        source: message.source,
        sender: message.sender,
        body: message.body,
        categorizer: categorizer,
        accounts: accounts,
        report: report ?? IngestReport(),
        writeRaw: (status, {txnId, score}) async {
          result = status;
          await (db.update(db.rawMessages)..where((m) => m.id.equals(message.id))).write(
            RawMessagesCompanion(
              parseStatus: Value(status),
              transactionId: Value(txnId),
              mergeScore: Value(score),
              ignoreReason: const Value(null),
            ),
          );
        },
      );
    });
    return result;
  }

  /// Shared tail of the pipeline for a parsed transaction: dedup against
  /// existing transactions, then merge or insert, then record the raw
  /// message's outcome via [writeRaw].
  Future<void> _store(
    ParsedTxn txn, {
    required SourceKind source,
    required String sender,
    required String body,
    required Categorizer categorizer,
    required List<Account> accounts,
    required IngestReport report,
    required Future<void> Function(ParseStatus status, {int? txnId, double? score}) writeRaw,
  }) async {
    final currency = txn.currency ?? homeCurrency;
    final converted = txn.convertedMinor != null && txn.convertedCurrency != null && txn.convertedCurrency != currency
        ? (txn.convertedMinor!, txn.convertedCurrency!)
        : null;
    final sourceKey = DedupEngine.sourceKey(source, sender);
    final match = dedup.best(txn, sourceKey, await _candidates(txn, currency, converted));

    if (match != null && match.score >= DedupEngine.autoMerge) {
      report.merged++;
      await _enrich(
        match.candidate.id,
        txn,
        currency: currency,
        converted: converted,
        source: source,
        sender: sender,
        body: body,
        categorizer: categorizer,
      );
      await writeRaw(ParseStatus.merged, txnId: match.candidate.id, score: match.score);
      return;
    }

    final possibleDup = match != null && match.score >= DedupEngine.review;
    final needsReview = possibleDup || txn.confidence < 0.7;
    if (needsReview) report.flagged++;
    report.added++;

    final account = await _resolveAccount(txn, body, accounts);
    final id = await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            amountMinor: txn.amountMinor,
            currency: Value(currency),
            convertedMinor: Value(converted?.$1),
            convertedCurrency: Value(converted?.$2),
            direction: txn.direction,
            occurredAt: txn.occurredAt,
            merchant: Value(txn.merchant),
            counterparty: Value(txn.counterparty),
            categoryId: Value(categorizer.categorize(txn, body)),
            accountId: Value(account?.id),
            accountHint: Value(txn.accountHint),
            mode: txn.mode,
            reference: Value(txn.reference),
            status: needsReview ? TxnStatus.needsReview : TxnStatus.confirmed,
            isTransfer: Value(txn.transferHint),
            duplicateOfId: Value(possibleDup ? match.candidate.id : null),
          ),
        );
    await writeRaw(ParseStatus.parsed, txnId: id);
    if (account != null && !txn.transferHint) {
      await _detectSelfTransfer(id, txn, currency, account.id, categorizer.transferId);
    }
  }

  Future<List<DedupCandidate>> _candidates(ParsedTxn t, String currency, (int, String)? converted) async {
    final rows = await db.candidatesFor(
      amountMinor: t.amountMinor,
      currency: currency,
      also: converted,
      direction: t.direction,
      at: t.occurredAt,
    );
    return [
      for (final r in rows)
        DedupCandidate(
          id: r.id,
          occurredAt: r.occurredAt,
          reference: r.reference,
          accountHint: r.accountHint,
          merchant: r.merchant,
          counterparty: r.counterparty,
          sourceKeys: {for (final m in await db.sourcesOf(r.id)) DedupEngine.sourceKey(m.source, m.sender)},
        ),
    ];
  }

  /// Fill gaps on the existing transaction with whatever the new source knows.
  /// A merchant receipt email names the merchant better than a bank alert
  /// ("BUNDL TECHNOLOGIES", a VPA, or nothing), so it replaces it and the
  /// category is re-derived unless the user picked one.
  Future<void> _enrich(
    int id,
    ParsedTxn t, {
    required String currency,
    required (int, String)? converted,
    required SourceKind source,
    required String sender,
    required String body,
    required Categorizer categorizer,
  }) async {
    final existing = await (db.select(db.transactions)..where((x) => x.id.equals(id))).getSingle();
    final betterMerchant =
        t.merchant != null &&
        t.merchant != existing.merchant &&
        source == SourceKind.email &&
        EmailSenders.isMerchant(sender);
    final merchant = betterMerchant || existing.merchant == null ? t.merchant : existing.merchant;
    final recategorize = betterMerchant && !existing.categoryLocked && !existing.isTransfer;
    // A rupee-only alert matched a foreign spend (or the other way round):
    // the second source tells us what it cost at home.
    final conversion = existing.convertedMinor != null
        ? null
        : currency != existing.currency
        ? (t.amountMinor, currency)
        : converted != null && converted.$2 != existing.currency
        ? converted
        : null;
    await (db.update(db.transactions)..where((x) => x.id.equals(id))).write(
      TransactionsCompanion(
        reference: existing.reference == null ? Value(t.reference) : const Value.absent(),
        convertedMinor: conversion == null ? const Value.absent() : Value(conversion.$1),
        convertedCurrency: conversion == null ? const Value.absent() : Value(conversion.$2),
        merchant: merchant != existing.merchant ? Value(merchant) : const Value.absent(),
        categoryId: recategorize
            ? Value(
                categorizer.categorize(
                      ParsedTxn(
                        amountMinor: existing.amountMinor,
                        direction: existing.direction,
                        occurredAt: existing.occurredAt,
                        mode: existing.mode,
                        confidence: 1,
                        merchant: merchant,
                        counterparty: existing.counterparty,
                      ),
                      body,
                    ) ??
                    existing.categoryId,
              )
            : const Value.absent(),
        counterparty: existing.counterparty == null ? Value(t.counterparty) : const Value.absent(),
        accountHint: existing.accountHint == null ? Value(t.accountHint) : const Value.absent(),
        // A second independent source confirming the payment is good evidence.
        status: existing.duplicateOfId == null ? const Value(TxnStatus.confirmed) : const Value.absent(),
      ),
    );
  }

  /// Finds or auto-creates the account a message refers to (by last 4 digits).
  Future<Account?> _resolveAccount(ParsedTxn t, String body, List<Account> accounts) async {
    final hint = t.accountHint;
    if (hint == null) return null;
    for (final a in accounts) {
      if (a.last4 != null &&
          (a.last4!.endsWith(hint) || hint.endsWith(a.last4!)) &&
          (a.institution == null || t.institution == null || a.institution == t.institution)) {
        return a;
      }
    }
    final isCard = RegExp(r'credit card|\bcc\b', caseSensitive: false).hasMatch(body);
    final account = Account(
      id: -1,
      name: isCard ? '${t.institution ?? ''} Card'.trim() : (t.institution ?? 'Bank account'),
      kind: isCard ? AccountKind.creditCard : AccountKind.bank,
      institution: t.institution,
      last4: hint,
      color: Palette.categories[(accounts.length * 5 + 6) % Palette.categories.length].toARGB32(),
      archived: false,
      currency: homeCurrency,
    );
    final id = await db.into(db.accounts).insert(account.toCompanion(true).copyWith(id: const Value.absent()));
    final created = account.copyWith(id: id);
    accounts.add(created);
    return created;
  }

  /// Debit from one own account + equal credit into another within an hour
  /// ⇒ both legs are a self-transfer and shouldn't count as spend/income.
  Future<void> _detectSelfTransfer(int id, ParsedTxn t, String currency, int accountId, int? transferCategory) async {
    final opposite = t.direction == TxnDirection.debit ? TxnDirection.credit : TxnDirection.debit;
    final legs = await db.candidatesFor(
      amountMinor: t.amountMinor,
      currency: currency,
      direction: opposite,
      at: t.occurredAt,
      window: const Duration(hours: 1),
    );
    final other = legs.where((l) => l.accountId != null && l.accountId != accountId && !l.isTransfer).firstOrNull;
    if (other == null) return;
    await (db.update(db.transactions)..where((x) => x.id.isIn([id, other.id]))).write(
      TransactionsCompanion(
        isTransfer: const Value(true),
        categoryId: transferCategory == null ? const Value.absent() : Value(transferCategory),
      ),
    );
  }
}
