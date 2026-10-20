import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import 'widgets.dart';

final _group = NumberFormat('#,##,##0', 'en_IN');

/// Paise → editable text: "12,500" or "12,500.5".
String amountInputText(int minor) {
  final rupees = minor ~/ 100;
  final paise = minor % 100;
  final whole = _group.format(rupees);
  if (paise == 0) return whole;
  return '$whole.${paise.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
}

/// Parses text from an [AmountField] into paise; null if empty/invalid.
int? parseAmountInput(String text) {
  final cleaned = text.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  final v = double.tryParse(cleaned);
  if (v == null) return null;
  return (v * 100).round();
}

/// Keeps digits and one decimal point (2 places max) and regroups the
/// rupee part Indian-style (1,23,456) as the user types.
class IndianAmountFormatter extends TextInputFormatter {
  const IndianAmountFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    if (raw.isEmpty) return const TextEditingValue();
    final dot = raw.indexOf('.');
    var whole = dot < 0 ? raw : raw.substring(0, dot);
    var frac = dot < 0 ? null : raw.substring(dot + 1).replaceAll('.', '');
    if (frac != null && frac.length > 2) frac = frac.substring(0, 2);
    whole = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (whole.length > 11) return oldValue; // ₹99,999 crore is plenty
    final grouped = whole.isEmpty ? '0' : _group.format(int.parse(whole));
    final text = frac == null ? grouped : '$grouped.$frac';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Large centred ₹ amount input with optional one-tap presets.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.color,
    this.presets = const [],
    this.hint = '0',
  });

  final TextEditingController controller;
  final bool autofocus;
  final Color? color;

  /// Quick picks, in paise.
  final List<int> presets;
  final String hint;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: controller,
        autofocus: autofocus,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [IndianAmountFormatter()],
        style: context.text.displaySmall?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
        decoration: InputDecoration(
          hintText: hint,
          prefixText: '₹ ',
          prefixStyle: context.text.displaySmall?.copyWith(color: context.colors.onSurfaceVariant),
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
                label: Text(moneyCompact(p)),
                onPressed: () {
                  final text = amountInputText(p);
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
