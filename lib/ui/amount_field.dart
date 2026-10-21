import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import 'widgets.dart';

final _groups = <String, NumberFormat>{};

/// Whole-unit grouping: Indian (1,23,456) for INR, thousands elsewhere.
NumberFormat _group(String currency) =>
    _groups[currency] ??= currency == 'INR' ? NumberFormat('#,##,##0', 'en_IN') : NumberFormat('#,##0', 'en');

/// Minor units → editable text: "12,500" or "12,500.5" (INR by default).
String amountInputText(int minor, {String currency = 'INR'}) {
  final per = minorPerUnit(currency);
  final whole = _group(currency).format(minor ~/ per);
  final frac = minor % per;
  if (frac == 0) return whole;
  return '$whole.${frac.toString().padLeft(currencyDigits(currency), '0').replaceFirst(RegExp(r'0+$'), '')}';
}

/// Parses text from an [AmountField] into minor units of [currency]; null
/// if empty/invalid.
int? parseAmountInput(String text, {String currency = 'INR'}) {
  final cleaned = text.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  final v = double.tryParse(cleaned);
  if (v == null) return null;
  return toMinor(v, currency);
}

/// Keeps digits and one decimal point (as many places as [currency] has,
/// none for JPY) and regroups the whole part as the user types — Indian
/// style (1,23,456) for INR.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter({this.currency = 'INR'});

  final String currency;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    if (raw.isEmpty) return const TextEditingValue();
    final digits = currencyDigits(currency);
    final dot = raw.indexOf('.');
    var whole = dot < 0 ? raw : raw.substring(0, dot);
    var frac = dot < 0 || digits == 0 ? null : raw.substring(dot + 1).replaceAll('.', '');
    if (frac != null && frac.length > digits) frac = frac.substring(0, digits);
    whole = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (whole.length > 13) return oldValue; // ₹99,999 crore / ¥9 trillion is plenty
    final grouped = whole.isEmpty ? '0' : _group(currency).format(int.parse(whole));
    final text = frac == null ? grouped : '$grouped.$frac';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The original, INR-only name.
typedef IndianAmountFormatter = AmountInputFormatter;

/// Large centred amount input with optional one-tap presets.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.color,
    this.presets = const [],
    this.hint = '0',
    this.currency,
    this.onCurrencyTap,
  });

  final TextEditingController controller;
  final bool autofocus;
  final Color? color;

  /// Quick picks, in minor units of [currency].
  final List<int> presets;
  final String hint;

  /// Defaults to the home currency.
  final String? currency;

  /// When set, the currency symbol is a button (to pick another currency).
  final VoidCallback? onCurrencyTap;

  @override
  Widget build(BuildContext context) {
    final code = currency ?? Currencies.home;
    final prefixStyle = context.text.displaySmall?.copyWith(color: context.colors.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          autofocus: autofocus,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.numberWithOptions(decimal: currencyDigits(code) > 0),
          inputFormatters: [AmountInputFormatter(currency: code)],
          style: context.text.displaySmall?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: onCurrencyTap == null ? '${currencySymbol(code)} ' : null,
            prefixStyle: prefixStyle,
            prefixIcon: onCurrencyTap == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton(
                      onPressed: onCurrencyTap,
                      child: Text(
                        currencySymbol(code),
                        style: context.text.headlineSmall?.copyWith(color: context.colors.primary),
                      ),
                    ),
                  ),
            filled: false,
          ),
        ),
        if (presets.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in presets)
                ActionChip(
                  label: Text(moneyCompact(p, currency: code)),
                  onPressed: () {
                    final text = amountInputText(p, currency: code);
                    controller.value = TextEditingValue(
                      text: text,
                      selection: TextSelection.collapsed(offset: text.length),
                    );
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
