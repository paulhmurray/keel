import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/sync/sync_table_registry.dart';

/// Tripwire for the "new table silently doesn't sync" bug class: every
/// table in the schema must be explicitly classified as synced or
/// local-only in sync_table_registry.dart. Adding a table to database.dart
/// without deciding its sync fate fails this test — and the registry's doc
/// comment tells you the three places a synced table must be wired into.
void main() {
  test('every schema table is classified as synced or local-only', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final schemaTables =
        db.allTables.map((t) => t.actualTableName).toSet();
    final classified = {...syncedTables, ...localOnlyTables};

    expect(
      schemaTables.difference(classified),
      isEmpty,
      reason: 'Unclassified table(s) — decide whether they sync and add '
          'them to sync_table_registry.dart (synced tables must also be '
          'wired into JsonExporter, JsonImporter._import and '
          '_clearSyncedTables).',
    );
    expect(
      classified.difference(schemaTables),
      isEmpty,
      reason: 'Registry lists table(s) that no longer exist in the schema — '
          'remove them from sync_table_registry.dart.',
    );
    expect(
      syncedTables.intersection(localOnlyTables),
      isEmpty,
      reason: 'A table cannot be both synced and local-only.',
    );
  });
}
