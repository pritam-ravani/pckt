import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pckt/data/db/database.dart';

import 'generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the current schema version has a snapshot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final file = File('drift_schemas/drift_schema_v${db.schemaVersion}.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Bumped schemaVersion? Dump a snapshot: see "Schema migrations" in ARCHITECTURE.md.',
    );
  });

  test('a database at the v4 baseline matches the current schema', () async {
    final schema = await verifier.schemaAt(4);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);
  });

  test('upgrading from v5 adds the new categories without duplicating any', () async {
    final schema = await verifier.schemaAt(5);
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, db.schemaVersion);
    final names = (await db.allCategories()).map((c) => c.name).toList();
    expect(names, containsAll(['Food Delivery', 'Tiffin & Mess', 'Cab & Auto', 'Family Support', 'Bonus']));
    expect(names.toSet(), hasLength(names.length));
  });
}
