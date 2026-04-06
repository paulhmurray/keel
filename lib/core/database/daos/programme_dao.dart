part of '../database.dart';

@DriftAccessor(tables: [ProgrammeOverviews, Workstreams, GovernanceCadences])
class ProgrammeDao extends DatabaseAccessor<AppDatabase>
    with _$ProgrammeDaoMixin {
  ProgrammeDao(super.db);

  // ---- ProgrammeOverview ----

  Stream<ProgrammeOverview?> watchOverviewForProject(String projectId) {
    return (select(programmeOverviews)
          ..where((t) => t.projectId.equals(projectId)))
        .watchSingleOrNull();
  }

  Future<ProgrammeOverview?> getOverviewForProject(String projectId) {
    return (select(programmeOverviews)
          ..where((t) => t.projectId.equals(projectId)))
        .getSingleOrNull();
  }

  Future<void> upsertOverview(ProgrammeOverviewsCompanion entry) {
    return into(programmeOverviews).insertOnConflictUpdate(entry);
  }

  Future<int> deleteOverview(String id) {
    return (delete(programmeOverviews)..where((t) => t.id.equals(id))).go();
  }

  // ---- Workstreams ----

  Stream<List<Workstream>> watchWorkstreamsForProject(String projectId) {
    return (select(workstreams)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<List<Workstream>> getWorkstreamsForProject(String projectId) {
    return (select(workstreams)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<Workstream?> getWorkstreamById(String id) {
    return (select(workstreams)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertWorkstream(WorkstreamsCompanion entry) {
    return into(workstreams).insert(entry);
  }

  Future<bool> updateWorkstream(WorkstreamsCompanion entry) {
    return update(workstreams).replace(entry);
  }

  Future<int> deleteWorkstream(String id) {
    return (delete(workstreams)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertWorkstream(WorkstreamsCompanion entry) {
    return into(workstreams).insertOnConflictUpdate(entry);
  }

  // ---- GovernanceCadences ----

  Stream<List<GovernanceCadence>> watchGovernanceForProject(String projectId) {
    return (select(governanceCadences)
          ..where((t) => t.projectId.equals(projectId)))
        .watch();
  }

  Future<List<GovernanceCadence>> getGovernanceForProject(String projectId) {
    return (select(governanceCadences)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
  }

  Future<GovernanceCadence?> getGovernanceById(String id) {
    return (select(governanceCadences)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertGovernance(GovernanceCadencesCompanion entry) {
    return into(governanceCadences).insert(entry);
  }

  Future<bool> updateGovernance(GovernanceCadencesCompanion entry) {
    return update(governanceCadences).replace(entry);
  }

  Future<int> deleteGovernance(String id) {
    return (delete(governanceCadences)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertGovernance(GovernanceCadencesCompanion entry) {
    return into(governanceCadences).insertOnConflictUpdate(entry);
  }
}
