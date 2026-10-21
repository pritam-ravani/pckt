import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/db/database.dart';
import '../../ingestion/share/share_intake.dart';
import '../activity/transaction_sheet.dart';

/// Snackbar describing what happened to text shared to Pckt.
void showShareOutcome(BuildContext context, ShareOutcome o) {
  String describe(Transaction t) =>
      '${money(t.amountMinor, currency: t.currency)} ${t.direction == TxnDirection.debit ? 'spent' : 'received'}'
      '${t.merchant == null ? '' : ' · ${t.merchant}'}';
  final txn = o.txn;
  final text = switch (o.kind) {
    ShareOutcomeKind.added => txn == null ? 'Transaction added' : 'Added ${describe(txn)}',
    ShareOutcomeKind.merged => txn == null ? 'Already tracked' : 'Already tracked — matched ${describe(txn)}',
    ShareOutcomeKind.duplicate => txn == null ? 'Already shared this message' : 'Already added: ${describe(txn)}',
    ShareOutcomeKind.ignored => 'Not a transaction${o.reason == null ? '' : ' (${o.reason!.toLowerCase()})'}',
    ShareOutcomeKind.unreadable => "Couldn't read a transaction from that text",
  };
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 6),
      action: txn == null
          ? null
          : SnackBarAction(label: 'View', onPressed: () => showTransactionSheet(context, txn.id)),
    ),
  );
}
