import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../ingestion_service.dart';
import 'paytm_statement.dart';

class StatementImportResult {
  const StatementImportResult({
    required this.total,
    required this.added,
    required this.merged,
    required this.review,
    required this.alreadyImported,
    required this.unreadable,
    required this.newCategories,
  });

  final int total, added, merged, review, alreadyImported, unreadable;
  final List<String> newCategories;
}

/// Brings a Paytm statement through the normal pipeline, using the tags the
/// user set in Paytm as categories.
class PaytmStatementImporter {
  PaytmStatementImporter(this.db, this.ingestion);

  final AppDatabase db;
  final IngestionService ingestion;

  /// Paytm tag (see [PaytmStatement.tagKey]) → built-in category. Any other
  /// tag becomes a category of its own, so the user's groupings survive.
  static const tagCategories = {
    'food': 'Food & Dining',
    'dinner': 'Food & Dining',
    'groceries': 'Groceries',
    'fruits': 'Groceries',
    'shopping': 'Shopping',
    'bill payments': 'Bills & Utilities',
    'medical': 'Health',
    'hospital': 'Health',
    'travel': 'Travel',
    'taxi': 'Transport',
    'metro': 'Transport',
    'fuel': 'Fuel',
    'entertainment': 'Entertainment',
    'movie': 'Entertainment',
    'donation': 'Gifts & Donations',
    'money transfer': 'People',
    'money received': 'Other Income',
    'refund': 'Refunds & Cashback',
    'self transfer': 'Transfers',
    'miscellaneous': 'Other',
  };

  Future<StatementImportResult> import(List<int> bytes) async {
    final file = PaytmStatement.parse(bytes);
    final created = <String>[];
    final categoryByTag = await _resolveTags(file.rows, created);
    final byId = {for (final c in await db.allCategories()) c.id: c};

    final report = await ingestion.ingestParsed([
      for (final row in file.rows)
        (
          PaytmStatement.toRaw(row),
          PaytmStatement.toParsed(row, categoryId: _categoryFor(row, categoryByTag, byId)),
        ),
    ]);
    return StatementImportResult(
      total: file.rows.length,
      added: report.added,
      merged: report.merged,
      review: report.flagged,
      alreadyImported: file.rows.length - report.seen,
      unreadable: file.skipped,
      newCategories: created,
    );
  }

  /// An income category on a payment (or the reverse) would be misleading,
  /// so such a row is left to the categoriser. Transfers keep theirs.
  int? _categoryFor(PaytmRow row, Map<String, int> byTag, Map<int, Category> byId) {
    final id = byTag[PaytmStatement.tagKey(row.tag)];
    if (id == null || row.isSelfTransfer) return id;
    return byId[id]?.isIncome == row.isCredit ? id : null;
  }

  Future<Map<String, int>> _resolveTags(List<PaytmRow> rows, List<String> created) async {
    final cats = await db.allCategories();
    final byName = {
      for (final c in cats) c.name.toLowerCase(): c.id,
      for (final c in cats)
        if (c.seedName != null) c.seedName!.toLowerCase(): c.id,
    };
    final out = <String, int>{};
    for (final row in rows) {
      final key = PaytmStatement.tagKey(row.tag);
      if (key.isEmpty || out.containsKey(key)) continue;
      final existing = byName[(tagCategories[key] ?? key).toLowerCase()];
      if (existing != null) {
        out[key] = existing;
        continue;
      }
      final name = _displayName(key);
      out[key] = await db.addCategory(
        name: name,
        icon: 'other',
        color: Palette.categories[(cats.length + created.length) * 5 % Palette.categories.length].toARGB32(),
        isIncome: rows.where((r) => PaytmStatement.tagKey(r.tag) == key).every((r) => r.isCredit),
      );
      created.add(name);
    }
    return out;
  }

  static String _displayName(String key) =>
      key.split(' ').map((w) => w == 'emi' ? 'EMI' : w[0].toUpperCase() + w.substring(1)).join(' ');
}
