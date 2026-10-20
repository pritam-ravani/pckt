import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';

/// Thrown when a file is not a usable Pckt backup. [message] is user-facing.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What a validated backup contains, for the confirmation dialog.
class BackupSummary {
  const BackupSummary({required this.exportedAt, required this.schemaVersion, required this.counts});

  final DateTime? exportedAt;
  final int schemaVersion;

  /// Rows per table (SQL table name).
  final Map<String, int> counts;

  int get transactions => counts['transactions'] ?? 0;
}

/// CSV export, full JSON backup and restore.
///
/// The backup is a raw dump of every table (SQL column names and stored
/// values), so it round-trips exactly and automatically covers tables added
/// in later schema versions. Restore accepts backups from the same or an
/// older schema; unknown columns are dropped and missing ones take their
/// defaults.
class DataExport {
  DataExport(this.db);

  final AppDatabase db;

  static const format = 'pckt-backup';
  static const formatVersion = 1;

  /// Tables every backup must have; anything else is optional.
  static const requiredTables = ['accounts', 'categories', 'transactions', 'raw_messages', 'merchant_rules'];

  static const csvHeader = [
    'date',
    'amount',
    'direction',
    'merchant',
    'category',
    'account',
    'mode',
    'reference',
    'note',
    'sources',
  ];

  // ------------------------------------------------------------------ CSV

  /// All transactions, oldest first, one row each. Amounts are in rupees.
  Future<String> transactionsCsv() async {
    final cats = {for (final c in await db.allCategories()) c.id: c.name};
    final accts = {for (final a in await db.allAccounts()) a.id: a};
    final sources = <int, Set<String>>{};
    for (final m in await (db.select(db.rawMessages)..where((m) => m.transactionId.isNotNull())).get()) {
      sources.putIfAbsent(m.transactionId!, () => <String>{}).add(m.source.name);
    }
    final txns = await (db.select(
      db.transactions,
    )..orderBy([(t) => OrderingTerm(expression: t.occurredAt), (t) => OrderingTerm(expression: t.id)])).get();
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = <List<String>>[
      csvHeader,
      for (final t in txns)
        [
          fmt.format(t.occurredAt),
          (t.amountMinor / 100).toStringAsFixed(2),
          t.direction.name,
          t.merchant ?? '',
          cats[t.categoryId] ?? '',
          switch (accts[t.accountId]) {
            null => '',
            final a => a.last4 == null ? a.name : '${a.name} ••${a.last4}',
          },
          t.mode.name,
          t.reference ?? '',
          t.note ?? '',
          (sources[t.id]?.toList() ?? const <String>[]).join(';'),
        ],
    ];
    return encodeCsv(rows);
  }

  // --------------------------------------------------------------- backup

  Future<Map<String, Object?>> backup() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in db.allTables) {
      final rows = await db.customSelect('SELECT * FROM "${t.actualTableName}"', readsFrom: {t}).get();
      tables[t.actualTableName] = [
        for (final r in rows) {for (final e in r.data.entries) e.key: _encodeValue(e.value)},
      ];
    }
    return {
      'format': format,
      'formatVersion': formatVersion,
      'schemaVersion': db.schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    };
  }

  Future<String> backupJson() async => const JsonEncoder.withIndent(' ').convert(await backup());

  /// Parses and validates a backup file. Throws [BackupFormatException].
  BackupSummary inspect(String json) => _validate(_decode(json)).$2;

  /// Replaces all data with the backup's, in one DB transaction: either
  /// everything is restored or nothing changes.
  Future<BackupSummary> restore(String json) async {
    final (data, summary) = _validate(_decode(json));
    final tables = (data['tables']! as Map).cast<String, Object?>();
    await db.transaction(() async {
      // Rows are inserted parent-first, but defer FK checks to commit anyway
      // so self/forward references (raw_messages → transactions) never trip.
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final t in db.allTables.toList().reversed) {
        await db.customUpdate('DELETE FROM "${t.actualTableName}"', updates: {t}, updateKind: UpdateKind.delete);
      }
      for (final t in db.allTables) {
        final known = {for (final c in t.$columns) c.name};
        for (final row in (tables[t.actualTableName] as List?) ?? const []) {
          final entries = (row as Map).entries.where((e) => known.contains(e.key)).toList();
          if (entries.isEmpty) continue;
          await db.customInsert(
            'INSERT INTO "${t.actualTableName}" (${entries.map((e) => '"${e.key}"').join(', ')}) '
            'VALUES (${List.filled(entries.length, '?').join(', ')})',
            variables: [for (final e in entries) Variable<Object>(_decodeValue(e.value))],
            updates: {t},
          );
        }
      }
    });
    return summary;
  }

  Map<String, Object?> _decode(String json) {
    try {
      final v = jsonDecode(json);
      if (v is Map<String, Object?>) return v;
    } on FormatException {
      // fall through
    }
    throw const BackupFormatException('This file is not a Pckt backup (not valid JSON).');
  }

  (Map<String, Object?>, BackupSummary) _validate(Map<String, Object?> data) {
    if (data['format'] != format) throw const BackupFormatException('This file is not a Pckt backup.');
    final fv = data['formatVersion'];
    if (fv is! int || fv > formatVersion) {
      throw const BackupFormatException('This backup was made by a newer version of Pckt. Update the app first.');
    }
    final sv = data['schemaVersion'];
    if (sv is! int || sv < 1) throw const BackupFormatException('The backup is missing its schema version.');
    if (sv > db.schemaVersion) {
      throw const BackupFormatException('This backup was made by a newer version of Pckt. Update the app first.');
    }
    final tables = data['tables'];
    if (tables is! Map) throw const BackupFormatException('The backup has no data.');
    for (final name in requiredTables) {
      if (tables[name] is! List) throw BackupFormatException('The backup is incomplete (no "$name").');
    }
    final counts = <String, int>{};
    for (final e in tables.entries) {
      final rows = e.value;
      if (rows is! List || rows.any((r) => r is! Map)) {
        throw BackupFormatException('The backup is damaged ("${e.key}").');
      }
      counts['${e.key}'] = rows.length;
    }
    for (final t in db.allTables) {
      final rows = tables[t.actualTableName] as List?;
      if (rows == null) continue;
      final hasId = t.$columns.any((c) => c.name == 'id');
      for (final r in rows.cast<Map>()) {
        if (hasId && r['id'] is! int) throw BackupFormatException('The backup is damaged ("${t.actualTableName}").');
      }
    }
    final at = data['exportedAt'];
    return (
      data,
      BackupSummary(
        exportedAt: at is String ? DateTime.tryParse(at)?.toLocal() : null,
        schemaVersion: sv,
        counts: counts,
      ),
    );
  }

  static Object? _encodeValue(Object? v) => v is Uint8List ? {r'$b64': base64Encode(v)} : v;

  static Object? _decodeValue(Object? v) => v is Map && v[r'$b64'] is String ? base64Decode(v[r'$b64'] as String) : v;
}

// ------------------------------------------------------------------- CSV io

/// RFC 4180 CSV with CRLF line endings and a UTF-8 BOM so Excel reads ₹ and
/// non-ASCII names correctly.
String encodeCsv(List<List<String>> rows) {
  String cell(String s) =>
      RegExp(r'[",\r\n]').hasMatch(s) || s.startsWith(' ') || s.endsWith(' ') ? '"${s.replaceAll('"', '""')}"' : s;
  return '﻿${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
}

/// Inverse of [encodeCsv] (tolerates LF endings and a missing BOM).
List<List<String>> decodeCsv(String text) {
  final s = text.startsWith('﻿') ? text.substring(1) : text;
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}
