part of '../database.dart';

@DriftAccessor(tables: [Risks, Assumptions, Issues, ProgramDependencies])
class RaidDao extends DatabaseAccessor<AppDatabase> with _$RaidDaoMixin {
  RaidDao(super.db);

  // ---- Risks ----

  Stream<List<Risk>> watchRisksForProject(String projectId) {
    return (select(risks)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<Risk>> getRisksForProject(String projectId) {
    return (select(risks)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Stream<List<Risk>> watchOpenRisksForProject(String projectId) {
    return (select(risks)
          ..where(
              (t) => t.projectId.equals(projectId) & t.status.equals('open'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<Risk?> getRiskById(String id) {
    return (select(risks)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertRisk(RisksCompanion entry) {
    return into(risks).insert(entry);
  }

  Future<bool> updateRisk(RisksCompanion entry) {
    return update(risks).replace(entry);
  }

  Future<int> deleteRisk(String id) {
    return (delete(risks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertRisk(RisksCompanion entry) {
    return into(risks).insertOnConflictUpdate(entry);
  }

  // ---- Assumptions ----

  Stream<List<Assumption>> watchAssumptionsForProject(String projectId) {
    return (select(assumptions)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<Assumption>> getAssumptionsForProject(String projectId) {
    return (select(assumptions)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<Assumption?> getAssumptionById(String id) {
    return (select(assumptions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertAssumption(AssumptionsCompanion entry) {
    return into(assumptions).insert(entry);
  }

  Future<bool> updateAssumption(AssumptionsCompanion entry) {
    return update(assumptions).replace(entry);
  }

  Future<int> deleteAssumption(String id) {
    return (delete(assumptions)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertAssumption(AssumptionsCompanion entry) {
    return into(assumptions).insertOnConflictUpdate(entry);
  }

  // ---- Issues ----

  Stream<List<Issue>> watchIssuesForProject(String projectId) {
    return (select(issues)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<Issue>> getIssuesForProject(String projectId) {
    return (select(issues)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Stream<List<Issue>> watchOpenIssuesForProject(String projectId) {
    return (select(issues)
          ..where(
              (t) => t.projectId.equals(projectId) & t.status.equals('open'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<Issue?> getIssueById(String id) {
    return (select(issues)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertIssue(IssuesCompanion entry) {
    return into(issues).insert(entry);
  }

  Future<bool> updateIssue(IssuesCompanion entry) {
    return update(issues).replace(entry);
  }

  Future<int> deleteIssue(String id) {
    return (delete(issues)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertIssue(IssuesCompanion entry) {
    return into(issues).insertOnConflictUpdate(entry);
  }

  // ---- ProgramDependencies ----

  Stream<List<ProgramDependency>> watchDependenciesForProject(String projectId) {
    return (select(programDependencies)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<ProgramDependency>> getDependenciesForProject(String projectId) {
    return (select(programDependencies)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<ProgramDependency?> getDependencyById(String id) {
    return (select(programDependencies)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertDependency(ProgramDependenciesCompanion entry) {
    return into(programDependencies).insert(entry);
  }

  Future<bool> updateDependency(ProgramDependenciesCompanion entry) {
    return update(programDependencies).replace(entry);
  }

  Future<int> deleteDependency(String id) {
    return (delete(programDependencies)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertDependency(ProgramDependenciesCompanion entry) {
    return into(programDependencies).insertOnConflictUpdate(entry);
  }
}
