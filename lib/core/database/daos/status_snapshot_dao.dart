part of '../database.dart';

@DriftAccessor(tables: [StatusSnapshots])
class StatusSnapshotDao extends DatabaseAccessor<AppDatabase>
    with _$StatusSnapshotDaoMixin {
  StatusSnapshotDao(super.db);

  Stream<List<StatusSnapshot>> watchForProject(String projectId) =>
      (select(statusSnapshots)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.desc(t.weekEnding)]))
          .watch();

  Future<List<StatusSnapshot>> getForProject(String projectId) =>
      (select(statusSnapshots)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.desc(t.weekEnding)]))
          .get();

  Future<StatusSnapshot?> getMostRecent(String projectId) =>
      (select(statusSnapshots)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.desc(t.weekEnding)])
            ..limit(1))
          .getSingleOrNull();

  Future<void> insert(StatusSnapshotsCompanion entry) =>
      into(statusSnapshots).insertOnConflictUpdate(entry);

  Future<void> deleteSnapshot(String id) =>
      (delete(statusSnapshots)..where((t) => t.id.equals(id))).go();
}
