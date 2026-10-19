import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../seed/default_categories.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

/// A transaction joined with its category for list display.
class TxnView {
  const TxnView(this.txn, this.category, this.account);
  final Transaction txn;
  final Category? category;
  final Account? account;
}

@DriftDatabase(tables: [Accounts, Categories, Transactions, RawMessages, MerchantRules])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'pckt'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('CREATE INDEX idx_txn_time ON transactions (occurred_at)');
      await customStatement('CREATE INDEX idx_txn_amount ON transactions (amount_minor, direction)');
      await customStatement('CREATE INDEX idx_txn_ref ON transactions (reference)');
      await _seedCategories();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await _addMissingSeedCategories();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seedCategories() async {
    await batch((b) {
      for (final (i, c) in defaultCategories.indexed) {
        b.insert(
          categories,
          CategoriesCompanion.insert(
            name: c.name,
            icon: c.icon,
            color: c.color,
            isIncome: Value(c.isIncome),
            sortOrder: Value(i),
          ),
        );
      }
    });
  }

  /// Inserts seed categories added in later versions, matched by name.
  Future<void> _addMissingSeedCategories() async {
    final existing = {for (final c in await select(categories).get()) c.name};
    for (final (i, c) in defaultCategories.indexed) {
      if (existing.contains(c.name)) continue;
      await into(categories).insert(
        CategoriesCompanion.insert(
          name: c.name,
          icon: c.icon,
          color: c.color,
          isIncome: Value(c.isIncome),
          sortOrder: Value(i),
        ),
      );
    }
  }

  // ---------------------------------------------------------------- reads

  Stream<List<Category>> watchCategories() =>
      (select(categories)..orderBy([(c) => OrderingTerm(expression: c.sortOrder)])).watch();

  Future<List<Category>> allCategories() => select(categories).get();

  Stream<List<Account>> watchAccounts() => (select(accounts)..where((a) => a.archived.equals(false))).watch();

  Future<List<Account>> allAccounts() => select(accounts).get();

  /// Transactions in [from, to), newest first, joined with category/account.
  Stream<List<TxnView>> watchTxns({DateTime? from, DateTime? to, int? limit}) {
    final q = select(transactions).join([
      leftOuterJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(accounts, accounts.id.equalsExp(transactions.accountId)),
    ]);
    if (from != null) q.where(transactions.occurredAt.isBiggerOrEqualValue(from));
    if (to != null) q.where(transactions.occurredAt.isSmallerThanValue(to));
    q.orderBy([OrderingTerm.desc(transactions.occurredAt), OrderingTerm.desc(transactions.id)]);
    if (limit != null) q.limit(limit);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          TxnView(r.readTable(transactions), r.readTableOrNull(categories), r.readTableOrNull(accounts)),
      ],
    );
  }

  Stream<TxnView?> watchTxn(int id) {
    final q = select(transactions).join([
      leftOuterJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      leftOuterJoin(accounts, accounts.id.equalsExp(transactions.accountId)),
    ])..where(transactions.id.equals(id));
    return q.watchSingleOrNull().map(
      (r) => r == null
          ? null
          : TxnView(r.readTable(transactions), r.readTableOrNull(categories), r.readTableOrNull(accounts)),
    );
  }

  Stream<List<RawMessage>> watchSourcesFor(int txnId) =>
      (select(rawMessages)..where((m) => m.transactionId.equals(txnId))).watch();

  Stream<int> watchReviewCount() {
    final c = transactions.id.count();
    final q = selectOnly(transactions)
      ..addColumns([c])
      ..where(transactions.status.equalsValue(TxnStatus.needsReview));
    return q.watchSingle().map((r) => r.read(c) ?? 0);
  }

  Stream<Map<ParseStatus, int>> watchParseStats(SourceKind source) {
    final c = rawMessages.id.count();
    final q = selectOnly(rawMessages)
      ..addColumns([rawMessages.parseStatus, c])
      ..where(rawMessages.source.equalsValue(source))
      ..groupBy([rawMessages.parseStatus]);
    return q.watch().map(
      (rows) => {for (final r in rows) ParseStatus.values[r.read(rawMessages.parseStatus)!]: r.read(c) ?? 0},
    );
  }

  Stream<List<RawMessage>> watchRawMessages(SourceKind source, Set<ParseStatus> statuses) =>
      (select(rawMessages)
            ..where((m) => m.source.equalsValue(source) & m.parseStatus.isIn(statuses.map((s) => s.index)))
            ..orderBy([(m) => OrderingTerm.desc(m.receivedAt)])
            ..limit(300))
          .watch();

  Future<Set<String>> knownExternalIds(SourceKind source) async {
    final q = selectOnly(rawMessages)
      ..addColumns([rawMessages.externalId])
      ..where(rawMessages.source.equalsValue(source));
    return {for (final r in await q.get()) r.read(rawMessages.externalId)!};
  }

  /// Candidate duplicates: same amount + direction within ±[window].
  Future<List<Transaction>> candidatesFor({
    required int amountMinor,
    required TxnDirection direction,
    required DateTime at,
    Duration window = const Duration(hours: 48),
  }) =>
      (select(transactions)..where(
            (t) =>
                t.amountMinor.equals(amountMinor) &
                t.direction.equalsValue(direction) &
                t.occurredAt.isBetweenValues(at.subtract(window), at.add(window)),
          ))
          .get();

  Future<List<RawMessage>> sourcesOf(int txnId) =>
      (select(rawMessages)..where((m) => m.transactionId.equals(txnId))).get();

  Future<List<MerchantRule>> allMerchantRules() => select(merchantRules).get();

  // ---------------------------------------------------------------- writes

  Future<void> setCategory(int txnId, int? categoryId, {String? learnPattern}) => transaction(() async {
    await (update(transactions)..where((t) => t.id.equals(txnId))).write(
      TransactionsCompanion(categoryId: Value(categoryId), categoryLocked: const Value(true)),
    );
    if (learnPattern != null && learnPattern.isNotEmpty && categoryId != null) {
      await into(merchantRules).insert(
        MerchantRulesCompanion.insert(pattern: learnPattern, categoryId: categoryId),
        onConflict: DoUpdate(
          (_) => MerchantRulesCompanion(categoryId: Value(categoryId)),
          target: [merchantRules.pattern],
        ),
      );
      // Apply to other uncategorised/unlocked transactions with the same merchant.
      await (update(transactions)
            ..where((t) => t.merchant.lower().equals(learnPattern) & t.categoryLocked.equals(false)))
          .write(TransactionsCompanion(categoryId: Value(categoryId)));
    }
  });

  Future<void> deleteTxn(int id) => transaction(() async {
    await (update(rawMessages)..where((m) => m.transactionId.equals(id))).write(
      const RawMessagesCompanion(
        transactionId: Value(null),
        parseStatus: Value(ParseStatus.ignored),
        ignoreReason: Value('Deleted by user'),
      ),
    );
    await (delete(transactions)..where((t) => t.id.equals(id))).go();
  });

  /// User confirmed [fromId] is the same payment as [intoId].
  Future<void> mergeInto(int fromId, int intoId) => transaction(() async {
    await (update(rawMessages)..where((m) => m.transactionId.equals(fromId))).write(
      RawMessagesCompanion(transactionId: Value(intoId), parseStatus: const Value(ParseStatus.merged)),
    );
    await (delete(transactions)..where((t) => t.id.equals(fromId))).go();
    await (update(
      transactions,
    )..where((t) => t.id.equals(intoId))).write(const TransactionsCompanion(status: Value(TxnStatus.confirmed)));
  });

  Future<void> confirm(int id) => (update(transactions)..where((t) => t.id.equals(id))).write(
    const TransactionsCompanion(status: Value(TxnStatus.confirmed), duplicateOfId: Value(null)),
  );

  Future<void> setTransfer(int id, bool value) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(TransactionsCompanion(isTransfer: Value(value)));

  Future<void> setNote(int id, String? note) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(TransactionsCompanion(note: Value(note)));

  Future<int> addManual({
    required int amountMinor,
    required TxnDirection direction,
    required DateTime at,
    String? merchant,
    int? categoryId,
    int? accountId,
    String? note,
  }) => transaction(() async {
    final id = await into(transactions).insert(
      TransactionsCompanion.insert(
        amountMinor: amountMinor,
        direction: direction,
        occurredAt: at,
        merchant: Value(merchant),
        categoryId: Value(categoryId),
        accountId: Value(accountId),
        note: Value(note),
        mode: PaymentMode.cash,
        status: TxnStatus.confirmed,
        categoryLocked: const Value(true),
      ),
    );
    await into(rawMessages).insert(
      RawMessagesCompanion.insert(
        source: SourceKind.manual,
        externalId: 'manual-$id',
        sender: 'You',
        body: 'Added manually',
        receivedAt: DateTime.now(),
        parseStatus: ParseStatus.parsed,
        transactionId: Value(id),
      ),
    );
    return id;
  });

  /// Drops everything that came from [source] so it can be re-parsed.
  /// Transactions also backed by another source (manual, email) survive.
  Future<void> resetSource(SourceKind source) => transaction(() async {
    await (delete(rawMessages)..where((m) => m.source.equalsValue(source))).go();
    await customStatement(
      'DELETE FROM transactions WHERE id NOT IN '
      '(SELECT transaction_id FROM raw_messages WHERE transaction_id IS NOT NULL)',
    );
  });

  /// Wipes all imported data (keeps categories, accounts and learned rules).
  Future<void> resetImported() => transaction(() async {
    await delete(rawMessages).go();
    await delete(transactions).go();
  });
}
