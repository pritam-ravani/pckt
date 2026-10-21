import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currency.dart';
import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/currency_picker.dart';
import '../../ui/widgets.dart';
import 'manage_widgets.dart';

/// Every account, archived ones included.
final allAccountsProvider = StreamProvider<List<Account>>((ref) => ref.watch(databaseProvider).watchAllAccounts());

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(allAccountsProvider).value ?? const <Account>[];
    final active = accounts.where((a) => !a.archived).toList();
    final archived = accounts.where((a) => a.archived).toList();

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
              trailing: const Icon(PhosphorIconsBold.caretRight, size: 16),
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

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final db = ref.read(databaseProvider);
    final a = widget.account;
    if (a == null) {
      await db.addAccount(name: name, kind: _kind, color: _color, currency: _currency);
    } else {
      await db.updateAccount(a.id, name: name, kind: _kind, color: _color, archived: _archived, currency: _currency);
    }
    if (mounted) Navigator.pop(context);
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
