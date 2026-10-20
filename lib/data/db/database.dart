import 'package:drift/drift.dart';

import '../seed/default_categories.dart';
import 'db_encryption.dart';
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

@DriftDatabase(tables: [Accounts, Categories, Transactions, RawMessages, MerchantRules, Budgets])
class AppDatabase extends _$AppDatabase {
  /// Without an [executor], opens the SQLCipher-encrypted `pckt.sqlite`
  /// (migrating a plaintext one first) — see [openAppDatabase].
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openAppDatabase());

  /// Seed categories every transaction can fall back to; never deletable.
  static const protectedCategories = {'Transfers', 'Other'};

  @override
  int get schemaVersion => 3;

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
      // v3 first: later steps read categories with the new column.
      if (from < 3) {
        await m.addColumn(categories, categories.seedName);
        await m.createTable(budgets);
        for (final c in defaultCategories) {
          await (update(categories)..where((r) => r.name.equals(c.name) & r.seedName.isNull())).write(
            CategoriesCompanion(seedName: Value(c.name)),
          );
        }
      }
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
            seedName: Value(c.name),
          ),
        );
      }
    });
  }

  /// Inserts seed categories added in later versions, matched by name.
  Future<void> _addMissingSeedCategories() async {
    final existing = {
      for (final c in await select(categories).get()) ...[c.name, ?c.seedName],
    };
    for (final (i, c) in defaultCategories.indexed) {
      if (existing.contains(c.name)) continue;
      await into(categories).insert(
        CategoriesCompanion.insert(
          name: c.name,
          icon: c.icon,
          color: c.color,
          isIncome: Value(c.isIncome),
          sortOrder: Value(i),
          seedName: Value(c.name),
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

  /// Every account including archived ones, for the management screen.
  Stream<List<Account>> watchAllAccounts() => (select(
    accounts,
  )..orderBy([(a) => OrderingTerm(expression: a.archived), (a) => OrderingTerm(expression: a.name)])).watch();

  Stream<List<Budget>> watchBudgets() => select(budgets).watch();

  Future<List<Budget>> allBudgets() => select(budgets).get();

  /// Transaction count per category id (null = uncategorised).
  Future<int> countTxnsInCategory(int categoryId) async {
    final c = transactions.id.count();
    final q = selectOnly(transactions)
      ..addColumns([c])
      ..where(transactions.categoryId.equals(categoryId));
    return (await q.getSingle()).read(c) ?? 0;
  }

  Future<int> countTxnsWithMerchant(String merchant) async {
    final c = transactions.id.count();
    final q = selectOnly(transactions)
      ..addColumns([c])
      ..where(transactions.merchant.lower().equals(merchant.toLowerCase()));
    return (await q.getSingle()).read(c) ?? 0;
  }

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

  // ------------------------------------------------------------- editing

  /// Edits the user-facing fields of a transaction. Source evidence
  /// (raw messages, reference, counterparty) is left untouched.
  Future<void> updateTxn(
    int id, {
    required int amountMinor,
    required TxnDirection direction,
    required DateTime occurredAt,
    required String? merchant,
    required int? accountId,
    required String? note,
    Value<int?> categoryId = const Value.absent(),
  }) => (update(transactions)..where((t) => t.id.equals(id))).write(
    TransactionsCompanion(
      amountMinor: Value(amountMinor),
      direction: Value(direction),
      occurredAt: Value(occurredAt),
      merchant: Value(merchant),
      accountId: Value(accountId),
      note: Value(note),
      categoryId: categoryId,
    ),
  );

  /// Renames every transaction from merchant [from] (case-insensitive) to
  /// [to] and carries the learned category rule over, so future messages
  /// that still read [from] keep their category and [to] learns it too.
  /// Returns how many transactions were renamed.
  Future<int> renameMerchant(String from, String to) => transaction(() async {
    final oldKey = from.trim().toLowerCase();
    final newKey = to.trim().toLowerCase();
    if (oldKey.isEmpty || newKey.isEmpty) return 0;
    final n = await (update(
      transactions,
    )..where((t) => t.merchant.lower().equals(oldKey))).write(TransactionsCompanion(merchant: Value(to.trim())));
    if (oldKey == newKey) return n;
    final rules = {for (final r in await allMerchantRules()) r.pattern: r.categoryId};
    final oldRule = rules[oldKey];
    if (oldRule != null && !rules.containsKey(newKey)) {
      await into(merchantRules).insert(MerchantRulesCompanion.insert(pattern: newKey, categoryId: oldRule));
    }
    // Renamed onto a merchant the user already taught: follow that rule.
    final target = rules[newKey];
    if (target != null) {
      await (update(transactions)..where((t) => t.merchant.lower().equals(newKey) & t.categoryLocked.equals(false)))
          .write(TransactionsCompanion(categoryId: Value(target)));
    }
    return n;
  });

  // ----------------------------------------------------------- budgets

  /// Creates or replaces the monthly budget for [categoryId] (null = overall).
  Future<void> setBudget({int? categoryId, required int amountMinor, bool active = true}) => transaction(() async {
    final existing = await (select(
      budgets,
    )..where((b) => categoryId == null ? b.categoryId.isNull() : b.categoryId.equals(categoryId))).get();
    if (existing.isEmpty) {
      await into(
        budgets,
      ).insert(BudgetsCompanion.insert(categoryId: Value(categoryId), amountMinor: amountMinor, active: Value(active)));
      return;
    }
    await (update(budgets)..where((b) => b.id.equals(existing.first.id))).write(
      BudgetsCompanion(amountMinor: Value(amountMinor), active: Value(active)),
    );
    for (final dup in existing.skip(1)) {
      await (delete(budgets)..where((b) => b.id.equals(dup.id))).go();
    }
  });

  Future<void> setBudgetActive(int id, bool active) =>
      (update(budgets)..where((b) => b.id.equals(id))).write(BudgetsCompanion(active: Value(active)));

  Future<void> deleteBudget(int id) => (delete(budgets)..where((b) => b.id.equals(id))).go();

  // ---------------------------------------------------------- accounts

  Future<int> addAccount({required String name, required AccountKind kind, required int color}) =>
      into(accounts).insert(AccountsCompanion.insert(name: name, kind: kind, color: color));

  Future<void> updateAccount(int id, {String? name, AccountKind? kind, int? color, bool? archived}) =>
      (update(accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          kind: kind == null ? const Value.absent() : Value(kind),
          color: color == null ? const Value.absent() : Value(color),
          archived: archived == null ? const Value.absent() : Value(archived),
        ),
      );

  // -------------------------------------------------------- categories

  static bool isProtected(Category c) => protectedCategories.contains(c.seedName ?? c.name);

  Future<int> addCategory({required String name, required String icon, required int color, bool isIncome = false}) =>
      transaction(() async {
        final maxOrder = categories.sortOrder.max();
        final row = await (selectOnly(categories)..addColumns([maxOrder])).getSingle();
        return into(categories).insert(
          CategoriesCompanion.insert(
            name: name,
            icon: icon,
            color: color,
            isIncome: Value(isIncome),
            sortOrder: Value((row.read(maxOrder) ?? -1) + 1),
          ),
        );
      });

  Future<void> updateCategory(int id, {String? name, String? icon, int? color, bool? isIncome}) =>
      (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          name: name == null ? const Value.absent() : Value(name),
          icon: icon == null ? const Value.absent() : Value(icon),
          color: color == null ? const Value.absent() : Value(color),
          isIncome: isIncome == null ? const Value.absent() : Value(isIncome),
        ),
      );

  /// Persists a new display order; [ids] is the full ordered list.
  Future<void> reorderCategories(List<int> ids) => batch((b) {
    for (final (i, id) in ids.indexed) {
      b.update(categories, CategoriesCompanion(sortOrder: Value(i)), where: (c) => c.id.equals(id));
    }
  });

  /// Deletes category [id], moving its transactions and learned merchant
  /// rules to [moveTo] first so nothing is orphaned. Its budget goes too.
  /// Transfers and Other can't be deleted.
  Future<void> deleteCategory(int id, {required int moveTo}) => transaction(() async {
    if (id == moveTo) throw ArgumentError('Pick a different category to move transactions to');
    final cat = await (select(categories)..where((c) => c.id.equals(id))).getSingle();
    await (select(categories)..where((c) => c.id.equals(moveTo))).getSingle(); // must exist
    if (isProtected(cat)) throw StateError('${cat.name} can\'t be deleted');
    await (update(
      transactions,
    )..where((t) => t.categoryId.equals(id))).write(TransactionsCompanion(categoryId: Value(moveTo)));
    await (update(
      merchantRules,
    )..where((r) => r.categoryId.equals(id))).write(MerchantRulesCompanion(categoryId: Value(moveTo)));
    await (delete(budgets)..where((b) => b.categoryId.equals(id))).go();
    await (delete(categories)..where((c) => c.id.equals(id))).go();
  });

  /// Wipes all imported data (keeps categories, accounts and learned rules).
  Future<void> resetImported() => transaction(() async {
    await delete(rawMessages).go();
    await delete(transactions).go();
  });
}
