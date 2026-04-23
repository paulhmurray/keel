part of '../database.dart';

@DriftAccessor(tables: [WorkstreamActivities])
class WorkstreamActivitiesDao extends DatabaseAccessor<AppDatabase>
    with _$WorkstreamActivitiesDaoMixin {
  WorkstreamActivitiesDao(super.db);

  Future<List<WorkstreamActivity>> getForWorkstream(String workstreamId) =>
      (select(workstreamActivities)
            ..where((t) => t.workstreamId.equals(workstreamId))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  Future<List<WorkstreamActivity>> getForProject(String projectId) =>
      (select(workstreamActivities)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.workstreamId),
              (t) => OrderingTerm(expression: t.sortOrder),
            ]))
          .get();

  Future<void> upsert(WorkstreamActivitiesCompanion entry) =>
      into(workstreamActivities).insertOnConflictUpdate(entry);

  Future<void> deleteActivity(String id) =>
      (delete(workstreamActivities)..where((t) => t.id.equals(id))).go();

  Future<void> deleteForWorkstream(String workstreamId) =>
      (delete(workstreamActivities)
            ..where((t) => t.workstreamId.equals(workstreamId)))
          .go();
}
