import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../data/db/database.dart';
import 'llm_client.dart';
import 'llm_json.dart';

class CategoriseReport {
  int sent = 0, updated = 0, rulesLearned = 0, rejected = 0;
  int? maxId;
  String? error;

  @override
  String toString() => 'looked at $sent · recategorised $updated · learned $rulesLearned rules';
}

/// Fills in categories the rules left as "Other" / "Other Income" / none.
/// Only merchant, counterparty, amount, direction, mode and date are sent.
/// Answers are validated against the real category list; AI choices are
/// never locked, so the user (and later rules) can still override them.
class AiCategorizer {
  AiCategorizer({
    required this.db,
    required this.client,
    this.batchSize = 40,
    this.maxTxns = 200,
    this.pause = const Duration(milliseconds: 800),
  });

  final AppDatabase db;
  final LlmClient client;
  final int batchSize;
  final int maxTxns;
  final Duration pause;

  /// Confidence at which a merchant-level answer becomes a [MerchantRule].
  static const ruleConfidence = 0.8;

  static const fallbackNames = {'Other', 'Other Income'};

  /// Never assigned by the model — they carry structural meaning.
  static const _reserved = {'Transfers'};

  static final _date = DateFormat('yyyy-MM-dd');

  static String systemPrompt(List<Category> cats) {
    final expense = cats.where((c) => !c.isIncome && !_reserved.contains(c.name)).map((c) => c.name);
    final income = cats.where((c) => c.isIncome).map((c) => c.name);
    return '''
You categorise personal transactions for a user in India. Merchants may be UPI VPAs or abbreviated bank descriptors.
Expense categories (for debits): ${expense.join(', ')}
Income categories (for credits): ${income.join(', ')}

Use exactly one of these names. Use "Other"/"Other Income" when you can't tell; "People" for payments to individuals.
Set "merchantLevel" true only when the merchant name alone determines the category (e.g. Swiggy → Food & Dining), false when it depends on this particular payment.
Reply with ONLY JSON: {"results":[{"id":<id>,"category":"<name>","confidence":<0..1>,"merchantLevel":true|false}]}''';
  }

  /// Unlocked, non-transfer transactions without a useful category,
  /// newer than [afterId].
  Future<List<Transaction>> candidates({int afterId = 0}) async {
    final cats = await db.allCategories();
    final fallbackIds = cats.where((c) => fallbackNames.contains(c.name)).map((c) => c.id).toList();
    return (db.select(db.transactions)
          ..where(
            (t) =>
                t.categoryLocked.equals(false) &
                t.isTransfer.equals(false) &
                t.id.isBiggerThanValue(afterId) &
                (t.categoryId.isNull() | t.categoryId.isIn(fallbackIds)) &
                (t.merchant.isNotNull() | t.counterparty.isNotNull()),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(maxTxns))
        .get();
  }

  Future<CategoriseReport> run({int afterId = 0, void Function(int done, int total)? onProgress}) async {
    final report = CategoriseReport();
    final txns = await candidates(afterId: afterId);
    if (txns.isEmpty) return report;
    final cats = await db.allCategories();
    final byName = {for (final c in cats) c.name.toLowerCase(): c};
    final system = systemPrompt(cats);

    for (var i = 0; i < txns.length; i += batchSize) {
      final batch = txns.sublist(i, (i + batchSize).clamp(0, txns.length));
      if (i > 0) await Future<void>.delayed(pause);
      final payload = [
        for (final t in batch)
          {
            'id': t.id,
            'merchant': ?t.merchant,
            'counterparty': ?t.counterparty,
            'amount': t.amountMinor / 100,
            'direction': t.direction.name,
            'mode': t.mode.name,
            'date': _date.format(t.occurredAt),
          },
      ];
      report.sent += batch.length;
      final LlmResponse res;
      try {
        res = await client.chat(system: system, messages: [UserMessage(jsonEncode(payload))], maxTokens: 4096);
      } on LlmException catch (e) {
        report.error = e.userMessage;
        break;
      }
      await _apply(batch, extractResults(res.text), byName, report);
      for (final t in batch) {
        if (report.maxId == null || t.id > report.maxId!) report.maxId = t.id;
      }
      onProgress?.call(i + batch.length, txns.length);
    }
    return report;
  }

  Future<void> _apply(
    List<Transaction> batch,
    List<Map<String, dynamic>> results,
    Map<String, Category> byName,
    CategoriseReport report,
  ) async {
    final txnById = {for (final t in batch) t.id: t};
    await db.transaction(() async {
      for (final r in results) {
        final t = txnById[asInt(r['id'])];
        final name = asString(r['category'])?.toLowerCase();
        final cat = name == null ? null : byName[name];
        if (t == null || cat == null || _reserved.contains(cat.name)) {
          report.rejected++;
          continue;
        }
        // Direction must match the category kind.
        if (cat.isIncome != (t.direction == TxnDirection.credit)) {
          report.rejected++;
          continue;
        }
        if (fallbackNames.contains(cat.name) || cat.id == t.categoryId) continue;

        final updated =
            await (db.update(db.transactions)..where((x) => x.id.equals(t.id) & x.categoryLocked.equals(false))).write(
              TransactionsCompanion(categoryId: Value(cat.id)),
            );
        report.updated += updated;

        final confidence = asNumber(r['confidence']) ?? 0;
        final merchantLevel = r['merchantLevel'] == true;
        final pattern = t.merchant?.toLowerCase().trim();
        if (merchantLevel &&
            confidence >= ruleConfidence &&
            pattern != null &&
            pattern.length >= 3 &&
            cat.name != 'People') {
          // Never overwrite a rule the user taught us.
          final existing = await (db.select(
            db.merchantRules,
          )..where((x) => x.pattern.equals(pattern))).getSingleOrNull();
          if (existing == null) {
            await db.into(db.merchantRules).insert(MerchantRulesCompanion.insert(pattern: pattern, categoryId: cat.id));
            report.rulesLearned++;
          }
        }
      }
    });
  }
}
