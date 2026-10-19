import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';

import '../../core/format.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import 'transaction_sheet.dart';

enum ActivityFilter { all, spent, received, review, transfers }

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, this.initialFilter});
  final String? initialFilter;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  late ActivityFilter _filter = ActivityFilter.values.asNameMap()[widget.initialFilter] ?? ActivityFilter.all;
  String _query = '';

  @override
  void didUpdateWidget(ActivityScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialFilter != old.initialFilter && widget.initialFilter != null) {
      _filter = ActivityFilter.values.asNameMap()[widget.initialFilter] ?? _filter;
    }
  }

  bool _matches(TxnView v) {
    final t = v.txn;
    final ok = switch (_filter) {
      ActivityFilter.all => true,
      ActivityFilter.spent => t.direction == TxnDirection.debit && !t.isTransfer,
      ActivityFilter.received => t.direction == TxnDirection.credit && !t.isTransfer,
      ActivityFilter.review => t.status == TxnStatus.needsReview,
      ActivityFilter.transfers => t.isTransfer,
    };
    if (!ok) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return [
      t.merchant,
      t.counterparty,
      t.note,
      v.category?.name,
      v.account?.name,
      (t.amountMinor ~/ 100).toString(),
    ].any((s) => s?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(allTxnsProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(children: [Text('Activity', style: context.text.headlineSmall)]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search merchant, category, amount',
                  prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                children: [
                  for (final f in ActivityFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (f) {
                          ActivityFilter.all => 'All',
                          ActivityFilter.spent => 'Spent',
                          ActivityFilter.received => 'Received',
                          ActivityFilter.review => 'Needs review',
                          ActivityFilter.transfers => 'Transfers',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: txns.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (all) {
                  final list = all.where(_matches).toList();
                  if (list.isEmpty) {
                    return ListView(
                      children: [
                        EmptyState(
                          icon: _filter == ActivityFilter.review
                              ? PhosphorIconsFill.checkCircle
                              : PhosphorIconsFill.receipt,
                          title: _filter == ActivityFilter.review ? 'All clear' : 'No transactions',
                          message: _filter == ActivityFilter.review
                              ? 'Nothing needs your attention right now.'
                              : 'Try a different filter or search.',
                        ),
                      ],
                    );
                  }
                  return _GroupedList(list: list);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.list});
  final List<TxnView> list;

  @override
  Widget build(BuildContext context) {
    // Flatten into headers + rows so the list stays lazily built.
    final items = <Object>[];
    DateTime? day;
    for (final v in list) {
      final d = DateTime(v.txn.occurredAt.year, v.txn.occurredAt.month, v.txn.occurredAt.day);
      if (d != day) {
        day = d;
        final spent = list
            .where(
              (x) =>
                  !x.txn.isTransfer &&
                  x.txn.direction == TxnDirection.debit &&
                  x.txn.occurredAt.year == d.year &&
                  x.txn.occurredAt.month == d.month &&
                  x.txn.occurredAt.day == d.day,
            )
            .fold<int>(0, (s, x) => s + x.txn.amountMinor);
        items.add((d, spent));
      }
      items.add(v);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 100),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is (DateTime, int)) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    dayLabel(item.$1),
                    style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
                if (item.$2 > 0)
                  Text(
                    '−${money(item.$2)}',
                    style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
              ],
            ),
          );
        }
        final v = item as TxnView;
        return TransactionTile(view: v, onTap: () => showTransactionSheet(context, v.txn.id));
      },
    );
  }
}
