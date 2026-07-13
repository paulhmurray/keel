import '../database/database.dart';

/// Web has no filesystem: the database is in-memory per session, so there
/// is nothing durable to back up.
Future<String?> vacuumIntoBackup(AppDatabase db, String fileName, int keep) async => null;

/// Conflict snapshots can't be persisted on web. Throwing makes the pull
/// abort rather than silently import over unpushed local edits.
Future<String> writeSnapshotFile(String json, String fileName) async {
  throw UnsupportedError(
      'Conflict snapshots are not supported on web — push your local changes first.');
}
