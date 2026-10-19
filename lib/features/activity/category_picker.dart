import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';

/// Grid of category badges. Shows income or expense categories first
/// depending on [income], with the other kind available below.
class CategoryPicker extends ConsumerWidget {
  const CategoryPicker({super.key, required this.selectedId, required this.income, required this.onSelected});

  final int? selectedId;
  final bool income;
  final ValueChanged<Category> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    final primary = cats.where((c) => c.isIncome == income || c.name == 'Transfers').toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 86,
        mainAxisExtent: 86,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: primary.length,
      itemBuilder: (context, i) {
        final c = primary[i];
        final selected = c.id == selectedId;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onSelected(c),
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
}
