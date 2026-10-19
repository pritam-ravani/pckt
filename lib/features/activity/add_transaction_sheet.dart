import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';

import '../../core/format.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../ingestion/parser/text_utils.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';
import 'category_picker.dart';

Future<void> showAddTransactionSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => const _AddSheet(),
);

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  var _direction = TxnDirection.debit;
  int? _categoryId;
  var _at = DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minor = parseMinor(_amount.text);
    if (minor == null || minor <= 0) return;
    await ref
        .read(databaseProvider)
        .addManual(
          amountMinor: minor,
          direction: _direction,
          at: _at,
          merchant: _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
          categoryId: _categoryId,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final color = _direction == TxnDirection.credit ? Palette.income : context.colors.onSurface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              onSelectionChanged: (s) => setState(() {
                _direction = s.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amount,
              autofocus: true,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              style: context.text.displaySmall?.copyWith(color: color),
              decoration: InputDecoration(
                hintText: '0',
                prefixText: '₹ ',
                prefixStyle: context.text.displaySmall?.copyWith(color: context.colors.onSurfaceVariant),
                filled: false,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _merchant,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: _direction == TxnDirection.debit ? 'Where did you spend?' : 'From whom?',
                prefixIcon: const Icon(PhosphorIconsRegular.storefront),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(PhosphorIconsRegular.calendarBlank),
              title: Text(dateTimeLabel(_at)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _at,
                  firstDate: DateTime(2015),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
              },
            ),
            const SectionHeader('Category'),
            CategoryPicker(
              selectedId: _categoryId,
              income: _direction == TxnDirection.credit,
              onSelected: (c) => setState(() => _categoryId = c.id),
            ),
            const SizedBox(height: 20),
            ListenableBuilder(
              listenable: _amount,
              builder: (_, _) => FilledButton(
                onPressed: (parseMinor(_amount.text) ?? 0) > 0 ? _save : null,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
