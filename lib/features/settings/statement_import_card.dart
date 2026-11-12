import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currency.dart';
import '../../core/theme/icons.dart';
import '../../ingestion/statement/paytm_statement.dart';
import '../../ingestion/statement/statement_import.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';

/// Settings → Sources: imports the Excel UPI statement from Paytm. The file
/// is read on the phone and nothing is sent anywhere.
class StatementImportCard extends ConsumerStatefulWidget {
  const StatementImportCard({super.key});

  @override
  ConsumerState<StatementImportCard> createState() => _StatementImportCardState();
}

class _StatementImportCardState extends ConsumerState<StatementImportCard> {
  var _busy = false;

  Future<void> _import() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Choose your Paytm Excel statement');
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    String title, message;
    try {
      final result = await PaytmStatementImporter(
        ref.read(databaseProvider),
        ref.read(ingestionProvider),
      ).import(await picked.readAsBytes());
      title = 'Statement imported';
      message = [
        '${result.added} added, ${result.merged} matched to payments you already had.',
        if (result.review > 0) '${result.review} to review in Activity.',
        if (result.alreadyImported > 0) '${result.alreadyImported} were already imported.',
        if (result.unreadable > 0) '${result.unreadable} rows could not be read.',
        if (result.newCategories.isNotEmpty) 'New categories: ${result.newCategories.join(', ')}.',
        if (Currencies.home != 'INR')
          'Your currency is ${Currencies.home}, so these rupee payments stay out of your totals. '
              'Change it in Settings → Money → Currency.',
      ].join('\n\n');
    } on StatementFormatException catch (e) {
      title = 'Couldn\'t read that file';
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
    child: ListTile(
      leading: const Icon(PhosphorIconsRegular.downloadSimple),
      title: const Text('Import Paytm statement'),
      subtitle: const Text('Excel file from Paytm → Balance & History. Read on this phone only.'),
      trailing: _busy
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(PhosphorIconsBold.caretRight, size: 16),
      onTap: _busy ? null : _import,
    ),
  );
}
