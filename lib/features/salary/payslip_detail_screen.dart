import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import 'salary_math.dart';
import 'salary_providers.dart';

class PayslipDetailScreen extends ConsumerWidget {
  const PayslipDetailScreen({super.key, required this.id});
  final int id;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this payslip?'),
        content: const Text('Your bank transactions are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Palette.coral),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(databaseProvider).deletePayslip(id);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(payslipsProvider).value ?? const <PayslipView>[];
    final view = all.where((p) => p.payslip.id == id).firstOrNull;
    if (view == null) return Scaffold(appBar: AppBar());

    final month = view.payslip.month;
    final currency = view.payslip.currency;
    final stats = ref.watch(monthStatsProvider(month)).value;
    final sameMonth = all.where((p) => p.payslip.month == month).toList();
    final breakdown = stats == null ? null : SalaryBreakdown(sameMonth, stats);
    String m(int minor) => money(minor, currency: currency);

    return Scaffold(
      appBar: AppBar(
        title: Text(monthLabel(month)),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(PhosphorIconsRegular.pencilSimple),
            onPressed: () => context.push('/salary/$id/edit'),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(PhosphorIconsRegular.trash),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (breakdown != null) ...[
            const SectionHeader('Where it went'),
            AppCard(
              child: Column(
                children: [
                  _Row('Gross pay', m(breakdown.grossMinor)),
                  _Row('Deductions', '− ${m(breakdown.deductionsMinor)}'),
                  const Divider(height: 20),
                  _Row('Net pay', m(breakdown.netMinor), bold: true),
                  _Row('Spent in ${monthShort(month)}', '− ${m(breakdown.spentMinor)}'),
                  const Divider(height: 20),
                  _Row(
                    breakdown.leftMinor < 0 ? 'Overspent' : 'Left over',
                    m(breakdown.leftMinor.abs()),
                    bold: true,
                    color: breakdown.leftMinor < 0 ? Palette.coral : Palette.income,
                  ),
                ],
              ),
            ),
            if (breakdown.totalFoodMinor > 0) ...[
              const SizedBox(height: 20),
              const SectionHeader('Food'),
              AppCard(
                child: Column(
                  children: [
                    _Row('Company food', m(breakdown.companyFoodMinor)),
                    _Row('Your own food spending', m(breakdown.personalFoodMinor)),
                    const Divider(height: 20),
                    _Row('Total food', m(breakdown.totalFoodMinor), bold: true),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
          if (sameMonth.length == 1 || view.payslip.employer.isEmpty)
            const SectionHeader('Payslip')
          else
            SectionHeader(view.payslip.employer),
          for (final kind in PayslipLineKind.values)
            if (view.lines.any((l) => l.kind == kind)) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(switch (kind) {
                      PayslipLineKind.earning => 'Earnings',
                      PayslipLineKind.deduction => 'Deductions',
                      PayslipLineKind.employerContribution => 'Paid by your employer (not in your net pay)',
                    }, style: context.text.titleMedium),
                    const SizedBox(height: 8),
                    for (final l in view.lines.where((l) => l.kind == kind)) _Row(l.label, m(l.amountMinor)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 10),
          const SectionHeader('Bank credit'),
          _BankCredit(view: view),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false, this.color});
  final String label, value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = (bold ? context.text.titleMedium : context.text.bodyMedium)?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _BankCredit extends ConsumerWidget {
  const _BankCredit({required this.view});
  final PayslipView view;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final credits = await db.salaryCredits(month: view.payslip.month, currency: view.payslip.currency);
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<Transaction>(
      context: context,
      useSafeArea: true,
      builder: (c) => credits.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No money received around this month yet.', textAlign: TextAlign.center),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                for (final t in credits)
                  ListTile(
                    title: Text(money(t.amountMinor, currency: t.currency)),
                    subtitle: Text('${t.merchant ?? 'Money received'} · ${dateTimeLabel(t.occurredAt)}'),
                    onTap: () => Navigator.pop(c, t),
                  ),
              ],
            ),
    );
    if (picked != null) await db.linkSalary(view.payslip.id, picked.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txn = view.salaryTxn;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: txn == null
          ? ListTile(
              leading: const Icon(PhosphorIconsBold.question),
              title: const Text('Not matched to a bank credit'),
              subtitle: const Text('Tap to choose the payment'),
              trailing: const Icon(PhosphorIconsBold.caretRight, size: 16),
              onTap: () => _choose(context, ref),
            )
          : ListTile(
              leading: const Icon(PhosphorIconsBold.checkCircle, color: Palette.income),
              title: Text(money(txn.amountMinor, currency: txn.currency)),
              subtitle: Text('${txn.merchant ?? 'Salary'} · ${dateTimeLabel(txn.occurredAt)}'),
              trailing: TextButton(
                onPressed: () => ref.read(databaseProvider).unlinkSalary(view.payslip.id),
                child: const Text('Not this'),
              ),
            ),
    );
  }
}
