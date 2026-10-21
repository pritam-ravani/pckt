import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/amount_field.dart';
import '../../ui/widgets.dart';

/// Asks what a foreign transaction came to in the home currency — the
/// amount from the card statement, or an exchange rate to work it out.
/// Pckt has no backend and fetches no rates; this is the only way a foreign
/// amount without a stated equivalent joins the home-currency totals.
Future<void> showConversionSheet(BuildContext context, Transaction txn) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ConversionSheet(txn: txn),
);

class _ConversionSheet extends ConsumerStatefulWidget {
  const _ConversionSheet({required this.txn});
  final Transaction txn;

  @override
  ConsumerState<_ConversionSheet> createState() => _ConversionSheetState();
}

class _ConversionSheetState extends ConsumerState<_ConversionSheet> {
  Transaction get _t => widget.txn;
  final _home = Currencies.home;
  late final _amount = TextEditingController(
    text: _t.convertedCurrency == _home && _t.convertedMinor != null
        ? amountInputText(_t.convertedMinor!, currency: _home)
        : '',
  );
  final _rate = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    super.dispose();
  }

  /// Fills the amount from `1 foreign = rate home`.
  void _applyRate(String text) {
    final rate = double.tryParse(text.trim());
    if (rate == null || rate <= 0) return;
    final minor = toMinor(toMajor(_t.amountMinor, _t.currency) * rate, _home);
    _amount.text = amountInputText(minor, currency: _home);
  }

  Future<void> _save({bool clear = false}) async {
    final minor = clear ? null : parseAmountInput(_amount.text, currency: _home);
    if (!clear && (minor == null || minor <= 0)) return;
    await ref.read(databaseProvider).setConversion(_t.id, minor: minor, currency: _home);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final original = money(_t.amountMinor, currency: _t.currency, forceDecimals: true);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$original in $_home', style: context.text.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Enter what your bank charged (it\'s on the statement), or the rate you got. '
              'Pckt works offline and never looks rates up.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            AmountField(controller: _amount, autofocus: true, currency: _home),
            const SizedBox(height: 12),
            TextField(
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}'))],
              onChanged: _applyRate,
              decoration: InputDecoration(
                labelText: 'Or exchange rate',
                prefixText: '1 ${_t.currency} = ',
                suffixText: _home,
                prefixIcon: const Icon(PhosphorIconsRegular.arrowsLeftRight),
              ),
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _amount,
              builder: (_, _) => FilledButton(
                onPressed: (parseAmountInput(_amount.text, currency: _home) ?? 0) > 0 ? _save : null,
                child: const Text('Count it in totals'),
              ),
            ),
            if (_t.convertedCurrency == _home) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: () => _save(clear: true), child: Text('Remove the $_home amount')),
            ],
          ],
        ),
      ),
    );
  }
}
