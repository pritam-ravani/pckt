import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../core/secrets.dart';

/// Encryption at rest for the app database (SQLCipher, selected through the
/// `hooks: user_defines: sqlite3: source: sqlcipher` entry in pubspec.yaml).
///
/// * A random 256-bit key is generated on first run and kept in the platform
///   keystore through [SecretStore]. It is used as a raw key
///   (`PRAGMA key = "x'…'"`), so opening skips SQLCipher's PBKDF2 pass.
/// * A plaintext database from an older install is converted once:
///   `sqlcipher_export` into a sibling file, row counts verified, files
///   swapped by rename, verified again, and only then is the plaintext copy
///   deleted. Any failure keeps the app on the plaintext file (and it tries
///   again on the next start).
///
/// Every step logs with the `[pckt-db]` tag (logcat: `flutter` tag).
abstract final class DbEncryption {
  static const secretKey = 'db.key.v1';
  static const fileName = 'pckt.sqlite';

  /// What the last open decided, for Settings.
  static final status = ValueNotifier<DbSecurityStatus>(const DbSecurityStatus.unknown());
}

class DbSecurityStatus {
  const DbSecurityStatus({required this.encrypted, required this.detail, this.cipherVersion});
  const DbSecurityStatus.unknown() : encrypted = false, detail = 'Opening…', cipherVersion = null;

  final bool encrypted;
  final String detail;
  final String? cipherVersion;
}

void dbLog(String message) => debugPrint('[pckt-db] $message');

// ------------------------------------------------------------------ keys

/// 32 random bytes as 64 lowercase hex chars.
String generateDbKey([Random? random]) {
  final r = random ?? Random.secure();
  return [for (var i = 0; i < 32; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
}

bool isValidDbKey(String? key) => key != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(key);

/// SQL literal for a raw SQLCipher key: `"x'…'"`.
String rawKeyLiteral(String hexKey) {
  if (!isValidDbKey(hexKey)) throw ArgumentError('not a 256-bit hex key');
  return "\"x'$hexKey'\"";
}

/// Reads the key, or creates and stores one. The new key is read back before
/// it is used — encrypting with a key the keystore silently dropped would
/// lose the data on the next start.
Future<String> obtainDbKey(SecretStore secrets, {bool create = true}) async {
  final existing = await secrets.read(DbEncryption.secretKey);
  if (isValidDbKey(existing)) return existing!;
  if (existing != null && existing.isNotEmpty) dbLog('stored key is malformed; ignoring it');
  if (!create) throw StateError('no database key');
  final key = generateDbKey();
  await secrets.write(DbEncryption.secretKey, key);
  final back = await secrets.read(DbEncryption.secretKey);
  if (back != key) throw StateError('database key did not persist in the keystore');
  dbLog('generated a new database key');
  return key;
}

// ------------------------------------------------------------------ files

enum DbFileKind { missing, plaintext, encrypted }

const _sqliteHeader = 'SQLite format 3\u0000';

DbFileKind detectDbFile(String path) {
  final f = File(path);
  if (!f.existsSync() || f.lengthSync() == 0) return DbFileKind.missing;
  final raf = f.openSync();
  try {
    final header = raf.readSync(16);
    return header.length == 16 && latin1.decode(header) == _sqliteHeader ? DbFileKind.plaintext : DbFileKind.encrypted;
  } finally {
    raf.closeSync();
  }
}

String _tmpPath(String path) => '$path.enc-tmp';
String _backupPath(String path) => '$path.plain-bak';

void _deleteQuietly(String path) {
  for (final suffix in const ['', '-journal', '-wal', '-shm']) {
    final f = File('$path$suffix');
    if (f.existsSync()) f.deleteSync();
  }
}

bool _hasHotJournal(String path) =>
    ['-journal', '-wal'].any((s) => File('$path$s').existsSync() && File('$path$s').lengthSync() > 0);

/// A start that was killed between the two renames of a migration leaves no
/// database but a plaintext backup: put the backup back.
void recoverInterruptedSwap(String path) {
  final bak = File(_backupPath(path));
  if (!bak.existsSync()) return;
  if (detectDbFile(path) == DbFileKind.missing) {
    dbLog('recovering: restoring plaintext backup left by an interrupted migration');
    _deleteQuietly(path);
    bak.renameSync(path);
  }
}

// --------------------------------------------------------------- sqlite work

/// `PRAGMA cipher_version`, or null when the linked SQLite is not SQLCipher.
String? cipherVersion() {
  final db = sqlite3.openInMemory();
  try {
    final rows = db.select('PRAGMA cipher_version');
    final v = rows.isEmpty ? null : rows.first.values.first?.toString();
    return v == null || v.isEmpty ? null : v;
  } finally {
    db.close();
  }
}

Map<String, int> _tableCounts(Database db, [String schema = 'main']) {
  final tables = db
      .select("SELECT name FROM $schema.sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
      .map((r) => r['name'] as String)
      .toList();
  return {
    for (final t in tables)
      t: db.select('SELECT count(*) AS n FROM $schema."${t.replaceAll('"', '""')}"').first['n'] as int,
  };
}

int _userVersion(Database db) => db.select('PRAGMA user_version').first.values.first as int;

Database _openEncrypted(String path, String hexKey, {OpenMode mode = OpenMode.readWrite}) {
  final db = sqlite3.open(path, mode: mode);
  try {
    db.execute('PRAGMA key = ${rawKeyLiteral(hexKey)}');
    // Fails with "file is not a database" on a wrong key.
    db.select('SELECT count(*) FROM sqlite_master');
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

/// True when [path] opens with [hexKey].
bool canOpenWithKey(String path, String hexKey) {
  try {
    _openEncrypted(path, hexKey, mode: OpenMode.readOnly).close();
    return true;
  } catch (_) {
    return false;
  }
}

class MigrationResult {
  const MigrationResult({required this.ok, required this.log, this.counts = const {}, this.error});
  final bool ok;
  final List<String> log;
  final Map<String, int> counts;
  final String? error;

  int get rows => counts.values.fold(0, (a, b) => a + b);
}

class _Abort implements Exception {
  _Abort(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Converts the plaintext database at [path] to SQLCipher in place.
/// Synchronous and blocking — run it off the UI isolate. On failure the
/// plaintext file is untouched (or restored) and `ok` is false.
MigrationResult migratePlaintextDb(String path, String hexKey) {
  final log = <String>[];
  void note(String m) {
    log.add(m);
    dbLog('migrate: $m');
  }

  final tmp = _tmpPath(path);
  final bak = _backupPath(path);
  final sw = Stopwatch()..start();
  var swapped = false;
  try {
    final cipher = cipherVersion();
    if (cipher == null) throw _Abort('the linked SQLite is not SQLCipher');
    note('SQLCipher $cipher; source ${File(path).lengthSync()} bytes');
    _deleteQuietly(tmp);

    final Map<String, int> before;
    final int version;
    final plain = sqlite3.open(path);
    try {
      plain.execute('PRAGMA temp_store = MEMORY');
      // No-op unless the file is in WAL mode; folds pending pages back in.
      plain.select('PRAGMA wal_checkpoint(TRUNCATE)');
      final check = plain.select('PRAGMA quick_check').first.values.first;
      if (check != 'ok') throw _Abort('plaintext quick_check: $check');
      before = _tableCounts(plain);
      version = _userVersion(plain);
      note('source: user_version $version, ${before.length} tables, ${before.values.fold(0, (a, b) => a + b)} rows $before');

      plain.execute("ATTACH DATABASE '${tmp.replaceAll("'", "''")}' AS encrypted KEY ${rawKeyLiteral(hexKey)}");
      plain.select("SELECT sqlcipher_export('encrypted')");
      plain.execute('PRAGMA encrypted.user_version = $version');
      final exported = _tableCounts(plain, 'encrypted');
      plain.execute('DETACH DATABASE encrypted');
      if (!mapEquals(exported, before)) throw _Abort('export counts differ: $exported');
    } finally {
      plain.close();
    }

    if (detectDbFile(tmp) != DbFileKind.encrypted) throw _Abort('export is not encrypted');
    final enc = _openEncrypted(tmp, hexKey);
    try {
      final after = _tableCounts(enc);
      if (!mapEquals(after, before)) throw _Abort('encrypted copy counts differ: $after');
      if (_userVersion(enc) != version) throw _Abort('user_version differs');
      final check = enc.select('PRAGMA quick_check').first.values.first;
      if (check != 'ok') throw _Abort('encrypted quick_check: $check');
      final cipherCheck = enc.select('PRAGMA cipher_integrity_check');
      if (cipherCheck.isNotEmpty) throw _Abort('cipher_integrity_check: ${cipherCheck.first.values}');
    } finally {
      enc.close();
    }
    note('encrypted copy verified (${File(tmp).lengthSync()} bytes)');

    if (_hasHotJournal(path)) throw _Abort('plaintext database still has a journal; not swapping');
    for (final s in const ['-shm']) {
      final f = File('$path$s');
      if (f.existsSync()) f.deleteSync();
    }
    _deleteQuietly(bak);
    File(path).renameSync(bak);
    swapped = true;
    File(tmp).renameSync(path);
    note('files swapped');

    final reopened = _openEncrypted(path, hexKey);
    try {
      final final_ = _tableCounts(reopened);
      if (!mapEquals(final_, before)) throw _Abort('swapped database counts differ: $final_');
    } finally {
      reopened.close();
    }
    _deleteQuietly(bak);
    note('done in ${sw.elapsedMilliseconds} ms; plaintext copy deleted');
    return MigrationResult(ok: true, log: log, counts: before);
  } catch (e) {
    note('FAILED: $e — staying on the plaintext database');
    try {
      if (swapped) {
        // Put the plaintext file back where the app expects it.
        if (File(path).existsSync()) {
          _deleteQuietly('$path.enc-failed');
          File(path).renameSync('$path.enc-failed');
        }
        File(bak).renameSync(path);
        note('rolled back to the plaintext file');
      }
      _deleteQuietly(tmp);
    } catch (e2) {
      note('cleanup after failure: $e2');
    }
    return MigrationResult(ok: false, log: log, error: '$e');
  }
}

// ------------------------------------------------------------------ open

/// The decision for one start: which file, and the key (null = plaintext).
class DbOpenPlan {
  const DbOpenPlan(this.path, this.key, this.status);
  final String path;
  final String? key;
  final DbSecurityStatus status;
}

/// Runs blocking sqlite work on a helper isolate (inline in tests).
typedef BlockingRunner = Future<T> Function<T>(T Function() work);

Future<T> _isolateRunner<T>(T Function() work) => Isolate.run(work);

// Closures built here capture only their arguments, so they can be sent to
// the helper isolate (a closure made inside prepareDatabase would drag its
// whole scope, keystore plugin included, along).
bool Function() _canOpenTask(String path, String key) => () => canOpenWithKey(path, key);
MigrationResult Function() _migrateTask(String path, String key) => () => migratePlaintextDb(path, key);

/// Decides how to open [path]: creates / validates the key and migrates a
/// plaintext file. Never throws for encryption problems — the worst case is
/// the plaintext database with a log line.
Future<DbOpenPlan> prepareDatabase(String path, SecretStore secrets, {BlockingRunner run = _isolateRunner}) async {
  recoverInterruptedSwap(path);
  final cipher = await run(cipherVersion);
  final kind = detectDbFile(path);
  dbLog('open: $kind file, SQLCipher ${cipher ?? 'NOT linked'}');

  if (cipher == null) {
    if (kind == DbFileKind.encrypted) {
      // Should never happen (the build always links SQLCipher), and there is
      // no way to read the file without it.
      throw StateError('Database is encrypted but SQLCipher is not available');
    }
    return DbOpenPlan(path, null, const DbSecurityStatus(encrypted: false, detail: 'SQLCipher is not available'));
  }

  String? key;
  try {
    key = await obtainDbKey(secrets, create: kind != DbFileKind.encrypted);
  } catch (e) {
    dbLog('key unavailable: $e');
  }

  switch (kind) {
    case DbFileKind.missing:
      if (key == null) {
        return DbOpenPlan(path, null, const DbSecurityStatus(encrypted: false, detail: 'Keystore unavailable'));
      }
      _deleteQuietly(_tmpPath(path));
      dbLog('open: new encrypted database');
      return DbOpenPlan(path, key, DbSecurityStatus(encrypted: true, detail: 'Encrypted', cipherVersion: cipher));

    case DbFileKind.encrypted:
      if (key != null && await run(_canOpenTask(path, key))) {
        _deleteQuietly(_tmpPath(path));
        if (File(_backupPath(path)).existsSync()) {
          dbLog('open: removing plaintext backup from an earlier verified migration');
          _deleteQuietly(_backupPath(path));
        }
        return DbOpenPlan(path, key, DbSecurityStatus(encrypted: true, detail: 'Encrypted', cipherVersion: cipher));
      }
      // The keystore lost the key (e.g. data restored onto a new phone).
      // The file can't be read; keep it aside rather than deleting it, and
      // start a fresh encrypted database.
      final aside = '$path.unreadable-${DateTime.now().millisecondsSinceEpoch}';
      dbLog('open: ERROR encrypted database does not open with the stored key (key ${key == null ? 'missing' : 'present'}); moved to $aside');
      File(path).renameSync(aside);
      for (final s in const ['-journal', '-wal', '-shm']) {
        if (File('$path$s').existsSync()) File('$path$s').renameSync('$aside$s');
      }
      await secrets.delete(DbEncryption.secretKey);
      final fresh = await obtainDbKey(secrets);
      return DbOpenPlan(
        path,
        fresh,
        DbSecurityStatus(
          encrypted: true,
          detail: 'Encrypted · the previous database could not be unlocked and was set aside',
          cipherVersion: cipher,
        ),
      );

    case DbFileKind.plaintext:
      if (key == null) {
        return DbOpenPlan(path, null, const DbSecurityStatus(encrypted: false, detail: 'Keystore unavailable'));
      }
      final k = key;
      final result = await run(_migrateTask(path, k));
      if (!result.ok) {
        return DbOpenPlan(
          path,
          null,
          DbSecurityStatus(encrypted: false, detail: 'Not encrypted yet — will retry (${result.error})'),
        );
      }
      return DbOpenPlan(
        path,
        key,
        DbSecurityStatus(encrypted: true, detail: 'Encrypted (migrated ${result.rows} rows)', cipherVersion: cipher),
      );
  }
}

/// The app's database connection: `pckt.sqlite` in the documents directory
/// (same file drift_flutter used), opened with the SQLCipher key on a
/// background isolate.
DatabaseConnection openAppDatabase({SecretStore? secrets, Future<String> Function()? directory}) {
  return DatabaseConnection.delayed(
    Future(() async {
      final dir = directory != null ? await directory() : (await getApplicationDocumentsDirectory()).path;
      try {
        // Android has no /tmp; temp files (big sorts) go to the cache dir.
        sqlite3.tempDirectory = (await getTemporaryDirectory()).path;
      } catch (_) {}
      final path = p.join(dir, DbEncryption.fileName);
      final sw = Stopwatch()..start();
      final plan = await prepareDatabase(path, secrets ?? SecretStore());
      DbEncryption.status.value = plan.status;
      dbLog('open: ${plan.key == null ? 'PLAINTEXT' : 'encrypted'} — ${plan.status.detail} (${sw.elapsedMilliseconds} ms)');
      final key = plan.key;
      return NativeDatabase.createBackgroundConnection(
        File(path),
        setup: key == null
            ? null
            : (db) {
                db.execute('PRAGMA key = ${rawKeyLiteral(key)}');
                db.select('SELECT count(*) FROM sqlite_master');
              },
      );
    }),
  );
}
