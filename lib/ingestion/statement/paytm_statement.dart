import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../data/db/tables.dart';
import '../parser/parsed_txn.dart';

class StatementFormatException implements Exception {
  const StatementFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One payment from the "Passbook Payment History" sheet.
class PaytmRow {
  const PaytmRow({
    required this.occurredAt,
    required this.details,
    required this.counterparty,
    required this.account,
    required this.amountText,
    required this.amountMinor,
    required this.sign,
    required this.reference,
    required this.remarks,
    required this.tag,
  });

  final DateTime occurredAt;
  final String details;
  final String counterparty;
  final String account;
  final String amountText;
  final int amountMinor;

  /// '-' paid, '+' received, '' neither (Paytm's transfers between own accounts).
  final String sign;
  final String reference;
  final String remarks;

  /// First tag, as Paytm wrote it ("#🥘 Food"); may be empty.
  final String tag;

  bool get isCredit => sign == '+';
  bool get isSelfTransfer => sign.isEmpty || PaytmStatement.tagKey(tag) == 'self transfer';
}

class PaytmStatementFile {
  const PaytmStatementFile(this.rows, this.skipped);
  final List<PaytmRow> rows;

  /// Rows whose date or amount could not be read.
  final int skipped;
}

/// Reads the Excel UPI statement Paytm exports (Balance & History).
abstract final class PaytmStatement {
  static const sender = 'Paytm statement';
  static const _maxBytes = 20 * 1024 * 1024;
  static const _required = ['Date', 'Time', 'Transaction Details', 'Amount', 'UPI Ref No.'];

  static final _date = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');
  static final _time = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$');
  static final _amount = RegExp(r'^([+-]?)\s*([\d,]+)(?:\.(\d{1,2}))?$');
  static final _account = RegExp(r'^(.*?)\s*-\s*(\d+)$');
  static final _prefix = RegExp(r'^(paid to|money sent to|received from|refund from)\s+', caseSensitive: false);
  static final _appSuffix = RegExp(r'\s+on\s+[A-Za-z ]+$');

  /// The tag without its #, emoji or case: "#🥘 Food" → "food".
  static String tagKey(String tag) =>
      tag.replaceAll(RegExp(r'[^A-Za-z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  static PaytmStatementFile parse(List<int> bytes) {
    if (bytes.length > _maxBytes) throw const StatementFormatException('This file is too large to be a statement.');
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const StatementFormatException('Choose the Excel (.xlsx) statement from Paytm, not the PDF.');
    }
    final shared = _sharedStrings(zip);
    for (final file in zip.files) {
      if (!RegExp(r'^xl/worksheets/[^/]+\.xml$').hasMatch(file.name)) continue;
      final rows = _rows(XmlDocument.parse(_text(file)), shared);
      if (rows.isEmpty) continue;
      final header = {for (final e in rows.first.entries) e.value: e.key};
      if (_required.every(header.containsKey)) return _read(rows.skip(1), header);
    }
    throw const StatementFormatException('This doesn\'t look like a Paytm UPI statement.');
  }

  static ParsedTxn toParsed(PaytmRow r, {int? categoryId}) {
    final account = _account.firstMatch(r.account);
    final isPayment = _prefix.hasMatch(r.details);
    return ParsedTxn(
      amountMinor: r.amountMinor,
      currency: 'INR',
      direction: r.isCredit ? TxnDirection.credit : TxnDirection.debit,
      occurredAt: r.occurredAt,
      mode: PaymentMode.upi,
      confidence: 1,
      merchant: isPayment ? r.details.replaceFirst(_prefix, '').trim() : r.details,
      counterparty: r.counterparty.isEmpty ? null : r.counterparty.replaceFirst(_appSuffix, ''),
      accountHint: account?.group(2),
      institution: account?.group(1) ?? (r.account.isEmpty ? null : r.account),
      reference: r.reference.isEmpty ? null : r.reference,
      transferHint: r.isSelfTransfer,
      categoryId: categoryId,
      note: r.remarks.isEmpty ? null : r.remarks,
    );
  }

  static RawInput toRaw(PaytmRow r) => RawInput(
    source: SourceKind.statement,
    externalId: r.reference.isNotEmpty ? 'paytm:${r.reference}' : 'paytm:${r.occurredAt.toIso8601String()}:${r.amountText}',
    sender: sender,
    body: [r.details, r.counterparty, r.account, r.amountText, r.tag].where((s) => s.isNotEmpty).join(' · '),
    receivedAt: r.occurredAt,
  );

  static PaytmStatementFile _read(Iterable<Map<String, String>> rows, Map<String, String> header) {
    final out = <PaytmRow>[];
    var skipped = 0;
    for (final row in rows) {
      String cell(String name) => (row[header[name]] ?? '').trim();
      if (cell('Date').isEmpty && cell('Amount').isEmpty) continue;
      final at = _dateTime(cell('Date'), cell('Time'));
      final amount = _amount.firstMatch(cell('Amount'));
      if (at == null || amount == null) {
        skipped++;
        continue;
      }
      final paise = (amount.group(3) ?? '').padRight(2, '0');
      out.add(
        PaytmRow(
          occurredAt: at,
          details: cell('Transaction Details'),
          counterparty: cell('Other Transaction Details (UPI ID or A/c No)'),
          account: cell('Your Account'),
          amountText: cell('Amount'),
          amountMinor: int.parse(amount.group(2)!.replaceAll(',', '')) * 100 + int.parse(paise),
          sign: amount.group(1)!,
          reference: cell('UPI Ref No.'),
          remarks: cell('Remarks'),
          tag: cell('Tags').split(',').first.trim(),
        ),
      );
    }
    return PaytmStatementFile(out, skipped);
  }

  static DateTime? _dateTime(String date, String time) {
    final d = _date.firstMatch(date);
    final t = _time.firstMatch(time);
    if (d == null || t == null) return null;
    int n(RegExpMatch m, int i) => int.parse(m.group(i) ?? '0');
    return DateTime(n(d, 3), n(d, 2), n(d, 1), n(t, 1), n(t, 2), n(t, 3));
  }

  static String _text(ArchiveFile file) => utf8.decode(file.content, allowMalformed: true);

  static List<String> _sharedStrings(Archive zip) {
    final file = zip.findFile('xl/sharedStrings.xml');
    if (file == null) return const [];
    return [
      for (final si in XmlDocument.parse(_text(file)).findAllElements('si'))
        si.findAllElements('t').map((t) => t.innerText).join(),
    ];
  }

  /// Each sheet row as column letter → value, skipping empty rows.
  static List<Map<String, String>> _rows(XmlDocument sheet, List<String> shared) {
    final rows = <Map<String, String>>[];
    for (final row in sheet.findAllElements('row')) {
      final cells = <String, String>{};
      for (final c in row.findElements('c')) {
        final column = (c.getAttribute('r') ?? '').replaceAll(RegExp(r'\d'), '');
        final type = c.getAttribute('t');
        final String? value;
        if (type == 'inlineStr') {
          value = c.findAllElements('t').map((t) => t.innerText).join();
        } else {
          final raw = c.getElement('v')?.innerText;
          value = raw == null || type != 's' ? raw : shared[int.parse(raw)];
        }
        if (value != null && value.isNotEmpty) cells[column] = value;
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }
}
