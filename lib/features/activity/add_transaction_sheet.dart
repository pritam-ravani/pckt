import 'package:collection/collection.dart';
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
import '../settings/manage_widgets.dart';
import 'category_picker.dart';
import 'quick_entry.dart';

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
  var _saving = false;

  // Most entries repeat the previous payment type and account.
  late var _mode =
      PaymentMode.values.asNameMap()[ref.read(prefsProvider).getString(PrefKeys.quickAddMode)] ?? PaymentMode.upi;
  late int? _accountId = ref.read(prefsProvider).getInt(PrefKeys.quickAddAccount);

  static const _modes = [
    PaymentMode.upi,
    PaymentMode.card,
    PaymentMode.cash,
    PaymentMode.netbanking,
    PaymentMode.wallet,
  ];

  /// [_accountId], unless that account has since been archived or deleted.
  int? _validAccount(List<Account> accounts) => accounts.any((a) => a.id == _accountId) ? _accountId : null;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _converted.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minor = parseAmountInput(_amount.text, currency: _currency);
    if (minor == null || minor <= 0 || _saving) return;
    _saving = true;
    try {
      final db = ref.read(databaseProvider);
      final prefs = ref.read(prefsProvider);
      final accountId = _validAccount(ref.read(accountsProvider).value ?? const []);
      final existing = await findLikelyDuplicate(
        db,
        amountMinor: minor,
        currency: _currency,
        direction: _direction,
        at: _at,
      );
      if (existing != null && !await _confirmDuplicate(existing)) return;
      final converted = _currency == Currencies.home
          ? null
          : parseAmountInput(_converted.text, currency: Currencies.home);
      await db.addManual(
        amountMinor: minor,
        currency: _currency,
        convertedMinor: converted != null && converted > 0 ? converted : null,
        direction: _direction,
        at: _at,
        merchant: _merchant.text.trim().isEmpty ? null : _merchant.text.trim(),
        categoryId: _categoryId,
        accountId: accountId,
        mode: _mode,
      );
      await prefs.setString(PrefKeys.quickAddMode, _mode.name);
      if (accountId == null) {
        await prefs.remove(PrefKeys.quickAddAccount);
      } else {
        await prefs.setInt(PrefKeys.quickAddAccount, accountId);
      }
      if (mounted) Navigator.pop(context);
    } finally {
      _saving = false;
    }
  }

  /// True when the user wants to save despite the similar [existing] entry.
  Future<bool> _confirmDuplicate(Transaction existing) async {
    if (!mounted) return false;
    final name = existing.merchant ?? 'an existing transaction';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Already recorded?'),
        content: Text(
          '${money(existing.amountMinor, currency: existing.currency)} at $name '
          'on ${dateTimeLabel(existing.occurredAt)} looks like the same payment.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add anyway')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final color = _direction == TxnDirection.credit ? Palette.income : context.colors.onSurface;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final suggestions = ref.watch(merchantSuggestionsProvider(_direction)).value ?? const <MerchantSuggestion>[];
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
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ActionChip(
                    label: Text(suggestions[i].name),
                    onPressed: () => setState(() {
                      _merchant.text = suggestions[i].name;
                      _categoryId = suggestions[i].categoryId ?? _categoryId;
                    }),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in _modes)
                  ChoiceChip(
                    avatar: Icon(modeIcon(m), size: 16),
                    label: Text(modeLabel(m)),
                    selected: _mode == m,
                    onSelected: (_) => setState(() => _mode = m),
                  ),
              ],
            ),
            if (accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                key: ValueKey(accounts.length),
                initialValue: _validAccount(accounts),
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
                onChanged: (id) => setState(() {
                  _accountId = id;
                  final kind = accounts.firstWhereOrNull((a) => a.id == id)?.kind;
                  _mode = switch (kind) {
                    AccountKind.creditCard => PaymentMode.card,
                    AccountKind.cash => PaymentMode.cash,
                    AccountKind.wallet => PaymentMode.wallet,
                    _ => _mode,
                  };
                }),
              ),
            ],
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
