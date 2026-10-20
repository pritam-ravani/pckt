import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import '../activity/transaction_sheet.dart';
import 'recurring_detector.dart';

/// Recurring payments detected over the last 12 months.
final recurringProvider = StreamProvider<List<RecurringPayment>>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return ref
      .watch(databaseProvider)
      .watchTxns(from: DateTime(today.year - 1, today.month, today.day), to: today.add(const Duration(days: 1)))
      .map((txns) => detectRecurring(txns, today: today));
});

String cadenceLabel(String cadence) => switch (cadence) {
  'weekly' => 'Weekly',
  'monthly' => 'Monthly',
  'quarterly' => 'Every 3 months',
  _ => cadence,
};

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = ref.watch(recurringProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      body: found.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: PhosphorIconsFill.repeat,
              title: 'No subscriptions spotted yet',
              message:
                  'Payments to the same merchant for a similar amount every week, month or quarter show up here '
                  'after three occurrences.',
            );
          }
          final monthly = monthlyTotalMinor(list);
          final today = DateTime.now();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              _TotalCard(monthlyMinor: monthly, count: list.length),
              const SizedBox(height: 16),
              for (final r in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecurringTile(payment: r, today: today),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.monthlyMinor, required this.count});
  final int monthlyMinor;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        colors: Palette.heroGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recurring, per month',
          style: context.text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
        ),
        const SizedBox(height: 6),
        Text(
          money(monthlyMinor),
          style: context.text.displaySmall?.copyWith(
            color: Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$count payment${count == 1 ? '' : 's'} · ${money(monthlyMinor * 12)} a year',
          style: context.text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
        ),
      ],
    ),
  );
}

class _RecurringTile extends StatelessWidget {
  const _RecurringTile({required this.payment, required this.today});
  final RecurringPayment payment;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final r = payment;
    final overdue = r.isOverdue(today);
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: r.payments.isEmpty ? null : () => showTransactionSheet(context, r.payments.last.txn.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryBadge(category: r.category),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                    Text(
                      '${cadenceLabel(r.cadence)} · ${r.count} payments',
                      style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(r.typicalMinor),
                    style: context.text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (r.cadence != 'monthly')
                    Text(
                      '≈ ${money(r.monthlyCostMinor.round())}/mo',
                      style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoPill(icon: PhosphorIconsBold.checkCircle, label: 'Last paid ${dayLabel(r.last)}'),
              InfoPill(
                icon: PhosphorIconsBold.calendarBlank,
                label: overdue ? 'Expected ${dayLabel(r.next)}' : 'Next ${_nextLabel(r.next)}',
                color: overdue ? Palette.amber : Palette.violet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _nextLabel(DateTime next) {
    final d = DateTime(next.year, next.month, next.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (d == 0) return 'today';
    if (d == 1) return 'tomorrow';
    if (d < 7) return 'in $d days';
    return monthDay(next);
  }
}

String monthDay(DateTime d) => '${d.day} ${monthShort(d)}';
