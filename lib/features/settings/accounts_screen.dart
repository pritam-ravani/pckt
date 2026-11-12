import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/amount_field.dart';
import '../../ui/currency_picker.dart';
import '../../ui/widgets.dart';
import 'manage_widgets.dart';

/// Every account, archived ones included.
final allAccountsProvider = StreamProvider<List<Account>>((ref) => ref.watch(databaseProvider).watchAllAccounts());

/// Running balance of every account, keyed by account id.
final balancesProvider = StreamProvider<Map<int, AccountBalance>>(
  (ref) => ref.watch(databaseProvider).watchBalances().map((list) => {for (final b in list) b.account.id: b}),
);

/// "₹12,345" for a bank, "₹3,200 due" for a card that is owed money.
String balanceLabel(AccountBalance b) {
  final minor = b.balanceMinor!;
  final currency = b.account.currency;
  if (b.account.kind == AccountKind.creditCard) {
    return minor < 0 ? '${money(-minor, currency: currency)} due' : money(minor, currency: currency);
  }
  return minor < 0 ? '−${money(-minor, currency: currency)}' : money(minor, currency: currency);
}

/// Minor units as editable text: 1234550 → "12345.5".
String _amountText(int minor, String currency) {
  final digits = currencyDigits(currency);
  var scale = 1;
  for (var i = 0; i < digits; i++) {
    scale *= 10;
  }
  final whole = minor ~/ scale;
  final fraction = minor % scale;
  return fraction == 0 ? '$whole' : '$whole.${fraction.toString().padLeft(digits, '0')}';
}

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(allAccountsProvider).value ?? const <Account>[];
    final active = accounts.where((a) => !a.archived).toList();
    final archived = accounts.where((a) => a.archived).toList();
    final balances = ref.watch(balancesProvider).value ?? const <int, AccountBalance>{};

    Widget trailing(Account a) {
      final b = balances[a.id];
      final text = b != null && b.isSet ? balanceLabel(b) : 'Set balance';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: b != null && b.isSet
                ? context.text.titleSmall
                : context.text.bodySmall?.copyWith(color: context.colors.primary),
          ),
          const SizedBox(width: 6),
          const Icon(PhosphorIconsBold.caretRight, size: 16),
        ],
      );
    }

    Widget group(List<Account> list) => AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Column(
        children: [
          for (final a in list)
            ListTile(
              leading: AccountBadge(account: a, size: 40),
              title: Text(a.name),
              subtitle: Text(
                [
                  accountKindLabel(a.kind),
                  if (a.institution != null && a.institution != a.name) a.institution!,
                  if (a.last4 != null && a.last4!.isNotEmpty) '••${a.last4}',
                ].join('  ·  '),
              ),
              trailing: trailing(a),
              onTap: () => showAccountEditor(context, account: a),
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAccountEditor(context),
        icon: const Icon(PhosphorIconsBold.plus),
        label: const Text('Cash account'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Accounts are detected from your messages by the last digits. Rename them or add a cash wallet for '
              'manual spends.',
              style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
          if (active.isEmpty)
            const EmptyState(
              icon: PhosphorIconsFill.bank,
              title: 'No accounts yet',
              message: 'They appear once a bank SMS or email is imported.',
            )
          else
            group(active),
          if (archived.isNotEmpty) ...[const SizedBox(height: 20), const SectionHeader('Archived'), group(archived)],
        ],
      ),
    );
  }
}

Future<void> showAccountEditor(BuildContext context, {Account? account}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _AccountEditor(account: account),
);

class _AccountEditor extends ConsumerStatefulWidget {
  const _AccountEditor({this.account});
  final Account? account;

  @override
  ConsumerState<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends ConsumerState<_AccountEditor> {
  late final _name = TextEditingController(text: widget.account?.name ?? 'Cash');
  late var _kind = widget.account?.kind ?? AccountKind.cash;
  late var _color = widget.account?.color ?? Palette.categories[5].toARGB32();
  late var _archived = widget.account?.archived ?? false;
  late var _currency = widget.account?.currency ?? Currencies.home;

  // Opening balance. A card's is entered as the amount due and stored negative.
  late final _opening = TextEditingController(text: _openingText());
  late DateTime? _openingAt = widget.account?.openingBalanceAt;
  late var _openingCleared = false;

  String _openingText() {
    final minor = widget.account?.openingBalanceMinor;
    return minor == null ? '' : _amountText(minor.abs(), widget.account!.currency);
  }

  bool get _isCard => _kind == AccountKind.creditCard;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final db = ref.read(databaseProvider);
    final a = widget.account;
    final int id;
    if (a == null) {
      id = await db.addAccount(name: name, kind: _kind, color: _color, currency: _currency);
    } else {
      id = a.id;
      await db.updateAccount(a.id, name: name, kind: _kind, color: _color, archived: _archived, currency: _currency);
    }
    final entered = parseAmountInput(_opening.text, currency: _currency);
    if (entered != null) {
      final signed = _isCard ? -entered : entered;
      if (signed != a?.openingBalanceMinor || _openingAt != a?.openingBalanceAt) {
        await db.setOpeningBalance(id, signed, at: _openingAt ?? DateTime.now());
      }
    } else if (_openingCleared && a?.openingBalanceMinor != null) {
      await db.setOpeningBalance(id, null);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickOpeningDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _openingAt ?? now,
      firstDate: DateTime(2015),
      lastDate: now,
    );
    if (d == null) return;
    final today = DateTime(now.year, now.month, now.day);
    // Today means "right now"; an earlier day means its closing balance.
    setState(() => _openingAt = d == today ? now : DateTime(d.year, d.month, d.day, 23, 59, 59));
  }

  Widget _balanceSection(AccountBalance? b) {
    final bank = b?.reported?.balanceAfterMinor;
    final diff = b?.differenceMinor;
    final at = _openingAt;
    String m(int minor) => money(minor, currency: _currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text('Balance', style: context.text.labelLarge),
        if (b != null && b.isSet) ...[
          const SizedBox(height: 4),
          Text('Now: ${balanceLabel(b)}', style: context.text.titleMedium),
          if (b.unconverted > 0)
            Text(
              '${b.unconverted} foreign transaction${b.unconverted == 1 ? '' : 's'} left out until converted',
              style: context.text.bodySmall,
            ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _opening,
          keyboardType: TextInputType.numberWithOptions(decimal: currencyDigits(_currency) > 0),
          inputFormatters: [AmountInputFormatter(currency: _currency)],
          decoration: InputDecoration(
            labelText: _isCard ? 'Amount due' : 'Balance',
            prefixText: '${currencySymbol(_currency)} ',
            helperText: _isCard
                ? 'What the card owed on the date below. Payments and spends after it are added.'
                : 'What the account held on the date below. Payments after it are added.',
            helperMaxLines: 2,
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(PhosphorIconsRegular.calendarBlank),
          title: Text(
            at == null || DateTime.now().difference(at).inMinutes < 5
                ? 'As of right now'
                : 'As of ${dateTimeLabel(at)}',
          ),
          onTap: _pickOpeningDate,
        ),
        if (bank != null && b?.reported != null) ...[
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your bank said ${m(bank)} on ${dateTimeLabel(b!.reported!.occurredAt)}.'),
                if (diff != null && diff != 0)
                  Text(
                    'PennyWise has ${m(diff.abs())} ${diff > 0 ? 'less' : 'more'} at that point, so a transaction may '
                    'be missing or recorded twice.',
                    style: context.text.bodySmall?.copyWith(color: Palette.coral),
                  )
                else if (diff == 0)
                  Text('PennyWise matches it.', style: context.text.bodySmall?.copyWith(color: Palette.income)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _opening.text = _amountText(bank.abs(), _currency);
                      _openingAt = b.reported!.occurredAt;
                    }),
                    child: const Text('Use bank\'s balance'),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.account?.openingBalanceMinor != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _opening.clear();
                _openingAt = null;
                _openingCleared = true;
              }),
              child: const Text('Stop tracking balance'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(a == null ? 'New account' : 'Edit account', style: context.text.titleLarge),
            if (a?.last4 != null && a!.last4!.isNotEmpty)
              Text(
                'Matched by ••${a.last4}${a.institution == null ? '' : ' · ${a.institution}'}',
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: a == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 16),
            Text('Type', style: context.text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in AccountKind.values)
                  ChoiceChip(
                    avatar: Icon(accountIcon(k), size: 16),
                    label: Text(accountKindLabel(k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() => _kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(PhosphorIconsRegular.coins),
              title: const Text('Currency'),
              subtitle: Text(currencyFor(_currency)?.toString() ?? _currency),
              trailing: const Icon(PhosphorIconsBold.caretRight, size: 16),
              onTap: () async {
                final c = await showCurrencyPicker(context, selected: _currency, title: 'Account currency');
                if (c != null) setState(() => _currency = c);
              },
            ),
            _balanceSection(a == null ? null : ref.watch(balancesProvider).value?[a.id]),
            const SizedBox(height: 8),
            Text('Colour', style: context.text.labelLarge),
            const SizedBox(height: 8),
            ColorSwatchPicker(selected: _color, onSelected: (c) => setState(() => _color = c)),
            if (a != null) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                value: _archived,
                onChanged: (v) => setState(() => _archived = v),
                title: const Text('Archived'),
                subtitle: const Text('Hidden from pickers; its transactions stay'),
              ),
            ],
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _name,
              builder: (_, _) =>
                  FilledButton(onPressed: _name.text.trim().isEmpty ? null : _save, child: const Text('Save')),
            ),
          ],
        ),
      ),
    );
  }
}
