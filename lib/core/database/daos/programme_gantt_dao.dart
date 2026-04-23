part of '../database.dart';

@DriftAccessor(tables: [
  TimelineWorkPackages,
  TimelineActivities,
  TimelineDependencies,
  ProgrammeHeaders,
  ProjectScopes,
  IntegrationDomains,
  PrioritisationSources,
])
class ProgrammeGanttDao extends DatabaseAccessor<AppDatabase>
    with _$ProgrammeGanttDaoMixin {
  ProgrammeGanttDao(super.db);

  // ── Work Packages ─────────────────────────────────────────────────────────

  Future<List<TimelineWorkPackage>> getWorkPackages(String projectId) =>
      (select(timelineWorkPackages)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  Stream<List<TimelineWorkPackage>> watchWorkPackages(String projectId) =>
      (select(timelineWorkPackages)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .watch();

  Future<void> upsertWorkPackage(TimelineWorkPackagesCompanion entry) =>
      into(timelineWorkPackages).insertOnConflictUpdate(entry);

  Future<void> deleteWorkPackage(String id) =>
      (delete(timelineWorkPackages)..where((t) => t.id.equals(id))).go();

  // ── Activities ────────────────────────────────────────────────────────────

  Future<List<TimelineActivity>> getActivitiesForWP(String wpId) =>
      (select(timelineActivities)
            ..where((t) => t.workPackageId.equals(wpId))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  Future<List<TimelineActivity>> getActivitiesForProject(String projectId) =>
      (select(timelineActivities)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.workPackageId),
              (t) => OrderingTerm(expression: t.sortOrder),
            ]))
          .get();

  Future<void> upsertActivity(TimelineActivitiesCompanion entry) =>
      into(timelineActivities).insertOnConflictUpdate(entry);

  /// Partial update — only writes the columns present in [data].
  Future<void> patchActivity(String id, TimelineActivitiesCompanion data) =>
      (update(timelineActivities)..where((t) => t.id.equals(id))).write(data);

  /// Snapshots current startMonth/endMonth into baselineStart/baselineEnd
  /// for all activities in [projectId].
  Future<void> setBaseline(String projectId) async {
    final acts = await getActivitiesForProject(projectId);
    for (final a in acts) {
      await patchActivity(
        a.id,
        TimelineActivitiesCompanion(
          isBaseline:    const Value(true),
          baselineStart: Value(a.startMonth),
          baselineEnd:   Value(a.endMonth),
          updatedAt:     Value(DateTime.now()),
        ),
      );
    }
  }

  /// Clears baseline data from all activities in [projectId].
  Future<void> clearBaseline(String projectId) =>
      (update(timelineActivities)
            ..where((t) => t.projectId.equals(projectId)))
          .write(const TimelineActivitiesCompanion(
            isBaseline:    Value(false),
            baselineStart: Value.absent(),
            baselineEnd:   Value.absent(),
          ));

  Future<void> deleteActivity(String id) =>
      (delete(timelineActivities)..where((t) => t.id.equals(id))).go();

  Future<void> deleteActivitiesForWP(String wpId) =>
      (delete(timelineActivities)
            ..where((t) => t.workPackageId.equals(wpId)))
          .go();

  // ── Dependencies ──────────────────────────────────────────────────────────

  Future<List<TimelineDependency>> getDependencies(String projectId) =>
      (select(timelineDependencies)
            ..where((t) => t.projectId.equals(projectId)))
          .get();

  Future<void> upsertDependency(TimelineDependenciesCompanion entry) =>
      into(timelineDependencies).insertOnConflictUpdate(entry);

  Future<void> deleteDependency(String id) =>
      (delete(timelineDependencies)..where((t) => t.id.equals(id))).go();

  // ── Programme Header ──────────────────────────────────────────────────────

  Future<ProgrammeHeader?> getHeader(String projectId) =>
      (select(programmeHeaders)
            ..where((t) => t.projectId.equals(projectId))
            ..limit(1))
          .getSingleOrNull();

  Future<void> upsertHeader(ProgrammeHeadersCompanion entry) =>
      into(programmeHeaders).insertOnConflictUpdate(entry);

  // ── Project Scopes ────────────────────────────────────────────────────────

  Future<ProjectScope?> getScope(String projectId) =>
      (select(projectScopes)
            ..where((t) => t.projectId.equals(projectId))
            ..limit(1))
          .getSingleOrNull();

  Future<void> upsertScope(ProjectScopesCompanion entry) =>
      into(projectScopes).insertOnConflictUpdate(entry);

  // ── Integration Domains ───────────────────────────────────────────────────

  Future<List<IntegrationDomain>> getDomains(String projectId) =>
      (select(integrationDomains)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  Future<void> upsertDomain(IntegrationDomainsCompanion entry) =>
      into(integrationDomains).insertOnConflictUpdate(entry);

  Future<void> deleteDomain(String id) =>
      (delete(integrationDomains)..where((t) => t.id.equals(id))).go();

  // ── Prioritisation Sources ────────────────────────────────────────────────

  Future<List<PrioritisationSource>> getSources(String projectId) =>
      (select(prioritisationSources)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  Future<void> upsertSource(PrioritisationSourcesCompanion entry) =>
      into(prioritisationSources).insertOnConflictUpdate(entry);

  Future<void> deleteSource(String id) =>
      (delete(prioritisationSources)..where((t) => t.id.equals(id))).go();
}
