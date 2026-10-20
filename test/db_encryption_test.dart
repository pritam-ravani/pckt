import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/core/secrets.dart';
import 'package:pckt/data/db/database.dart';
import 'package:pckt/data/db/db_encryption.dart';
import 'package:sqlite3/sqlite3.dart';

/// In-memory stand-in for the keystore.
class MemorySecretStore extends SecretStore {
  MemorySecretStore({this.dropWrites = false});
  final bool dropWrites;
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (dropWrites) return;
    value == null || value.isEmpty ? values.remove(key) : values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

Future<T> inline<T>(T Function() work) async => work();

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pckt_db_');
    path = '${dir.path}${Platform.pathSeparator}pckt.sqlite';
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A plaintext database shaped like an old install.
  void makePlaintext({int messages = 1600}) {
    final db = sqlite3.open(path);
    db.execute('CREATE TABLE raw_messages (id INTEGER PRIMARY KEY, body TEXT NOT NULL)');
    db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY, amount_minor INTEGER)');
    db.execute('CREATE INDEX idx_amount ON transactions (amount_minor)');
    final insert = db.prepare('INSERT INTO raw_messages (body) VALUES (?)');
    db.execute('BEGIN');
    for (var i = 0; i < messages; i++) {
      insert.execute(['Rs.$i debited from A/c XX1234 via UPI']);
    }
    db.execute('COMMIT');
    insert.close();
    db.execute('INSERT INTO transactions (amount_minor) VALUES (12300), (4500)');
    db.execute('PRAGMA user_version = 2');
    db.close();
  }

  test('the test VM links SQLCipher (pubspec hooks user_defines)', () {
    expect(cipherVersion(), isNotNull);
  });

  group('keys', () {
    test('256-bit hex, random, validated', () {
      final a = generateDbKey(), b = generateDbKey();
      expect(isValidDbKey(a), isTrue);
      expect(a, hasLength(64));
      expect(a, isNot(b));
      expect(generateDbKey(Random(1)), generateDbKey(Random(1)));
      expect(isValidDbKey('abc'), isFalse);
      expect(isValidDbKey(null), isFalse);
      expect(isValidDbKey('G' * 64), isFalse);
      expect(rawKeyLiteral('a' * 64), "\"x'${'a' * 64}'\"");
      expect(() => rawKeyLiteral("'; DROP TABLE x; --"), throwsArgumentError);
    });

    test('created once, then reused', () async {
      final store = MemorySecretStore();
      final k1 = await obtainDbKey(store);
      final k2 = await obtainDbKey(store);
      expect(k1, k2);
      expect(store.values[DbEncryption.secretKey], k1);
    });

    test('a key the keystore did not keep is never used', () async {
      expect(() => obtainDbKey(MemorySecretStore(dropWrites: true)), throwsStateError);
    });

    test('malformed stored key is replaced', () async {
      final store = MemorySecretStore()..values[DbEncryption.secretKey] = 'nope';
      expect(isValidDbKey(await obtainDbKey(store)), isTrue);
    });
  });

  group('detection', () {
    test('missing, empty, plaintext, encrypted', () {
      expect(detectDbFile(path), DbFileKind.missing);
      File(path).writeAsBytesSync([]);
      expect(detectDbFile(path), DbFileKind.missing);
      File(path).deleteSync();
      makePlaintext(messages: 3);
      expect(detectDbFile(path), DbFileKind.plaintext);
      expect(migratePlaintextDb(path, generateDbKey()).ok, isTrue);
      expect(detectDbFile(path), DbFileKind.encrypted);
    });
  });

  group('migration', () {
    test('plaintext → encrypted keeps every row and deletes the plaintext copy', () {
      makePlaintext();
      final key = generateDbKey();
      final r = migratePlaintextDb(path, key);
      expect(r.ok, isTrue, reason: r.log.join('\n'));
      expect(r.counts, {'raw_messages': 1600, 'transactions': 2});
      expect(detectDbFile(path), DbFileKind.encrypted);
      expect(File('$path.plain-bak').existsSync(), isFalse);
      expect(File('$path.enc-tmp').existsSync(), isFalse);

      final db = sqlite3.open(path)..execute('PRAGMA key = ${rawKeyLiteral(key)}');
      expect(db.select('SELECT count(*) AS n FROM raw_messages').first['n'], 1600);
      expect(db.select('PRAGMA user_version').first.values.first, 2);
      expect(db.select("SELECT count(*) AS n FROM sqlite_master WHERE name = 'idx_amount'").first['n'], 1);
      db.close();

      expect(canOpenWithKey(path, key), isTrue);
      expect(canOpenWithKey(path, generateDbKey()), isFalse);
      // Without a key it is not a database at all.
      final noKey = sqlite3.open(path);
      expect(() => noKey.select('SELECT count(*) FROM sqlite_master'), throwsA(isA<SqliteException>()));
      noKey.close();
      // The plaintext text is gone from disk.
      expect(String.fromCharCodes(File(path).readAsBytesSync()).contains('debited from'), isFalse);
    });

    test('a failed export leaves the plaintext database untouched', () {
      makePlaintext(messages: 10);
      final before = File(path).readAsBytesSync();
      // A directory where the encrypted copy should go makes ATTACH fail.
      Directory('$path.enc-tmp').createSync();
      final r = migratePlaintextDb(path, generateDbKey());
      expect(r.ok, isFalse);
      expect(detectDbFile(path), DbFileKind.plaintext);
      expect(File(path).readAsBytesSync(), before);
      final db = sqlite3.open(path);
      expect(db.select('SELECT count(*) AS n FROM raw_messages').first['n'], 10);
      db.close();
    });

    test('an interrupted swap restores the plaintext backup', () {
      makePlaintext(messages: 5);
      File(path).renameSync('$path.plain-bak');
      recoverInterruptedSwap(path);
      expect(detectDbFile(path), DbFileKind.plaintext);
      expect(File('$path.plain-bak').existsSync(), isFalse);
    });
  });

  group('prepareDatabase decision', () {
    test('fresh install → new key, encrypted', () async {
      final store = MemorySecretStore();
      final plan = await prepareDatabase(path, store, run: inline);
      expect(plan.key, isNotNull);
      expect(plan.key, store.values[DbEncryption.secretKey]);
      expect(plan.status.encrypted, isTrue);
    });

    test('old plaintext install → migrated with the stored key; next start just opens', () async {
      makePlaintext(messages: 50);
      final store = MemorySecretStore();
      final plan = await prepareDatabase(path, store, run: inline);
      expect(plan.status.encrypted, isTrue, reason: plan.status.detail);
      expect(detectDbFile(path), DbFileKind.encrypted);
      expect(canOpenWithKey(path, store.values[DbEncryption.secretKey]!), isTrue);

      final again = await prepareDatabase(path, store, run: inline);
      expect(again.key, plan.key);
      expect(again.status.detail, 'Encrypted');
    });

    test('keystore failure → stays plaintext, nothing touched', () async {
      makePlaintext(messages: 5);
      final plan = await prepareDatabase(path, MemorySecretStore(dropWrites: true), run: inline);
      expect(plan.key, isNull);
      expect(plan.status.encrypted, isFalse);
      expect(detectDbFile(path), DbFileKind.plaintext);
    });

    test('encrypted file whose key is gone is set aside, not deleted', () async {
      makePlaintext(messages: 5);
      expect(migratePlaintextDb(path, generateDbKey()).ok, isTrue);
      final store = MemorySecretStore();
      final plan = await prepareDatabase(path, store, run: inline);
      expect(plan.key, isNotNull);
      expect(detectDbFile(path), DbFileKind.missing);
      expect(dir.listSync().where((f) => f.path.contains('.unreadable-')), hasLength(1));
    });
  });

  test('AppDatabase works end to end on the encrypted connection', () async {
    makePlaintext(messages: 0);
    File(path).deleteSync(); // a fresh install
    final store = MemorySecretStore();
    final db = AppDatabase(openAppDatabase(secrets: store, directory: () async => dir.path));
    expect((await db.allCategories()).isNotEmpty, isTrue);
    await db.addManual(amountMinor: 1000, direction: TxnDirection.debit, at: DateTime(2026));
    await db.close();
    expect(detectDbFile(path), DbFileKind.encrypted);
    expect(DbEncryption.status.value.encrypted, isTrue);

    final reopened = AppDatabase(openAppDatabase(secrets: store, directory: () async => dir.path));
    expect(await reopened.select(reopened.transactions).get(), hasLength(1));
    await reopened.close();
  });

  test('a real plaintext app database migrates on open (helper isolate) and keeps its data', () async {
    final plain = AppDatabase(NativeDatabase(File(path)));
    for (var i = 0; i < 25; i++) {
      await plain.addManual(
        amountMinor: 100 + i,
        direction: TxnDirection.debit,
        at: DateTime(2026, 10, 1),
        merchant: 'M$i',
      );
    }
    final cats = (await plain.allCategories()).length;
    await plain.close();
    expect(detectDbFile(path), DbFileKind.plaintext);

    final db = AppDatabase(openAppDatabase(secrets: MemorySecretStore(), directory: () async => dir.path));
    expect(await db.select(db.transactions).get(), hasLength(25));
    expect(await db.select(db.rawMessages).get(), hasLength(25));
    expect(await db.allCategories(), hasLength(cats));
    await db.close();
    expect(detectDbFile(path), DbFileKind.encrypted);
    expect(DbEncryption.status.value.detail, contains('migrated'));
    final leftovers = dir.listSync().map((f) => f.path).where((p) => p.contains('plain-bak') || p.contains('enc-tmp'));
    expect(leftovers, isEmpty);
  });
}
