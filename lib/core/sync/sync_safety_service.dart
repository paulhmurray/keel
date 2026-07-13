import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../export/json_exporter.dart';
import '_sync_safety_io.dart' if (dart.library.html) '_sync_safety_web.dart';

/// Safety nets around the destructive clear-and-reimport that a pull (or
/// manual JSON import) performs. Two layers with different guarantees:
///
/// 1. [backupDatabase] — whole-DB `VACUUM INTO` snapshot, rotating. This
///    is best-effort defence-in-depth: a failed backup logs and never
///    blocks the operation.
/// 2. [saveConflictSnapshot] — a plain JSON export of the project about to
///    be overwritten. This is the HARD guarantee for unpushed local edits:
///    it throws on failure, and callers must abort the import when it does.
class SyncSafetyService {
  /// How many rotating whole-DB backups to keep.
  static const backupKeepCount = 5;

  static String _stamp() =>
      DateTime.now().toIso8601String().split('.').first.replaceAll(':', '-');

  /// Snapshots the whole database before a destructive operation.
  /// [reason] lands in the filename (`keel-<reason>-<timestamp>.db`).
  /// Returns the backup path, or null on web / failure.
  static Future<String?> backupDatabase(AppDatabase db,
      {String reason = 'pre-pull'}) async {
    try {
      return await vacuumIntoBackup(
          db, 'keel-$reason-${_stamp()}.db', backupKeepCount);
    } catch (e) {
      debugPrint('SyncSafetyService: database backup failed: $e');
      return null;
    }
  }

  /// Exports the current LOCAL state of [projectId] to a JSON snapshot the
  /// user can restore via Settings → Data → Import. Called when a pull is
  /// about to overwrite unpushed local edits with a newer server blob.
  ///
  /// Throws when the snapshot can't be written — the caller must then
  /// abort the import, because proceeding would destroy the only copy of
  /// those edits.
  static Future<String> saveConflictSnapshot(
      AppDatabase db, String projectId) async {
    final json = await JsonExporter.exportProjectToString(
        projectId: projectId, db: db);
    final project = await db.projectDao.getProjectById(projectId);
    final safeName = (project?.name ?? projectId)
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]+'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final name = safeName.isEmpty ? projectId : safeName;
    return writeSnapshotFile(json, '$name-${_stamp()}.json');
  }
}
