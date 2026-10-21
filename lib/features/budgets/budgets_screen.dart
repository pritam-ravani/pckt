import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/amount_field.dart';
import '../../ui/widgets.dart';
import '../stats.dart';
import 'budget_math.dart';
import 'budget_providers.dart';
import 'budget_widgets.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
    final progress = ref.watch(budgetProgressProvider).value ?? const <BudgetProgress>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final alertsOn = ref.watch(budgetAlertsProvider);

    final overallBudget = budgets.firstWhereOrNull((b) => b.categoryId == null);
    final overall = progress.firstWhereOrNull((p) => p.isOverall);
    final catBudgets = budgets.where((b) => b.categoryId != null).toList();
    final byId = {for (final c in cats) c.id: c};
    final progressById = {for (final p in progress) p.budget.id: p};
    // Active ones by closeness to the limit, paused ones last.
    catBudgets.sort((a, b) {
      final pa = progressById[a.id], pb = progressById[b.id];
      if ((pa == null) != (pb == null)) return pa == null ? 1 : -1;
      return (pb?.ratio ?? 0).compareTo(pa?.ratio ?? 0);
    });
    final budgeted = catBudgets.map((b) => b.categoryId).toSet();
    final available = cats.where((c) => !c.isIncome && !budgeted.contains(c.id) && c.name != 'Transfers').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Limits repeat every month. Showing ${monthLabel(month)}; transfers between your accounts don\'t count.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
          const SectionHeader('Monthly budget'),
          if (overallBudget == null)
            AppCard(
              onTap: () => showBudgetEditor(context, ref),
              child: Row(
                children: [
                  const Icon(PhosphorIconsFill.target, color: Palette.violet),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Set an overall monthly budget', style: context.text.titleSmall)),
                  const Icon(PhosphorIconsBold.plus, size: 18),
                ],
              ),
            )
          else
            _BudgetTile(
              title: 'All spending',
              budget: overallBudget,
              progress: overall,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Palette.violet.withValues(alpha: context.isDark ? 0.18 : 0.14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(PhosphorIconsFill.target, color: Palette.violet),
              ),
              onTap: () => showBudgetEditor(context, ref, existing: overallBudget),
            ),
          const SizedBox(height: 20),
          SectionHeader(
            'Category limits',
            action: available.isEmpty ? null : 'Add',
            onAction: () => _pickCategory(context, ref, available),
          ),
          if (catBudgets.isEmpty)
            AppCard(
              onTap: available.isEmpty ? null : () => _pickCategory(context, ref, available),
              child: Text(
                'Cap a category like Food or Shopping to see how close you are each month.',
                style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            )
          else
            for (final b in catBudgets)
              if (byId[b.categoryId] case final c?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BudgetTile(
                    title: c.name,
                    budget: b,
                    progress: progressById[b.id],
                    leading: CategoryBadge(category: c),
                    onTap: () => showBudgetEditor(context, ref, category: c, existing: b),
                  ),
                ),
          const SizedBox(height: 20),
          const SectionHeader('Alerts'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: SwitchListTile(
              value: alertsOn,
              onChanged: (v) => ref.read(budgetAlertsProvider.notifier).setEnabled(v),
              secondary: const Icon(PhosphorIconsRegular.bellRinging),
              title: const Text('Budget alerts'),
              subtitle: const Text('Notify me at 80% and when a budget is exceeded'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref, List<Category> available) async {
    final c = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text('Limit which category?', style: c.text.titleMedium),
            ),
            for (final cat in available)
              ListTile(
                leading: CategoryBadge(category: cat, size: 36),
                title: Text(cat.name),
                onTap: () => Navigator.pop(c, cat),
              ),
          ],
        ),
      ),
    );
    if (c != null && context.mounted) await showBudgetEditor(context, ref, category: c);
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.title,
    required this.budget,
    required this.progress,
    required this.leading,
    required this.onTap,
  });

  final String title;
  final Budget budget;
  final BudgetProgress? progress;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    // Set before the home currency changed: kept, but not tracked.
    final stale = budget.currency != Currencies.home;
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Opacity(
        opacity: budget.active ? 1 : 0.55,
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: context.text.titleSmall)),
                      if (stale)
                        InfoPill(icon: PhosphorIconsBold.pause, label: 'Set in ${budget.currency}')
                      else if (!budget.active)
                        const InfoPill(icon: PhosphorIconsBold.pause, label: 'Paused')
                      else
                        Text(
                          '${money(p?.spentMinor ?? 0)} / ${money(budget.amountMinor)}',
                          style: context.text.labelLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: p == null || p.level == BudgetLevel.ok ? null : budgetColor(p),
                          ),
                        ),
                    ],
                  ),
                  if (p != null) ...[
                    const SizedBox(height: 8),
                    BudgetBar(progress: p),
                    const SizedBox(height: 6),
                    Text(
                      paceLabel(p),
                      style: context.text.bodySmall?.copyWith(
                        color: p.remainingMinor < 0 ? Palette.coral : context.colors.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    Text(
                      stale
                          ? '${money(budget.amountMinor, currency: budget.currency)} a month · tap to set it in '
                                '${Currencies.home}'
                          : '${money(budget.amountMinor)} a month',
                      style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to create/edit/remove the overall budget ([category] null)
/// or a category limit.
Future<void> showBudgetEditor(BuildContext context, WidgetRef ref, {Category? category, Budget? existing}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BudgetEditor(category: category, existing: existing),
    );

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor({this.category, this.existing});
  final Category? category;
  final Budget? existing;

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  final _currency = Currencies.home;
  late final _amount = TextEditingController(
    text: widget.existing == null || widget.existing!.currency != _currency
        ? ''
        : amountInputText(widget.existing!.amountMinor, currency: _currency),
  );
  late var _active = widget.existing?.active ?? true;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Average monthly spend over the 3 months before the selected one.
  int? _average() {
    final trend = ref.watch(trendTxnsProvider).value;
    final month = ref.watch(selectedMonthProvider);
    if (trend == null) return null;
    final totals = <int>[];
    for (var i = 1; i <= 3; i++) {
      final m = DateTime(month.year, month.month - i);
      final inMonth = trend.where((v) => v.txn.occurredAt.year == m.year && v.txn.occurredAt.month == m.month);
      if (inMonth.isEmpty) continue;
      final stats = MonthStats(inMonth.toList(), m);
      totals.add(
        widget.category == null
            ? stats.spent
            : stats.categories.firstWhereOrNull((c) => c.category?.id == widget.category!.id)?.amount ?? 0,
      );
    }
    if (totals.isEmpty) return null;
    final avg = totals.reduce((a, b) => a + b) ~/ totals.length;
    if (avg <= 0) return null;
    // Round up: to ₹500 for rupees, to two significant figures elsewhere.
    var step = 50000;
    if (_currency != 'INR') {
      step = 1;
      while (avg ~/ step >= 100) {
        step *= 10;
      }
    }
    return ((avg + step - 1) ~/ step) * step;
  }

  Future<void> _save() async {
    final minor = parseAmountInput(_amount.text, currency: _currency);
    if (minor == null || minor <= 0) return;
    await ref
        .read(databaseProvider)
        .setBudget(categoryId: widget.category?.id, amountMinor: minor, active: _active, currency: _currency);
    if (_active && ref.read(budgetAlertsProvider)) {
      await ref.read(notificationsProvider).requestPermission();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final avg = _average();
    // Fixed picks only make sense in rupees; elsewhere offer the average.
    final presets = <int>{
      ?avg,
      if (_currency == 'INR')
        ...(widget.category == null
            ? const [1000000, 2500000, 5000000, 7500000]
            : const [200000, 500000, 1000000, 1500000]),
    }.toList();
    final title = widget.category == null ? 'Monthly budget' : '${widget.category!.name} limit';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.category != null) ...[
                  CategoryBadge(category: widget.category, size: 36),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(title, style: context.text.titleLarge)),
              ],
            ),
            const SizedBox(height: 12),
            AmountField(controller: _amount, autofocus: widget.existing == null, presets: presets, currency: _currency),
            if (avg != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'You spent about ${moneyCompact(avg)} a month recently.',
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active'),
                subtitle: const Text('Paused budgets are kept but not tracked'),
              ),
            ],
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _amount,
              builder: (_, _) => FilledButton(
                onPressed: (parseAmountInput(_amount.text, currency: _currency) ?? 0) > 0 ? _save : null,
                child: const Text('Save'),
              ),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Palette.coral),
                onPressed: () async {
                  await ref.read(databaseProvider).deleteBudget(widget.existing!.id);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(PhosphorIconsRegular.trash),
                label: const Text('Remove budget'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
