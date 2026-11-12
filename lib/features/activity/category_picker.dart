import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import 'category_search.dart';

/// Grid of category badges with a search box. Shows income or expense
/// categories depending on [income]; a search looks through all of them,
/// including everyday words that belong under a category ("dhobi" →
/// Laundry & Ironing).
class CategoryPicker extends ConsumerStatefulWidget {
  const CategoryPicker({super.key, required this.selectedId, required this.income, required this.onSelected});

  final int? selectedId;
  final bool income;
  final ValueChanged<Category> onSelected;

  @override
  ConsumerState<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<CategoryPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _pick(Category c) {
    if (_query.text.isNotEmpty) {
      _query.clear();
      FocusScope.of(context).unfocus();
    }
    widget.onSelected(c);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search, e.g. chai, dhobi, petrol',
            prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
            suffixIcon: ListenableBuilder(
              listenable: _query,
              builder: (_, _) => _query.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(PhosphorIconsBold.minusCircle, size: 18),
                      onPressed: _query.clear,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: _query,
          builder: (context, _) {
            if (_query.text.trim().isEmpty) {
              final primary = cats.where((c) => c.isIncome == widget.income || c.name == 'Transfers').toList();
              return _Grid(categories: primary, selectedId: widget.selectedId, onTap: _pick);
            }
            final rules = ref.watch(merchantRulesProvider).value ?? const <MerchantRule>[];
            final matches = searchCategories(_query.text, cats, rules: rules);
            if (matches.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No category matches "${_query.text.trim()}". Try another word, or add one in '
                  'Settings → Money → Categories.',
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall,
                ),
              );
            }
            return Column(
              children: [
                for (final m in matches)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: CategoryBadge(category: m.category, size: 36),
                    title: Text(m.category.name),
                    subtitle: m.via == null ? null : Text('Matches "${m.via}"'),
                    trailing: m.category.id == widget.selectedId
                        ? Icon(PhosphorIconsBold.checkCircle, color: Color(m.category.color))
                        : null,
                    onTap: () => _pick(m.category),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.categories, required this.selectedId, required this.onTap});

  final List<Category> categories;
  final int? selectedId;
  final ValueChanged<Category> onTap;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 86,
      mainAxisExtent: 86,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
    ),
    itemCount: categories.length,
    itemBuilder: (context, i) {
      final c = categories[i];
      final selected = c.id == selectedId;
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onTap(c),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected ? Color(c.color).withValues(alpha: 0.12) : null,
            border: Border.all(color: selected ? Color(c.color) : Colors.transparent, width: 1.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CategoryBadge(category: c, size: 38),
              const SizedBox(height: 6),
              Text(
                c.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
