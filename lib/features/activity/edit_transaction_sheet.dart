import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/amount_field.dart';
import '../../ui/widgets.dart';
import '../settings/accounts_screen.dart';
import '../settings/manage_widgets.dart';

Future<void> showEditTransactionSheet(BuildContext context, TxnView view) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _EditSheet(view: view),
);

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.view});
  final TxnView view;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  Transaction get _t => widget.view.txn;
  late final _amount = TextEditingController(text: amountInputText(_t.amountMinor));
  late final _merchant = TextEditingController(text: _t.merchant ?? '');
  late final _note = TextEditingController(text: _t.note ?? '');
  late var _direction = _t.direction;
  late var _at = _t.occurredAt;
  late int? _accountId = _t.accountId;
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final minor = parseAmountInput(_amount.text);
    if (minor == null || minor <= 0 || _saving) return;
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final newMerchant = _merchant.text.trim().isEmpty ? null : _merchant.text.trim();
    final oldMerchant = _t.merchant;
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();

    // A credit can't keep an expense category (and vice versa); Transfers fits both.
    final cat = widget.view.category;
    final kindMismatch = cat != null && cat.name != 'Transfers' && cat.isIncome != (_direction == TxnDirection.credit);

    var renameAll = false;
    if (oldMerchant != null && newMerchant != null && newMerchant != oldMerchant) {
      final others = await db.countTxnsWithMerchant(oldMerchant) - 1;
      if (others > 0 && mounted) {
        final all = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Rename "$oldMerchant"?'),
            content: Text(
              '$others other transaction${others == 1 ? '' : 's'} use${others == 1 ? 's' : ''} this name. '
              'Renaming all keeps their learned category too.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Just this one')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('All ${others + 1}')),
            ],
          ),
        );
        if (all == null) {
          setState(() => _saving = false);
          return;
        }
        renameAll = all;
      }
    }

    await db.transaction(() async {
      if (renameAll) await db.renameMerchant(oldMerchant!, newMerchant!);
      await db.updateTxn(
        _t.id,
        amountMinor: minor,
        direction: _direction,
        occurredAt: _at,
        merchant: newMerchant,
        accountId: _accountId,
        note: note,
        categoryId: kindMismatch ? const Value(null) : const Value.absent(),
      );
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = (ref.watch(allAccountsProvider).value ?? const <Account>[])
        .where((a) => !a.archived || a.id == _t.accountId)
        .toList();
    final color = _direction == TxnDirection.credit ? Palette.income : context.colors.onSurface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit transaction', style: context.text.titleLarge),
            const SizedBox(height: 14),
            SegmentedButton<TxnDirection>(
              segments: const [
                ButtonSegment(
                  value: TxnDirection.debit,
                  label: Text('Expense'),
                  icon: Icon(PhosphorIconsBold.arrowUpRight),
                ),
                ButtonSegment(
                  value: TxnDirection.credit,
                  label: Text('Income'),
                  icon: Icon(PhosphorIconsBold.arrowDownLeft),
                ),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 8),
            AmountField(controller: _amount, color: color),
            const SizedBox(height: 12),
            TextField(
              controller: _merchant,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Merchant',
                prefixIcon: Icon(PhosphorIconsRegular.storefront),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(PhosphorIconsRegular.calendarBlank, size: 18),
                    label: Text(dayLabel(_at)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(PhosphorIconsRegular.clock, size: 18),
                    label: Text(timeLabel(_at)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _accountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Account'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('No account')),
                for (final a in accounts)
                  DropdownMenuItem<int?>(
                    value: a.id,
                    child: Row(
                      children: [
                        AccountBadge(account: a, size: 26),
                        const SizedBox(width: 10),
                        Flexible(child: Text(accountLabel(a), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note', prefixIcon: Icon(PhosphorIconsRegular.notePencil)),
            ),
            const SizedBox(height: 8),
            Text(
              'The original SMS/email stays attached as evidence.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _amount,
              builder: (_, _) => FilledButton(
                onPressed: !_saving && (parseAmountInput(_amount.text) ?? 0) > 0 ? _save : null,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
