part of '../database.dart';

@DriftAccessor(tables: [ProjectCharters])
class ProjectCharterDao extends DatabaseAccessor<AppDatabase>
    with _$ProjectCharterDaoMixin {
  ProjectCharterDao(super.db);

  /// Watches the project's OWN charter (sourceProjectId IS NULL).
  /// Cascaded rows from linked projects sit alongside in the same
  /// table — see [watchCascadedForProgramme] for those.
  Stream<ProjectCharter?> watchForProject(String projectId) =>
      (select(projectCharters)
            ..where((t) =>
                t.projectId.equals(projectId) &
                t.sourceProjectId.isNull()))
          .watchSingleOrNull();

  Future<ProjectCharter?> getForProject(String projectId) =>
      (select(projectCharters)
            ..where((t) =>
                t.projectId.equals(projectId) &
                t.sourceProjectId.isNull()))
          .getSingleOrNull();

  /// Cascaded charters that arrived from linked projects. Used by the
  /// programme-side CharterView to render a "Linked Project Charters"
  /// section under the programme's own charter.
  Stream<List<ProjectCharter>> watchCascadedForProgramme(
          String programmeId) =>
      (select(projectCharters)
            ..where((t) =>
                t.projectId.equals(programmeId) &
                t.sourceProjectId.isNotNull())
            ..orderBy([(t) => OrderingTerm.asc(t.sourceProjectName)]))
          .watch();

  Future<void> upsert(ProjectChartersCompanion entry) =>
      into(projectCharters).insertOnConflictUpdate(entry);
}
