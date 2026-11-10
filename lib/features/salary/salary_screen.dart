import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import 'salary_providers.dart';

/// Settings → Money → Salary & payslips: one card per payslip, newest first.
class SalaryScreen extends ConsumerStatefulWidget {
  const SalaryScreen({super.key});

  @override
  ConsumerState<SalaryScreen> createState() => _SalaryScreenState();
}

class _SalaryScreenState extends ConsumerState<SalaryScreen> {
  @override
  void initState() {
    super.initState();
    // Salary SMS or statements may have arrived since the payslip was added.
    ref.read(databaseProvider).autoLinkPayslips();
  }

  @override
  Widget build(BuildContext context) {
    final payslips = ref.watch(payslipsProvider).value ?? const <PayslipView>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Salary & payslips')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add payslip',
        onPressed: () => context.push('/salary/new'),
        child: const Icon(PhosphorIconsBold.plus),
      ),
      body: payslips.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsFill.briefcase,
              title: 'No payslips yet',
              message: 'Add one to see gross pay, deductions and what you keep. It stays on this phone.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: payslips.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _PayslipCard(view: payslips[i]),
            ),
    );
  }
}

class _PayslipCard extends StatelessWidget {
  const _PayslipCard({required this.view});
  final PayslipView view;

  @override
  Widget build(BuildContext context) {
    final currency = view.payslip.currency;
    final matched = view.salaryTxn != null;
    return AppCard(
      onTap: () => context.push('/salary/${view.payslip.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            view.payslip.employer.isEmpty
                ? monthLabel(view.payslip.month)
                : '${monthLabel(view.payslip.month)} · ${view.payslip.employer}',
            style: context.text.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(money(view.netMinor, currency: currency), style: context.text.headlineSmall),
          Text('Net pay', style: context.text.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoPill(icon: PhosphorIconsBold.arrowDownLeft, label: 'Gross ${money(view.grossMinor, currency: currency)}'),
              InfoPill(
                icon: PhosphorIconsBold.minusCircle,
                label: 'Deductions ${money(view.deductionsMinor, currency: currency)}',
              ),
              InfoPill(
                icon: matched ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.question,
                label: matched ? 'In bank' : 'Not matched',
                color: matched ? Palette.income : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
