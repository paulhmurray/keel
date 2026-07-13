import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
// The io impl exposes the test dir hook (path_provider has no platform
// channel under flutter_test).
import 'package:keel/core/sync/_sync_safety_io.dart'
    show debugSafetyBaseDirOverride;
import 'package:keel/core/sync/sync_safety_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late AppDatabase db;
  late Directory baseDir;

  setUp(() async {
    db = AppDatabase.memory();
    baseDir = await Directory.systemTemp.createTemp('keel_safety_test');
    debugSafetyBaseDirOverride = baseDir;
  });

  tearDown(() async {
    debugSafetyBaseDirOverride = null;
    await db.close();
    baseDir.deleteSync(recursive: true);
  });

  Future<void> seedProject(String id, String name) =>
      db.projectDao.upsertProject(ProjectsCompanion(
        id: Value(id),
        name: Value(name),
      ));

  group('backupDatabase', () {
    test('VACUUM INTO produces an openable backup containing the data',
        () async {
      await seedProject('p-1', 'Backed Up');

      final path = await SyncSafetyService.backupDatabase(db);

      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      // The backup is a real SQLite DB with the row in it.
      final raw = sqlite3.open(path);
      final rows = raw.select('SELECT name FROM projects WHERE id = ?', ['p-1']);
      expect(rows.single['name'], 'Backed Up');
      raw.dispose();
    });

    test('rotates down to backupKeepCount', () async {
      await seedProject('p-1', 'P');
      final backupsDir = Directory('${baseDir.path}/backups');

      for (var i = 0; i < SyncSafetyService.backupKeepCount + 3; i++) {
        // Distinct filenames: the timestamp only has second precision, so
        // pre-plant differing names via the reason.
        await SyncSafetyService.backupDatabase(db, reason: 'test-$i');
      }

      final backups = backupsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();
      expect(backups.length, SyncSafetyService.backupKeepCount);
    });
  });

  group('saveConflictSnapshot', () {
    test('writes a restorable JSON export of the project', () async {
      await seedProject('p-1', 'My Project');

      final path = await SyncSafetyService.saveConflictSnapshot(db, 'p-1');

      final content = File(path).readAsStringSync();
      expect(content, contains('"My Project"'));
      expect(path, contains('conflict-snapshots'));
      expect(path, endsWith('.json'));
      // Filename derived from the project name, sanitized.
      expect(path, contains('My_Project'));
    });
  });
}
