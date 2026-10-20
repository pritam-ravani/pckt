import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../data/db/database.dart';
import '../../features/recurring/recurring_detector.dart';
import '../llm_client.dart';
import '../llm_json.dart';

export '../../features/recurring/recurring_detector.dart' show RecurringPayment, detectRecurring;

/// Result of running one tool: JSON for the model + a one-line summary
/// for the activity chip in the chat UI.
class ToolOutcome {
  const ToolOutcome(this.json, this.summary, {this.isError = false});
  final Map<String, dynamic> json;
  final String summary;
  final bool isError;

  String get content => jsonEncode(json);
}

/// A change the model wants to make; the UI must confirm it first.
class RecategorizeProposal {
  const RecategorizeProposal({required this.txns, required this.category, this.learnMerchants = const []});
  final List<Transaction> txns;
  final Category category;

  /// Exact merchant names to remember as rules (when matched by merchant).
  final List<String> learnMerchants;

  int get total => txns.fold(0, (s, t) => s + t.amountMinor);

  String get description {
    final names = txns.map((t) => t.merchant ?? t.counterparty ?? 'Unknown').toSet().take(3).join(', ');
    return 'Move ${txns.length} transaction${txns.length == 1 ? '' : 's'} ($names) to ${category.name}';
  }
}

typedef ConfirmRecategorize = Future<bool> Function(RecategorizeProposal proposal);

/// Read-mostly tools over the local database. Results carry structured
/// fields only — never raw SMS/email bodies.
class FinanceTools {
  FinanceTools(this.db, {DateTime Function()? now}) : now = now ?? DateTime.now;

  final AppDatabase db;
  final DateTime Function() now;

  static final _day = DateFormat('yyyy-MM-dd');
  static const _maxRows = 100;

  static const _dateRange = {
    'from': {'type': 'string', 'description': 'Start date YYYY-MM-DD (inclusive). Defaults to 30 days ago.'},
    'to': {'type': 'string', 'description': 'End date YYYY-MM-DD (inclusive). Defaults to today.'},
  };

  List<LlmTool> get specs => const [
    LlmTool(
      name: 'query_transactions',
      description:
          'Search transactions. Returns matching rows (newest first unless sort=amount) plus totals over ALL matches. '
          'Amounts are in rupees.',
      parameters: {
        'type': 'object',
        'properties': {
          ..._dateRange,
          'category': {'type': 'string', 'description': 'Exact category name (see list_categories).'},
          'text': {'type': 'string', 'description': 'Case-insensitive substring of merchant or counterparty/VPA.'},
          'direction': {
            'type': 'string',
            'enum': ['debit', 'credit'],
          },
          'min_amount': {'type': 'number'},
          'max_amount': {'type': 'number'},
          'include_transfers': {
            'type': 'boolean',
            'description': 'Include transfers between own accounts. Default false.',
          },
          'sort': {
            'type': 'string',
            'enum': ['date', 'amount'],
          },
          'limit': {'type': 'integer', 'description': 'Rows to return, max 100. Default 25.'},
        },
      },
    ),
    LlmTool(
      name: 'spending_summary',
      description:
          'Totals grouped by category, merchant, month, day or account over a date range. Transfers are excluded. '
          'Use this for "where did my money go", comparisons and trends.',
      parameters: {
        'type': 'object',
        'properties': {
          ..._dateRange,
          'group_by': {
            'type': 'string',
            'enum': ['category', 'merchant', 'month', 'day', 'account'],
          },
          'direction': {
            'type': 'string',
            'enum': ['debit', 'credit'],
            'description': 'debit = spending (default), credit = income.',
          },
        },
        'required': ['group_by'],
      },
    ),
    LlmTool(
      name: 'list_categories',
      description: 'All category names, marking which are income categories.',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
    ),
    LlmTool(
      name: 'list_accounts',
      description: 'Bank accounts, cards and wallets detected from messages.',
      parameters: {'type': 'object', 'properties': <String, dynamic>{}},
    ),
    LlmTool(
      name: 'find_recurring',
      description:
          'Detects subscriptions and recurring payments: same merchant with a similar amount at a weekly, '
          'monthly or quarterly cadence.',
      parameters: {
        'type': 'object',
        'properties': {
          'months': {'type': 'integer', 'description': 'How many months of history to scan. Default 6.'},
        },
      },
    ),
    LlmTool(
      name: 'recategorize',
      description:
          'Change the category of transactions, by ids or by merchant. The user is asked to confirm in the app '
          'before anything changes; the result says whether they approved.',
      parameters: {
        'type': 'object',
        'properties': {
          'transaction_ids': {
            'type': 'array',
            'items': {'type': 'integer'},
          },
          'merchant': {
            'type': 'string',
            'description': 'Apply to all transactions whose merchant contains this text, and remember it.',
          },
          'category': {'type': 'string', 'description': 'Exact category name.'},
        },
        'required': ['category'],
      },
    ),
  ];

  Future<ToolOutcome> execute(ToolCall call, {ConfirmRecategorize? confirm}) async {
    try {
      final a = call.arguments;
      return switch (call.name) {
        'query_transactions' => await queryTransactions(a),
        'spending_summary' => await spendingSummary(a),
        'list_categories' => await listCategories(),
        'list_accounts' => await listAccounts(),
        'find_recurring' => await findRecurring(a),
        'recategorize' => await recategorize(a, confirm),
        _ => ToolOutcome({'error': 'Unknown tool ${call.name}'}, 'Unknown tool', isError: true),
      };
    } on _BadArgs catch (e) {
      return ToolOutcome({'error': e.message}, 'Invalid request', isError: true);
    }
  }

  // ------------------------------------------------------------------ helpers

  (DateTime, DateTime) _range(Map<String, dynamic> a, {int defaultDays = 30}) {
    final today = DateTime(now().year, now().month, now().day);
    DateTime? parse(Object? v) {
      final s = asString(v);
      if (s == null) return null;
      final d = DateTime.tryParse(s);
      if (d == null) throw _BadArgs('Bad date "$s", use YYYY-MM-DD');
      return DateTime(d.year, d.month, d.day);
    }

    final from = parse(a['from']) ?? today.subtract(Duration(days: defaultDays));
    final to = (parse(a['to']) ?? today).add(const Duration(days: 1)); // exclusive
    if (!to.isAfter(from)) throw _BadArgs('"to" must be on or after "from"');
    return (from, to);
  }

  Future<List<TxnView>> _txns(DateTime from, DateTime to) => db.watchTxns(from: from, to: to).first;

  static double _rupees(int minor) => minor / 100;

  Map<String, dynamic> _row(TxnView v) {
    final t = v.txn;
    return {
      'id': t.id,
      'date': _day.format(t.occurredAt),
      'amount': _rupees(t.amountMinor),
      'direction': t.direction.name,
      'merchant': ?t.merchant,
      'counterparty': ?t.counterparty,
      'category': v.category?.name ?? 'Uncategorised',
      if (v.account != null) 'account': '${v.account!.name} ••${v.account!.last4 ?? ''}',
      'mode': t.mode.name,
      if (t.isTransfer) 'is_transfer': true,
      if (t.note != null) 'note': t.note,
    };
  }

  // -------------------------------------------------------------------- tools

  Future<ToolOutcome> queryTransactions(Map<String, dynamic> a) async {
    final (from, to) = _range(a);
    final category = asString(a['category'])?.toLowerCase();
    final text = asString(a['text'])?.toLowerCase();
    final direction = asString(a['direction']);
    final min = asNumber(a['min_amount']);
    final max = asNumber(a['max_amount']);
    final includeTransfers = a['include_transfers'] == true;
    final limit = (asInt(a['limit']) ?? 25).clamp(1, _maxRows);

    final matches = (await _txns(from, to)).where((v) {
      final t = v.txn;
      if (!includeTransfers && t.isTransfer) return false;
      if (direction != null && t.direction.name != direction) return false;
      if (category != null && (v.category?.name.toLowerCase() ?? 'uncategorised') != category) return false;
      if (text != null && !'${t.merchant ?? ''} ${t.counterparty ?? ''}'.toLowerCase().contains(text)) return false;
      if (min != null && t.amountMinor < min * 100) return false;
      if (max != null && t.amountMinor > max * 100) return false;
      return true;
    }).toList();
    if (a['sort'] == 'amount') matches.sort((x, y) => y.txn.amountMinor.compareTo(x.txn.amountMinor));

    int sum(TxnDirection d) => matches.where((v) => v.txn.direction == d).fold(0, (s, v) => s + v.txn.amountMinor);
    final debit = sum(TxnDirection.debit), credit = sum(TxnDirection.credit);
    return ToolOutcome({
      'from': _day.format(from),
      'to': _day.format(to.subtract(const Duration(days: 1))),
      'matched': matches.length,
      'total_debit': _rupees(debit),
      'total_debit_formatted': money(debit),
      'total_credit': _rupees(credit),
      'total_credit_formatted': money(credit),
      'returned': matches.length < limit ? matches.length : limit,
      'transactions': [for (final v in matches.take(limit)) _row(v)],
    }, 'Looked at ${matches.length} transaction${matches.length == 1 ? '' : 's'}');
  }

  Future<ToolOutcome> spendingSummary(Map<String, dynamic> a) async {
    final (from, to) = _range(a);
    final groupBy = asString(a['group_by']) ?? 'category';
    final direction = asString(a['direction']) == 'credit' ? TxnDirection.credit : TxnDirection.debit;
    final txns = (await _txns(from, to)).where((v) => !v.txn.isTransfer && v.txn.direction == direction).toList();

    String key(TxnView v) => switch (groupBy) {
      'merchant' => v.txn.merchant ?? v.txn.counterparty ?? 'Unknown',
      'month' => DateFormat('yyyy-MM').format(v.txn.occurredAt),
      'day' => _day.format(v.txn.occurredAt),
      'account' => v.account == null ? 'Unknown account' : '${v.account!.name} ••${v.account!.last4 ?? ''}',
      _ => v.category?.name ?? 'Uncategorised',
    };

    const valid = {'category', 'merchant', 'month', 'day', 'account'};
    if (!valid.contains(groupBy)) throw const _BadArgs('group_by must be category, merchant, month, day or account');
    final groups = groupBy;
    final byKey = txns.groupListsBy(key);
    final rows = [
      for (final e in byKey.entries) (e.key, e.value.fold<int>(0, (s, v) => s + v.txn.amountMinor), e.value.length),
    ];
    if (groups == 'month' || groups == 'day') {
      rows.sort((x, y) => x.$1.compareTo(y.$1));
    } else {
      rows.sort((x, y) => y.$2.compareTo(x.$2));
    }
    final total = txns.fold<int>(0, (s, v) => s + v.txn.amountMinor);
    final shown = rows.take(groups == 'day' ? 62 : 30).toList();
    return ToolOutcome({
      'from': _day.format(from),
      'to': _day.format(to.subtract(const Duration(days: 1))),
      'direction': direction.name,
      'group_by': groups,
      'total': _rupees(total),
      'total_formatted': money(total),
      'transaction_count': txns.length,
      'groups': [
        for (final (k, sum, n) in shown)
          {
            'key': k,
            'total': _rupees(sum),
            'total_formatted': money(sum),
            'count': n,
            if (total > 0) 'share_pct': (sum * 1000 / total).round() / 10,
          },
      ],
      if (rows.length > shown.length) 'more_groups': rows.length - shown.length,
    }, 'Summarised ${txns.length} transaction${txns.length == 1 ? '' : 's'} by $groups');
  }

  Future<ToolOutcome> listCategories() async {
    final cats = await db.allCategories();
    return ToolOutcome({
      'categories': [
        for (final c in cats.sortedBy<num>((c) => c.sortOrder)) {'name': c.name, 'is_income': c.isIncome},
      ],
    }, 'Checked ${cats.length} categories');
  }

  Future<ToolOutcome> listAccounts() async {
    final accounts = (await db.allAccounts()).where((a) => !a.archived).toList();
    return ToolOutcome({
      'accounts': [
        for (final a in accounts)
          {'name': a.name, 'kind': a.kind.name, 'institution': ?a.institution, 'last4': ?a.last4},
      ],
    }, 'Checked ${accounts.length} account${accounts.length == 1 ? '' : 's'}');
  }

  Future<ToolOutcome> findRecurring(Map<String, dynamic> a) async {
    final months = (asInt(a['months']) ?? 6).clamp(2, 24);
    final today = DateTime(now().year, now().month, now().day);
    final from = DateTime(today.year, today.month - months, today.day);
    final txns = (await _txns(
      from,
      today.add(const Duration(days: 1)),
    )).where((v) => !v.txn.isTransfer && v.txn.direction == TxnDirection.debit).toList();
    final found = detectRecurring(txns, today: today);
    final monthly = monthlyTotalMinor(found);
    return ToolOutcome({
      'scanned_from': _day.format(from),
      'estimated_monthly_total': _rupees(monthly),
      'estimated_monthly_total_formatted': money(monthly),
      'recurring': [
        for (final r in found)
          {
            'merchant': r.name,
            'cadence': r.cadence,
            'typical_amount': _rupees(r.typicalMinor),
            'typical_amount_formatted': money(r.typicalMinor),
            'occurrences': r.count,
            'last_date': _day.format(r.last),
            'next_expected': _day.format(r.next),
            'category': ?r.category?.name,
            'monthly_cost': _rupees(r.monthlyCostMinor.round()),
          },
      ],
    }, 'Scanned ${txns.length} payments for patterns');
  }

  Future<ToolOutcome> recategorize(Map<String, dynamic> a, ConfirmRecategorize? confirm) async {
    final name = asString(a['category'])?.toLowerCase();
    final cats = await db.allCategories();
    final cat = cats.firstWhereOrNull((c) => c.name.toLowerCase() == name);
    if (cat == null) {
      return ToolOutcome(
        {'error': 'Unknown category "${a['category']}"', 'valid': cats.map((c) => c.name).toList()},
        'Unknown category',
        isError: true,
      );
    }
    final ids = (a['transaction_ids'] is List ? a['transaction_ids'] as List : const [])
        .map(asInt)
        .whereType<int>()
        .toSet();
    final merchant = asString(a['merchant'])?.toLowerCase();
    if (ids.isEmpty && merchant == null) throw _BadArgs('Give transaction_ids or merchant');

    final txns =
        await (db.select(db.transactions)..where(
              (t) => ids.isNotEmpty
                  ? t.id.isIn(ids)
                  : (t.merchant.lower().contains(merchant!) | t.counterparty.lower().contains(merchant)),
            ))
            .get();
    if (txns.isEmpty) {
      return const ToolOutcome({'error': 'No matching transactions'}, 'Nothing matched', isError: true);
    }
    final learn = merchant == null
        ? const <String>[]
        : txns.map((t) => t.merchant?.toLowerCase()).whereType<String>().toSet().toList();
    final proposal = RecategorizeProposal(txns: txns, category: cat, learnMerchants: learn);
    if (confirm == null || !await confirm(proposal)) {
      return ToolOutcome({
        'applied': false,
        'message': 'The user declined; nothing was changed.',
      }, 'Change not applied');
    }
    await db.transaction(() async {
      for (final t in txns) {
        await db.setCategory(t.id, cat.id);
      }
      for (final m in learn) {
        await db.setCategory(txns.firstWhere((t) => t.merchant?.toLowerCase() == m).id, cat.id, learnPattern: m);
      }
    });
    return ToolOutcome({
      'applied': true,
      'updated': txns.length,
      'category': cat.name,
      'rules_learned': learn.length,
    }, 'Moved ${txns.length} to ${cat.name}');
  }
}

class _BadArgs implements Exception {
  const _BadArgs(this.message);
  final String message;
}
