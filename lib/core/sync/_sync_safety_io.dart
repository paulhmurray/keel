import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../database/database.dart';

/// Test hook: unit tests point this at a temp dir because path_provider
/// has no platform channel under flutter_test.
Directory? debugSafetyBaseDirOverride;

Future<Directory> _ensureDir(String sub) async {
  final base = debugSafetyBaseDirOverride ?? await getApplicationSupportDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}$sub');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Snapshots the live SQLite database into `backups/` via `VACUUM INTO`
/// (safe on an open connection) and prunes old backups down to [keep].
/// Returns the backup file path.
Future<String?> vacuumIntoBackup(AppDatabase db, String fileName, int keep) async {
  final dir = await _ensureDir('backups');
  final path = '${dir.path}${Platform.pathSeparator}$fileName';
  await db.customStatement('VACUUM INTO ?', [path]);
  await _pruneBackups(dir, keep);
  return path;
}

Future<void> _pruneBackups(Directory dir, int keep) async {
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.db'))
      .toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  for (final old in files.skip(keep)) {
    try {
      await old.delete();
    } catch (_) {
      // A locked/vanished old backup is not worth failing the pull over.
    }
  }
}

/// Writes a project JSON snapshot into `conflict-snapshots/` and returns
/// its path. Snapshots are never auto-pruned — they hold user edits that
/// exist nowhere else until restored.
Future<String> writeSnapshotFile(String json, String fileName) async {
  final dir = await _ensureDir('conflict-snapshots');
  final path = '${dir.path}${Platform.pathSeparator}$fileName';
  await File(path).writeAsString(json, flush: true);
  return path;
}
