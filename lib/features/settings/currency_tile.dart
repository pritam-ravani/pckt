import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currency.dart';
import '../../core/theme/icons.dart';
import '../../providers.dart';
import '../../ui/currency_picker.dart';

/// Settings → Money: the home currency used for totals, budgets and the
/// assistant.
class HomeCurrencyTile extends ConsumerWidget {
  const HomeCurrencyTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(homeCurrencyProvider);
    return ListTile(
      leading: const Icon(PhosphorIconsRegular.coins),
      title: const Text('Currency'),
      subtitle: Text('${currencyFor(code)?.name ?? code} · totals and budgets'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(code), const SizedBox(width: 6), const Icon(PhosphorIconsBold.caretRight, size: 16)],
      ),
      onTap: () => changeHomeCurrency(context, ref),
    );
  }
}

/// Picks a new home currency. With data already recorded, first explains
/// what changes: nothing is converted (Pckt has no exchange rates).
Future<void> changeHomeCurrency(BuildContext context, WidgetRef ref, {bool confirm = true}) async {
  final current = ref.read(homeCurrencyProvider);
  final code = await showCurrencyPicker(context, selected: current, title: 'Home currency');
  if (code == null || code == current || !context.mounted) return;
  if (confirm) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Switch to ${currencyFor(code)?.name ?? code}?'),
        content: Text(
          'Totals, budgets and the assistant will use $code. Nothing is converted: transactions in $current '
          'stay in $current and drop out of the totals unless you add a $code amount to them. '
          'Budgets set in $current pause until you set them again. You can switch back any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Use $code')),
        ],
      ),
    );
    if (ok != true) return;
  }
  await ref.read(homeCurrencyProvider.notifier).set(code);
}
