import '../data/db/database.dart';
import '../data/seed/default_categories.dart';
import 'parser/parsed_txn.dart';

/// Cheap, deterministic categorisation. Order of precedence:
/// user-learned rules → structural hints (transfer, ATM, P2P) →
/// built-in keyword lists → fallback. The LLM agent can override later.
class Categorizer {
  Categorizer(List<Category> categories, List<MerchantRule> rules)
    : _byName = {for (final c in categories) c.name: c},
      _rules = {for (final r in rules) r.pattern: r.categoryId},
      _keywords = [
        for (final seed in defaultCategories)
          for (final k in seed.keywords)
            (RegExp('(^|[^a-z])${RegExp.escape(k.trim())}([^a-z]|\$)'), seed.name, seed.isIncome),
      ];

  final Map<String, Category> _byName;
  final Map<String, int> _rules;
  final List<(RegExp, String, bool)> _keywords;

  int? _id(String name) => _byName[name]?.id;

  int? categorize(ParsedTxn t, String body) {
    final learned = _rules[t.merchant?.toLowerCase()];
    if (learned != null) return learned;

    if (t.transferHint) return _id('Transfers');
    if (t.mode == PaymentMode.atm) return _id('Cash Withdrawal');

    final isCredit = t.direction == TxnDirection.credit;
    final hay = '${t.merchant ?? ''} ${t.counterparty ?? ''}'.toLowerCase();
    for (final (re, name, income) in _keywords) {
      if (income == isCredit && re.hasMatch(hay)) return _id(name);
    }
    if (isCredit) {
      final lower = body.toLowerCase();
      for (final (re, name, income) in _keywords) {
        if (income && re.hasMatch(lower)) return _id(name);
      }
      return _id('Other Income');
    }
    if (t.isPersonToPerson) return _id('People');
    return _id('Other');
  }

  int? get transferId => _id('Transfers');
}
