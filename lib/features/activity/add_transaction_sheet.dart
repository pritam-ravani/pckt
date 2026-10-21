import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/icons.dart';

import '../../core/format.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/amount_field.dart';
import '../../ui/currency_picker.dart';
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
  final _converted = TextEditingController();
  var _currency = Currencies.home;
  var _direction = TxnDirection.debit;
  int? _categoryId;
  var _at = DateTime.now();

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _converted.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minor = parseAmountInput(_amount.text, currency: _currency);
    if (minor == null || minor <= 0) return;
    final converted = _currency == Currencies.home
        ? null
        : parseAmountInput(_converted.text, currency: Currencies.home);
    await ref
        .read(databaseProvider)
        .addManual(
          amountMinor: minor,
          currency: _currency,
          convertedMinor: converted != null && converted > 0 ? converted : null,
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
            AmountField(
              controller: _amount,
              autofocus: true,
              color: color,
              currency: _currency,
              onCurrencyTap: () async {
                final c = await showCurrencyPicker(context, selected: _currency);
                if (c == null || c == _currency) return;
                setState(() {
                  _currency = c;
                  _amount.clear();
                  _converted.clear();
                });
              },
            ),
            if (_currency != Currencies.home) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _converted,
                keyboardType: TextInputType.numberWithOptions(decimal: currencyDigits(Currencies.home) > 0),
                inputFormatters: [AmountInputFormatter(currency: Currencies.home)],
                decoration: InputDecoration(
                  labelText: 'In ${Currencies.home} (optional)',
                  helperText: 'Without it, this stays out of your totals until you add it.',
                  prefixText: '${currencySymbol(Currencies.home)} ',
                ),
              ),
            ],
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
                onPressed: (parseAmountInput(_amount.text, currency: _currency) ?? 0) > 0 ? _save : null,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
