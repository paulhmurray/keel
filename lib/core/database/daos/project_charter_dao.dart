part of '../database.dart';

@DriftAccessor(tables: [ProjectCharters])
class ProjectCharterDao extends DatabaseAccessor<AppDatabase>
    with _$ProjectCharterDaoMixin {
  ProjectCharterDao(super.db);

  Stream<ProjectCharter?> watchForProject(String projectId) =>
      (select(projectCharters)..where((t) => t.projectId.equals(projectId)))
          .watchSingleOrNull();

  Future<ProjectCharter?> getForProject(String projectId) =>
      (select(projectCharters)..where((t) => t.projectId.equals(projectId)))
          .getSingleOrNull();

  Future<void> upsert(ProjectChartersCompanion entry) =>
      into(projectCharters).insertOnConflictUpdate(entry);
}
