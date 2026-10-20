import 'package:flutter/material.dart';

import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../ui/widgets.dart';

/// The validated categorical palette plus neutral, as ARGB ints.
final pickerColors = [
  for (final c in [...Palette.categories, Palette.neutral]) c.toARGB32(),
];

class ColorSwatchPicker extends StatelessWidget {
  const ColorSwatchPicker({super.key, required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final c in pickerColors)
        Semantics(
          button: true,
          selected: c == selected,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onSelected(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: c == selected ? context.colors.onSurface : Colors.transparent, width: 2.5),
              ),
              child: c == selected ? const Icon(PhosphorIconsBold.check, color: Colors.white, size: 18) : null,
            ),
          ),
        ),
    ],
  );
}

IconData accountIcon(AccountKind kind) => switch (kind) {
  AccountKind.bank => PhosphorIconsFill.bank,
  AccountKind.creditCard => PhosphorIconsFill.creditCard,
  AccountKind.wallet => PhosphorIconsFill.wallet,
  AccountKind.cash => PhosphorIconsFill.money,
};

String accountKindLabel(AccountKind kind) => switch (kind) {
  AccountKind.bank => 'Bank',
  AccountKind.creditCard => 'Credit card',
  AccountKind.wallet => 'Wallet',
  AccountKind.cash => 'Cash',
};

/// "HDFC Bank ••1234" style label.
String accountLabel(Account a) => a.last4 == null || a.last4!.isEmpty ? a.name : '${a.name} ••${a.last4}';

/// Rounded tile with an account's kind icon in its color.
class AccountBadge extends StatelessWidget {
  const AccountBadge({super.key, required this.account, this.size = 44});
  final Account account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(account.color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      alignment: Alignment.center,
      child: Icon(accountIcon(account.kind), color: color, size: size * 0.5),
    );
  }
}
