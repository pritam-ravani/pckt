import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/icons.dart';
import '../../data/db/database.dart';
import '../../providers.dart';
import '../../ui/amount_field.dart';
import '../../ui/widgets.dart';
import 'salary_math.dart';
import 'salary_providers.dart';

class _LineField {
  _LineField(this.kind, this.code, String label, String amount)
    : label = TextEditingController(text: label),
      amount = TextEditingController(text: amount);

  final PayslipLineKind kind;
  final String code;
  final TextEditingController label, amount;

  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

/// Adds a payslip ([id] null, starting from the latest one's lines so only
/// what changed needs typing) or edits one.
class PayslipEditorScreen extends ConsumerStatefulWidget {
  const PayslipEditorScreen({super.key, this.id});
  final int? id;

  @override
  ConsumerState<PayslipEditorScreen> createState() => _PayslipEditorScreenState();
}

class _PayslipEditorScreenState extends ConsumerState<PayslipEditorScreen> {
  final _employer = TextEditingController();
  final _fields = <_LineField>[];
  late DateTime _month;
  late final String _currency;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final all = ref.read(payslipsProvider).value ?? const <PayslipView>[];
    final now = DateTime.now();
    final editing = all.where((p) => p.payslip.id == widget.id).firstOrNull;
    final latest = all.firstOrNull;
    if (editing != null) {
      _month = editing.payslip.month;
      _currency = editing.payslip.currency;
      _employer.text = editing.payslip.employer;
      _addLines(editing.lines.map((l) => (l.kind, l.code, l.label, l.amountMinor)));
    } else {
      _currency = Currencies.home;
      if (latest != null) {
        final next = DateTime(latest.payslip.month.year, latest.payslip.month.month + 1);
        _month = next.isAfter(DateTime(now.year, now.month)) ? DateTime(now.year, now.month) : next;
        _employer.text = latest.payslip.employer;
        // A bonus is rarely the same next month, so it starts empty.
        _addLines(
          latest.lines.map((l) => (l.kind, l.code, l.label, l.code == PayslipCodes.bonus ? 0 : l.amountMinor)),
        );
      } else {
        _month = DateTime(now.year, now.month - 1);
        _addLines(defaultPayslipLines.map((l) => (l.kind, l.code, l.label, 0)));
      }
    }
  }

  void _addLines(Iterable<(PayslipLineKind, String, String, int)> lines) {
    for (final (kind, code, label, minor) in lines) {
      _fields.add(_LineField(kind, code, label, minor == 0 ? '' : _amountText(minor)));
    }
  }

  String _amountText(int minor) {
    final digits = currencyDigits(_currency);
    var scale = 1;
    for (var i = 0; i < digits; i++) {
      scale *= 10;
    }
    final whole = minor ~/ scale;
    final fraction = minor % scale;
    return fraction == 0 ? '$whole' : '$whole.${fraction.toString().padLeft(digits, '0')}';
  }

  int _minor(_LineField f) => parseAmountInput(f.amount.text, currency: _currency) ?? 0;

  int _sum(PayslipLineKind kind) => _fields.where((f) => f.kind == kind).fold(0, (s, f) => s + _minor(f));

  @override
  void dispose() {
    _employer.dispose();
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    if (_saving) return;
    final gross = _sum(PayslipLineKind.earning);
    if (gross <= 0) return _showError('Add at least one earning.');
    if (_sum(PayslipLineKind.deduction) > gross) return _showError('Deductions are more than the earnings.');
    final lines = [
      for (final f in _fields)
        if (_minor(f) > 0 && f.label.text.trim().isNotEmpty)
          PayslipLineDraft(kind: f.kind, code: f.code, label: f.label.text.trim(), amountMinor: _minor(f)),
    ];
    _saving = true;
    final db = ref.read(databaseProvider);
    try {
      await db.savePayslip(
        id: widget.id,
        month: _month,
        employer: _employer.text,
        currency: _currency,
        lines: lines,
      );
      await db.autoLinkPayslips();
      if (mounted) context.pop();
    } on DuplicatePayslipException {
      _showError('You already have a payslip for ${monthLabel(_month)} from this employer.');
    } finally {
      _saving = false;
    }
  }

  List<DateTime> get _months {
    final now = DateTime.now();
    final recent = [for (var i = 0; i < 36; i++) DateTime(now.year, now.month - i)];
    return recent.contains(_month) ? recent : [_month, ...recent];
  }

  Widget _section(String title, PayslipLineKind kind, String addLabel) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title),
      for (final f in _fields.where((f) => f.kind == kind))
        Padding(
          key: ObjectKey(f),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: f.label,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Name'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 132,
                child: TextField(
                  controller: f.amount,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.numberWithOptions(decimal: currencyDigits(_currency) > 0),
                  inputFormatters: [AmountInputFormatter(currency: _currency)],
                  decoration: InputDecoration(prefixText: '${currencySymbol(_currency)} ', hintText: '0'),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(PhosphorIconsBold.minusCircle, size: 18),
                onPressed: () => setState(() {
                  _fields.remove(f);
                  WidgetsBinding.instance.addPostFrameCallback((_) => f.dispose());
                }),
              ),
            ],
          ),
        ),
      TextButton.icon(
        onPressed: () => setState(() => _fields.add(_LineField(kind, '', '', ''))),
        icon: const Icon(PhosphorIconsBold.plus, size: 16),
        label: Text(addLabel),
      ),
      const SizedBox(height: 12),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final inputs = Listenable.merge([for (final f in _fields) f.amount]);
    return Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? 'Add payslip' : 'Edit payslip')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          DropdownButtonFormField<DateTime>(
            initialValue: _month,
            decoration: const InputDecoration(labelText: 'Pay for'),
            items: [for (final m in _months) DropdownMenuItem(value: m, child: Text(monthLabel(m)))],
            onChanged: (m) => setState(() => _month = m ?? _month),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _employer,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Employer (optional)'),
          ),
          const SizedBox(height: 20),
          _section('Earnings', PayslipLineKind.earning, 'Add earning'),
          _section('Deductions', PayslipLineKind.deduction, 'Add deduction'),
          _section('Paid by your employer', PayslipLineKind.employerContribution, 'Add contribution'),
          ListenableBuilder(
            listenable: inputs,
            builder: (_, _) {
              final net = _sum(PayslipLineKind.earning) - _sum(PayslipLineKind.deduction);
              return AppCard(
                child: Row(
                  children: [
                    Expanded(child: Text('Net pay', style: context.text.titleMedium)),
                    Text(money(net, currency: _currency), style: context.text.titleLarge),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
