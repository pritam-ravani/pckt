import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/icons.dart';
import '../../core/theme/palette.dart';
import '../../data/backup/data_export.dart';
import '../../providers.dart';

final dataExportProvider = Provider((ref) => DataExport(ref.watch(databaseProvider)));

/// Settings → Data: CSV export, JSON backup and restore.
class DataExportTiles extends ConsumerWidget {
  const DataExportTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      ListTile(
        leading: const Icon(PhosphorIconsRegular.fileCsv),
        title: const Text('Export transactions (CSV)'),
        subtitle: const Text('Opens in Excel, Sheets or Numbers'),
        onTap: () => _run(context, () async {
          final csv = await ref.read(dataExportProvider).transactionsCsv();
          if (!context.mounted) return;
          await _deliver(context, 'pckt-transactions-${_stamp()}.csv', utf8.encode(csv), 'text/csv');
        }),
      ),
      ListTile(
        leading: const Icon(PhosphorIconsRegular.archive),
        title: const Text('Back up everything'),
        subtitle: const Text('Accounts, categories, transactions, messages and rules as JSON'),
        onTap: () => _run(context, () async {
          final json = await ref.read(dataExportProvider).backupJson();
          if (!context.mounted) return;
          await _deliver(context, 'pckt-backup-${_stamp()}.json', utf8.encode(json), 'application/json');
        }),
      ),
      ListTile(
        leading: const Icon(PhosphorIconsRegular.clockCounterClockwise),
        title: const Text('Restore from backup'),
        subtitle: const Text('Replaces all data on this phone'),
        onTap: () => _run(context, () => _restore(context, ref)),
      ),
    ],
  );
}

String _stamp() => DateFormat('yyyyMMdd-HHmm').format(DateTime.now());

Future<void> _run(BuildContext context, Future<void> Function() job) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await job();
  } on BackupFormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Something went wrong: $e')));
  }
}

/// Lets the user pick between the share sheet and saving to a folder.
Future<void> _deliver(BuildContext context, String name, List<int> bytes, String mime) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(PhosphorIconsRegular.shareNetwork),
            title: const Text('Share…'),
            subtitle: const Text('Drive, email, chat apps'),
            onTap: () => Navigator.pop(c, 'share'),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.downloadSimple),
            title: const Text('Save to device…'),
            subtitle: const Text('Pick a folder such as Downloads'),
            onTap: () => Navigator.pop(c, 'save'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (choice == 'save') {
    final uri = await FilePicker.saveFile(fileName: name, bytes: Uint8List.fromList(bytes), mimeType: mime);
    if (uri != null) messenger.showSnackBar(SnackBar(content: Text('Saved $name')));
    return;
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mime)], subject: name));
}

Future<void> _restore(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(dialogTitle: 'Choose a Pckt backup');
  if (picked == null || !context.mounted) return;
  final json = utf8.decode(await picked.readAsBytes(), allowMalformed: true);
  final export = ref.read(dataExportProvider);
  final summary = export.inspect(json);
  if (!context.mounted) return;
  final when = summary.exportedAt == null ? '' : ' from ${DateFormat('d MMM y, h:mm a').format(summary.exportedAt!)}';
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Restore backup?'),
      content: Text(
        'This backup$when has ${summary.transactions} transactions, '
        '${summary.counts['accounts'] ?? 0} accounts and ${summary.counts['categories'] ?? 0} categories.\n\n'
        'Everything currently in Pckt on this phone will be replaced. This cannot be undone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          style: TextButton.styleFrom(foregroundColor: Palette.coral),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final restored = await export.restore(json);
  messenger.showSnackBar(SnackBar(content: Text('Restored ${restored.transactions} transactions')));
}
