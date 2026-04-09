part of '../database.dart';

@DriftAccessor(tables: [Workstreams, WorkstreamLinks])
class WorkstreamsDao extends DatabaseAccessor<AppDatabase>
    with _$WorkstreamsDaoMixin {
  WorkstreamsDao(super.db);

  Stream<List<Workstream>> watchForProject(String projectId) {
    return (select(workstreams)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.lane),
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Future<List<Workstream>> getForProject(String projectId) {
    return (select(workstreams)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.lane),
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
  }

  Future<void> upsert(WorkstreamsCompanion entry) {
    return into(workstreams).insertOnConflictUpdate(entry);
  }

  Future<void> deleteWorkstream(String id) async {
    await (delete(workstreamLinks)
          ..where((t) => t.fromId.equals(id) | t.toId.equals(id)))
        .go();
    await (delete(workstreams)..where((t) => t.id.equals(id))).go();
  }

  Future<List<WorkstreamLink>> getLinksForProject(String projectId) {
    return (select(workstreamLinks)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
  }

  Future<void> upsertLink(WorkstreamLinksCompanion entry) {
    return into(workstreamLinks).insertOnConflictUpdate(entry);
  }

  Future<void> deleteLink(String id) {
    return (delete(workstreamLinks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteLinksForWorkstream(String workstreamId) {
    return (delete(workstreamLinks)
          ..where((t) =>
              t.fromId.equals(workstreamId) | t.toId.equals(workstreamId)))
        .go();
  }
}
