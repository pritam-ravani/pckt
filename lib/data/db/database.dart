import 'package:drift/drift.dart';

import '../../core/currency.dart';
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

extension TxnMoney on Transaction {
  /// Amount in minor units of [home]: the amount itself for a [home]
  /// transaction, the recorded conversion for a foreign one, or null when
  /// there is none (it is then left out of totals rather than guessed).
  int? amountIn(String home) => currency == home
      ? amountMinor
      : convertedCurrency == home
      ? convertedMinor
      : null;

  /// [amountIn] the current home currency.
  int? get homeMinor => amountIn(Currencies.home);

  bool get isForeign => currency != Currencies.home;
}

/// A payslip with its lines and the bank credit it was matched to.
class PayslipView {
  const PayslipView(this.payslip, this.lines, this.salaryTxn);
  final Payslip payslip;
  final List<PayslipLine> lines;
  final Transaction? salaryTxn;

  int _sum(PayslipLineKind kind) => lines.where((l) => l.kind == kind).fold(0, (s, l) => s + l.amountMinor);

  int get grossMinor => _sum(PayslipLineKind.earning);
  int get deductionsMinor => _sum(PayslipLineKind.deduction);
  int get employerMinor => _sum(PayslipLineKind.employerContribution);
  int get netMinor => grossMinor - deductionsMinor;

  /// Total of the lines with this standard [code].
  int minorOf(String code) => lines.where((l) => l.code == code).fold(0, (s, l) => s + l.amountMinor);
}

/// A payslip line being saved.
class PayslipLineDraft {
  const PayslipLineDraft({required this.kind, required this.label, required this.amountMinor, this.code = ''});
  final PayslipLineKind kind;
  final String code;
  final String label;
  final int amountMinor;
}

class DuplicatePayslipException implements Exception {
  const DuplicatePayslipException();
}

@DriftDatabase(
  tables: [Accounts, Categories, Transactions, RawMessages, MerchantRules, Budgets, Payslips, PayslipLines],
)
class AppDatabase extends _$AppDatabase {
  /// Without an [executor], opens the SQLCipher-encrypted `pckt.sqlite`
  /// (migrating a plaintext one first) — see [openAppDatabase].
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openAppDatabase());

  /// Seed categories every transaction can fall back to; never deletable.
  static const protectedCategories = {'Transfers', 'Other'};

  @override
  int get schemaVersion => 5;

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
      // v4: currencies. Everything recorded so far was in rupees, which is
      // the columns' default. (A pre-v3 database got the budgets table in
      // its current shape above, hence the existence check.)
      if (from < 4) {
        await _addColumnIfMissing(m, transactions, transactions.currency);
        await _addColumnIfMissing(m, transactions, transactions.convertedMinor);
        await _addColumnIfMissing(m, transactions, transactions.convertedCurrency);
        await _addColumnIfMissing(m, accounts, accounts.currency);
        await _addColumnIfMissing(m, budgets, budgets.currency);
      }
      if (from < 5) {
        await m.createTable(payslips);
        await m.createTable(payslipLines);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _addColumnIfMissing(Migrator m, TableInfo table, GeneratedColumn column) async {
    final cols = await customSelect('PRAGMA table_info("${table.actualTableName}")').get();
    if (cols.any((c) => c.read<String>('name') == column.name)) return;
    await m.addColumn(table, column);
  }

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

  /// Candidate duplicates: same amount, currency and direction within
  /// ±[window]. A transaction recorded in two currencies ("USD 12.50
  /// (INR 1,045.30)") also matches on its converted amount, both ways, so
  /// a rupee-only alert for the same card spend still finds it. [also] is
  /// the new payment's own converted amount, if any.
  Future<List<Transaction>> candidatesFor({
    required int amountMinor,
    String currency = 'INR',
    required TxnDirection direction,
    required DateTime at,
    Duration window = const Duration(hours: 48),
    (int, String)? also,
  }) =>
      (select(transactions)..where((t) {
            var amount =
                (t.amountMinor.equals(amountMinor) & t.currency.equals(currency)) |
                (t.convertedMinor.equals(amountMinor) & t.convertedCurrency.equals(currency));
            if (also != null) amount = amount | (t.amountMinor.equals(also.$1) & t.currency.equals(also.$2));
            return amount &
                t.direction.equalsValue(direction) &
                t.occurredAt.isBetweenValues(at.subtract(window), at.add(window));
          }))
          .get();

  /// Latest non-transfer transactions with a merchant name, newest first.
  Future<List<Transaction>> recentWithMerchant(TxnDirection direction, {int limit = 300}) =>
      (select(transactions)
            ..where((t) => t.direction.equalsValue(direction) & t.isTransfer.equals(false) & t.merchant.isNotNull())
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt), (t) => OrderingTerm.desc(t.id)])
            ..limit(limit))
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
    await (update(payslips)..where((p) => p.salaryTxnId.equals(fromId))).write(
      PayslipsCompanion(salaryTxnId: Value(intoId)),
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

  /// [currency] defaults to the home currency; [convertedMinor] is the
  /// home-currency amount of a foreign one.
  Future<int> addManual({
    required int amountMinor,
    String? currency,
    int? convertedMinor,
    required TxnDirection direction,
    required DateTime at,
    String? merchant,
    int? categoryId,
    int? accountId,
    String? note,
    PaymentMode mode = PaymentMode.cash,
  }) => transaction(() async {
    final id = await into(transactions).insert(
      TransactionsCompanion.insert(
        amountMinor: amountMinor,
        currency: Value(currency ?? Currencies.home),
        convertedMinor: Value(convertedMinor),
        convertedCurrency: Value(convertedMinor == null ? null : Currencies.home),
        direction: direction,
        occurredAt: at,
        merchant: Value(merchant),
        categoryId: Value(categoryId),
        accountId: Value(accountId),
        note: Value(note),
        mode: mode,
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
    Value<String> currency = const Value.absent(),
    Value<int?> convertedMinor = const Value.absent(),
    Value<String?> convertedCurrency = const Value.absent(),
    required TxnDirection direction,
    required DateTime occurredAt,
    required String? merchant,
    required int? accountId,
    required String? note,
    Value<int?> categoryId = const Value.absent(),
  }) => (update(transactions)..where((t) => t.id.equals(id))).write(
    TransactionsCompanion(
      amountMinor: Value(amountMinor),
      currency: currency,
      convertedMinor: convertedMinor,
      convertedCurrency: convertedCurrency,
      direction: Value(direction),
      occurredAt: Value(occurredAt),
      merchant: Value(merchant),
      accountId: Value(accountId),
      note: Value(note),
      categoryId: categoryId,
    ),
  );

  /// Records what a foreign transaction came to in [currency] (normally
  /// the home currency), or clears it with a null [minor].
  Future<void> setConversion(int id, {required int? minor, required String currency}) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(convertedMinor: Value(minor), convertedCurrency: Value(minor == null ? null : currency)),
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

  /// Creates or replaces the monthly budget for [categoryId] (null = overall),
  /// in [currency] (the home currency by default).
  Future<void> setBudget({int? categoryId, required int amountMinor, bool active = true, String? currency}) =>
      transaction(() async {
        final code = currency ?? Currencies.home;
        final existing = await (select(
          budgets,
        )..where((b) => categoryId == null ? b.categoryId.isNull() : b.categoryId.equals(categoryId))).get();
        if (existing.isEmpty) {
          await into(budgets).insert(
            BudgetsCompanion.insert(
              categoryId: Value(categoryId),
              amountMinor: amountMinor,
              active: Value(active),
              currency: Value(code),
            ),
          );
          return;
        }
        await (update(budgets)..where((b) => b.id.equals(existing.first.id))).write(
          BudgetsCompanion(amountMinor: Value(amountMinor), active: Value(active), currency: Value(code)),
        );
        for (final dup in existing.skip(1)) {
          await (delete(budgets)..where((b) => b.id.equals(dup.id))).go();
        }
      });

  Future<void> setBudgetActive(int id, bool active) =>
      (update(budgets)..where((b) => b.id.equals(id))).write(BudgetsCompanion(active: Value(active)));

  Future<void> deleteBudget(int id) => (delete(budgets)..where((b) => b.id.equals(id))).go();

  // ---------------------------------------------------------- payslips

  JoinedSelectStatement<HasResultSet, dynamic> _payslipQuery() =>
      select(payslips).join([
          leftOuterJoin(payslipLines, payslipLines.payslipId.equalsExp(payslips.id)),
          leftOuterJoin(transactions, transactions.id.equalsExp(payslips.salaryTxnId)),
        ])
        ..orderBy([
          OrderingTerm.desc(payslips.month),
          OrderingTerm.asc(payslips.id),
          OrderingTerm.asc(payslipLines.sortOrder),
          OrderingTerm.asc(payslipLines.id),
        ]);

  List<PayslipView> _payslipViews(List<TypedResult> rows) {
    final slips = <int, Payslip>{};
    final lines = <int, List<PayslipLine>>{};
    final txns = <int, Transaction?>{};
    for (final r in rows) {
      final p = r.readTable(payslips);
      slips[p.id] = p;
      txns[p.id] = r.readTableOrNull(transactions);
      final line = r.readTableOrNull(payslipLines);
      (lines[p.id] ??= []).addAll([?line]);
    }
    return [for (final e in slips.entries) PayslipView(e.value, lines[e.key]!, txns[e.key])];
  }

  /// Newest month first.
  Stream<List<PayslipView>> watchPayslips() => _payslipQuery().watch().map(_payslipViews);

  Future<List<PayslipView>> allPayslips() => _payslipQuery().get().then(_payslipViews);

  /// Creates a payslip, or replaces [id]'s details and lines. A link to a
  /// bank credit survives unless the net pay changed. Throws
  /// [DuplicatePayslipException] if that month and employer already exist.
  Future<int> savePayslip({
    int? id,
    required DateTime month,
    String employer = '',
    DateTime? payDate,
    String currency = 'INR',
    String? note,
    required List<PayslipLineDraft> lines,
  }) => transaction(() async {
    final first = DateTime(month.year, month.month);
    final name = employer.trim();
    final same =
        await (select(payslips)
              ..where((p) => p.month.equals(first) & p.employer.equals(name) & (id == null ? const Constant(true) : p.id.equals(id).not())))
            .get();
    if (same.isNotEmpty) throw const DuplicatePayslipException();

    final net = _net(lines.map((l) => (l.kind, l.amountMinor)));
    final int slipId;
    if (id == null) {
      slipId = await into(payslips).insert(
        PayslipsCompanion.insert(
          month: first,
          employer: Value(name),
          payDate: Value(payDate),
          currency: Value(currency),
          note: Value(note),
        ),
      );
    } else {
      slipId = id;
      final old = await (select(payslipLines)..where((l) => l.payslipId.equals(id))).get();
      final netChanged = _net(old.map((l) => (l.kind, l.amountMinor))) != net;
      await (update(payslips)..where((p) => p.id.equals(id))).write(
        PayslipsCompanion(
          month: Value(first),
          employer: Value(name),
          payDate: Value(payDate),
          currency: Value(currency),
          note: Value(note),
          salaryTxnId: netChanged ? const Value(null) : const Value.absent(),
          autoMatch: netChanged ? const Value(true) : const Value.absent(),
        ),
      );
      await (delete(payslipLines)..where((l) => l.payslipId.equals(id))).go();
    }
    for (final (i, l) in lines.indexed) {
      await into(payslipLines).insert(
        PayslipLinesCompanion.insert(
          payslipId: slipId,
          kind: l.kind,
          code: Value(l.code),
          label: l.label,
          amountMinor: l.amountMinor,
          sortOrder: Value(i),
        ),
      );
    }
    return slipId;
  });

  static int _net(Iterable<(PayslipLineKind, int)> lines) => lines.fold(
    0,
    (s, l) => switch (l.$1) {
      PayslipLineKind.earning => s + l.$2,
      PayslipLineKind.deduction => s - l.$2,
      PayslipLineKind.employerContribution => s,
    },
  );

  Future<void> deletePayslip(int id) => (delete(payslips)..where((p) => p.id.equals(id))).go();

  /// Credits that could be [month]'s salary, which is usually paid late in
  /// the month or early in the next. Excludes credits another payslip has.
  Future<List<Transaction>> salaryCredits({required DateTime month, required String currency, int? amountMinor}) async {
    final taken = {for (final v in await allPayslips()) ?v.payslip.salaryTxnId};
    final rows =
        await (select(transactions)
              ..where(
                (t) =>
                    t.direction.equalsValue(TxnDirection.credit) &
                    t.isTransfer.equals(false) &
                    t.currency.equals(currency) &
                    t.occurredAt.isBiggerOrEqualValue(DateTime(month.year, month.month)) &
                    t.occurredAt.isSmallerThanValue(DateTime(month.year, month.month + 1, 11)) &
                    (amountMinor == null ? const Constant(true) : t.amountMinor.equals(amountMinor)),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
            .get();
    return rows.where((t) => !taken.contains(t.id)).toList();
  }

  /// Links [txnId] as the payment of [payslipId] and files it under Salary,
  /// unless the user chose that transaction's category themselves.
  Future<void> linkSalary(int payslipId, int txnId) => transaction(() async {
    await (update(payslips)..where((p) => p.id.equals(payslipId))).write(
      PayslipsCompanion(salaryTxnId: Value(txnId), autoMatch: const Value(true)),
    );
    final salary = (await allCategories()).where((c) => (c.seedName ?? c.name) == 'Salary').firstOrNull;
    if (salary == null) return;
    await (update(transactions)..where((t) => t.id.equals(txnId) & t.categoryLocked.equals(false))).write(
      TransactionsCompanion(categoryId: Value(salary.id)),
    );
  });

  /// The user says this isn't the right credit: stop matching automatically.
  Future<void> unlinkSalary(int payslipId) => (update(payslips)..where((p) => p.id.equals(payslipId))).write(
    const PayslipsCompanion(salaryTxnId: Value(null), autoMatch: Value(false)),
  );

  /// Links each unmatched payslip to a credit of exactly its net pay, the
  /// one closest to its pay date. Returns how many were linked.
  Future<int> autoLinkPayslips() => transaction(() async {
    var linked = 0;
    for (final v in await allPayslips()) {
      if (v.payslip.salaryTxnId != null || !v.payslip.autoMatch || v.netMinor <= 0) continue;
      final month = v.payslip.month;
      final credits = await salaryCredits(month: month, currency: v.payslip.currency, amountMinor: v.netMinor);
      if (credits.isEmpty) continue;
      final target = v.payslip.payDate ?? DateTime(month.year, month.month + 1, 0);
      credits.sort((a, b) => a.occurredAt.difference(target).abs().compareTo(b.occurredAt.difference(target).abs()));
      await linkSalary(v.payslip.id, credits.first.id);
      linked++;
    }
    return linked;
  });

  // ---------------------------------------------------------- accounts

  /// [currency] defaults to the home currency.
  Future<int> addAccount({required String name, required AccountKind kind, required int color, String? currency}) =>
      into(accounts).insert(
        AccountsCompanion.insert(name: name, kind: kind, color: color, currency: Value(currency ?? Currencies.home)),
      );

  Future<void> updateAccount(int id, {String? name, AccountKind? kind, int? color, bool? archived, String? currency}) =>
      (update(accounts)..where((a) => a.id.equals(id))).write(
        AccountsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          kind: kind == null ? const Value.absent() : Value(kind),
          color: color == null ? const Value.absent() : Value(color),
          archived: archived == null ? const Value.absent() : Value(archived),
          currency: currency == null ? const Value.absent() : Value(currency),
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
