import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/category_icons.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import 'manage_widgets.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  var _income = false;

  /// Reorders within the visible kind ([to] is already adjusted for the
  /// removed item) and writes back a full ordering
  /// that keeps the other kind's rows in their slots.
  Future<void> _reorder(List<Category> all, List<Category> shown, int from, int to) async {
    final moved = [...shown];
    moved.insert(to, moved.removeAt(from));
    final shownIds = {for (final c in shown) c.id};
    final it = moved.iterator;
    final ids = [
      for (final c in all)
        if (shownIds.contains(c.id)) (it..moveNext()).current.id else c.id,
    ];
    await ref.read(databaseProvider).reorderCategories(ids);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final shown = all.where((c) => c.isIncome == _income).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCategoryEditor(context, income: _income),
        icon: const Icon(PhosphorIconsBold.plus),
        label: const Text('Category'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Expense')),
                  ButtonSegment(value: true, label: Text('Income')),
                ],
                selected: {_income},
                onSelectionChanged: (s) => setState(() => _income = s.first),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Drag to reorder. The order is used in pickers.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 100),
              buildDefaultDragHandles: false,
              itemCount: shown.length,
              onReorderItem: (from, to) => _reorder(all, shown, from, to),
              itemBuilder: (context, i) {
                final c = shown[i];
                return ListTile(
                  key: ValueKey(c.id),
                  leading: CategoryBadge(category: c, size: 40),
                  title: Text(c.name),
                  subtitle: AppDatabase.isProtected(c) ? const Text('Built-in') : null,
                  onTap: () => showCategoryEditor(context, category: c),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(PhosphorIconsBold.dotsSixVertical, size: 20),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showCategoryEditor(BuildContext context, {Category? category, bool income = false}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => _CategoryEditor(category: category, income: income, scroll: scroll),
      ),
    );

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.category, required this.income, required this.scroll});
  final Category? category;
  final bool income;
  final ScrollController scroll;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late var _icon = widget.category?.icon ?? 'other';
  late var _color = widget.category?.color ?? Palette.categories.first.toARGB32();
  late var _income = widget.category?.isIncome ?? widget.income;

  bool get _protected => widget.category != null && AppDatabase.isProtected(widget.category!);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final db = ref.read(databaseProvider);
    final c = widget.category;
    final clash = (await db.allCategories()).any((o) => o.id != c?.id && o.name.toLowerCase() == name.toLowerCase());
    if (clash) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A category called $name already exists')));
      }
      return;
    }
    if (c == null) {
      await db.addCategory(name: name, icon: _icon, color: _color, isIncome: _income);
    } else {
      await db.updateCategory(
        c.id,
        name: _protected ? null : name,
        icon: _icon,
        color: _color,
        isIncome: _protected ? null : _income,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final c = widget.category!;
    final db = ref.read(databaseProvider);
    final count = await db.countTxnsInCategory(c.id);
    final all = await db.allCategories();
    final targets = all.where((o) => o.id != c.id).toList()
      ..sort((a, b) => (a.isIncome == c.isIncome ? 0 : 1).compareTo(b.isIncome == c.isIncome ? 0 : 1));
    final fallback = targets.firstWhere((o) => (o.seedName ?? o.name) == 'Other', orElse: () => targets.first);
    if (!mounted) return;
    final moveTo = await showDialog<int>(
      context: context,
      builder: (_) => _MoveToDialog(category: c, count: count, targets: targets, initial: fallback.id),
    );
    if (moveTo == null) return;
    await db.deleteCategory(c.id, moveTo: moveTo);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final preview = Category(id: -1, name: _name.text, icon: _icon, color: _color, isIncome: _income, sortOrder: 0);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              CategoryBadge(category: preview, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _name,
                  enabled: !_protected,
                  autofocus: c == null,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
            ],
          ),
          if (!_protected) ...[
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Expense')),
                ButtonSegment(value: true, label: Text('Income')),
              ],
              selected: {_income},
              onSelectionChanged: (s) => setState(() => _income = s.first),
            ),
          ],
          const SizedBox(height: 16),
          Text('Colour', style: context.text.labelLarge),
          const SizedBox(height: 8),
          ColorSwatchPicker(selected: _color, onSelected: (v) => setState(() => _color = v)),
          const SizedBox(height: 16),
          Text('Icon', style: context.text.labelLarge),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [
              for (final e in CategoryIcons.all.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _icon = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: _icon == e.key
                          ? Color(_color).withValues(alpha: 0.16)
                          : context.colors.surfaceContainerHigh,
                      border: Border.all(color: _icon == e.key ? Color(_color) : Colors.transparent, width: 1.5),
                    ),
                    child: Icon(
                      e.value,
                      size: 22,
                      color: _icon == e.key ? Color(_color) : context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _name.text.trim().isEmpty ? null : _save, child: const Text('Save')),
          if (c != null && !_protected) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Palette.coral),
              onPressed: _delete,
              icon: const Icon(PhosphorIconsRegular.trash),
              label: const Text('Delete category'),
            ),
          ],
          if (_protected)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${c!.name} is built in, so it can\'t be renamed or deleted.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoveToDialog extends StatefulWidget {
  const _MoveToDialog({required this.category, required this.count, required this.targets, required this.initial});
  final Category category;
  final int count;
  final List<Category> targets;
  final int initial;

  @override
  State<_MoveToDialog> createState() => _MoveToDialogState();
}

class _MoveToDialogState extends State<_MoveToDialog> {
  late var _target = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Delete ${widget.category.name}?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.count == 0
              ? 'No transactions use it. Learned merchant rules move to:'
              : 'Move ${widget.count} transaction${widget.count == 1 ? '' : 's'} and its merchant rules to:',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _target,
          isExpanded: true,
          items: [
            for (final c in widget.targets)
              DropdownMenuItem(
                value: c.id,
                child: Row(
                  children: [
                    CategoryBadge(category: c, size: 26),
                    const SizedBox(width: 10),
                    Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
          onChanged: (v) => setState(() => _target = v ?? _target),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(
        style: TextButton.styleFrom(foregroundColor: Palette.coral),
        onPressed: () => Navigator.pop(context, _target),
        child: const Text('Delete'),
      ),
    ],
  );
}
