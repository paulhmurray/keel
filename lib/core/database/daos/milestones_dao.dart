part of '../database.dart';

@DriftAccessor(tables: [Milestones])
class MilestonesDao extends DatabaseAccessor<AppDatabase>
    with _$MilestonesDaoMixin {
  MilestonesDao(super.db);

  Stream<List<Milestone>> watchForProject(String projectId) =>
      (select(milestones)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm(expression: t.date)]))
          .watch();

  Future<List<Milestone>> getForProject(String projectId) =>
      (select(milestones)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm(expression: t.date)]))
          .get();

  Future<void> upsert(MilestonesCompanion entry) =>
      into(milestones).insertOnConflictUpdate(entry);

  Future<void> deleteMilestone(String id) =>
      (delete(milestones)..where((t) => t.id.equals(id))).go();
}
