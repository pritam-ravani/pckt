import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/seed/category_aliases.dart';
import '../../data/seed/default_categories.dart';
import '../../providers.dart';

/// A category found by a search, and the word that led to it when that
/// wasn't the category's own name ("Medicines" via "pharmacy").
class CategoryMatch {
  const CategoryMatch(this.category, {this.via});
  final Category category;
  final String? via;
}

String _clean(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r' +'), ' ').trim();

final Map<String, List<String>> _seedTerms = {
  for (final seed in defaultCategories)
    seed.name: {
      for (final k in [...seed.keywords, ...?categoryAliases[seed.name]])
        if (_clean(k).length >= 2) _clean(k),
    }.toList(),
};

/// Categories for [query], best first: by name, then by everyday words and
/// merchant keywords, then by merchants the user has filed there.
List<CategoryMatch> searchCategories(
  String query,
  List<Category> categories, {
  List<MerchantRule> rules = const [],
  int limit = 12,
}) {
  final q = _clean(query);
  if (q.isEmpty) return const [];

  int nameScore(String name) {
    final n = _clean(name);
    if (n == q) return 100;
    if (n.startsWith(q)) return 90;
    if (n.split(' ').any((w) => w.startsWith(q))) return 80;
    return n.contains(q) && q.length >= 3 ? 70 : 0;
  }

  int termScore(String term) {
    if (term == q) return 60;
    if (term.startsWith(q) && q.length >= 2) return 50;
    if (term.length >= 3 && RegExp('(^| )${RegExp.escape(term)}( |\$)').hasMatch(q)) return 40;
    return term.contains(q) && q.length >= 3 ? 30 : 0;
  }

  final ruleTerms = <int, List<String>>{};
  for (final r in rules) {
    (ruleTerms[r.categoryId] ??= []).add(_clean(r.pattern));
  }

  final scored = <(CategoryMatch, int)>[];
  for (final c in categories) {
    var best = nameScore(c.name);
    String? via;
    if (best == 0 && c.seedName != null) {
      // A renamed seed category is still found by its original name.
      final s = nameScore(c.seedName!);
      if (s > 0) (best, via) = (s - 5, c.seedName);
    }
    for (final term in [...?_seedTerms[c.seedName ?? c.name]]) {
      final s = termScore(term);
      if (s > best) (best, via) = (s, term);
    }
    for (final term in [...?ruleTerms[c.id]]) {
      final s = termScore(term) - 5;
      if (s > best) (best, via) = (s, term);
    }
    if (best > 0) scored.add((CategoryMatch(c, via: via), best));
  }
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    return byScore != 0 ? byScore : a.$1.category.sortOrder.compareTo(b.$1.category.sortOrder);
  });
  return [for (final s in scored.take(limit)) s.$1];
}

/// Merchants the user has filed under a category, for search.
final merchantRulesProvider = FutureProvider.autoDispose<List<MerchantRule>>(
  (ref) => ref.watch(databaseProvider).allMerchantRules(),
);
