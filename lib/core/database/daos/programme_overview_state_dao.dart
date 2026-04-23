part of '../database.dart';

@DriftAccessor(tables: [ProgrammeOverviewStates])
class ProgrammeOverviewStateDao extends DatabaseAccessor<AppDatabase>
    with _$ProgrammeOverviewStateDaoMixin {
  ProgrammeOverviewStateDao(super.db);

  Stream<ProgrammeOverviewState?> watchForProject(String projectId) =>
      (select(programmeOverviewStates)
            ..where((t) => t.projectId.equals(projectId)))
          .watchSingleOrNull();

  Future<ProgrammeOverviewState?> getForProject(String projectId) =>
      (select(programmeOverviewStates)
            ..where((t) => t.projectId.equals(projectId)))
          .getSingleOrNull();

  Future<void> upsert(ProgrammeOverviewStatesCompanion entry) =>
      into(programmeOverviewStates).insertOnConflictUpdate(entry);
}
