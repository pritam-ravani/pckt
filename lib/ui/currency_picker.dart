import 'package:flutter/material.dart';

import '../core/currency.dart';
import '../core/theme/icons.dart';
import 'widgets.dart';

/// Searchable list of [supportedCurrencies]; resolves to the picked code.
Future<String?> showCurrencyPicker(BuildContext context, {String? selected, String title = 'Currency'}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => _CurrencyList(scroll: scroll, selected: selected, title: title),
      ),
    );

class _CurrencyList extends StatefulWidget {
  const _CurrencyList({required this.scroll, required this.selected, required this.title});
  final ScrollController scroll;
  final String? selected;
  final String title;

  @override
  State<_CurrencyList> createState() => _CurrencyListState();
}

class _CurrencyListState extends State<_CurrencyList> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = supportedCurrencies
        .where((c) => q.isEmpty || c.code.toLowerCase().contains(q) || c.name.toLowerCase().contains(q))
        .toList();
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(widget.title, style: context.text.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: const InputDecoration(
              hintText: 'Search currency',
              prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
            ),
          ),
        ),
        for (final c in list)
          ListTile(
            leading: SizedBox(
              width: 44,
              child: Center(
                child: Text(
                  // The bare sign, as the currency's own users write it.
                  currencySymbol(c.code, home: c.code),
                  style: context.text.titleMedium?.copyWith(color: context.colors.primary),
                ),
              ),
            ),
            title: Text(c.name),
            subtitle: Text(c.code),
            trailing: c.code == widget.selected ? const Icon(PhosphorIconsBold.check) : null,
            onTap: () => Navigator.pop(context, c.code),
          ),
      ],
    );
  }
}
