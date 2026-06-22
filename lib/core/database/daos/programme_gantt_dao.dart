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

  /// Rewrites [TimelineWorkPackages.sortOrder] for [projectId] so that
  /// each id in [orderedIds] takes the index it sits at. Work packages
  /// in the project that aren't listed are left untouched (so partial
  /// reorders don't accidentally renumber siblings the UI doesn't know
  /// about). Idempotent; runs in a single transaction.
  Future<void> reorderWorkPackages(
      String projectId, List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(timelineWorkPackages)
              ..where((t) =>
                  t.id.equals(orderedIds[i]) &
                  t.projectId.equals(projectId)))
            .write(TimelineWorkPackagesCompanion(sortOrder: Value(i)));
      }
    });
  }

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

  /// Rewrites [TimelineActivities.sortOrder] for activities under [wpId]
  /// so each id in [orderedIds] takes its index. Filtering by [wpId] is
  /// load-bearing: it prevents an out-of-scope id from accidentally
  /// being repositioned (and from leaking activities across WPs).
  /// Idempotent; runs in a single transaction.
  Future<void> reorderActivitiesWithinWp(
      String wpId, List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(timelineActivities)
              ..where((t) =>
                  t.id.equals(orderedIds[i]) &
                  t.workPackageId.equals(wpId)))
            .write(TimelineActivitiesCompanion(sortOrder: Value(i)));
      }
    });
  }

  // ── Dependencies ──────────────────────────────────────────────────────────

  Future<List<TimelineDependency>> getDependencies(String projectId) =>
      (select(timelineDependencies)
            ..where((t) => t.projectId.equals(projectId)))
          .get();

  Future<void> upsertDependency(TimelineDependenciesCompanion entry) =>
      into(timelineDependencies).insertOnConflictUpdate(entry);

  Future<void> deleteDependency(String id) =>
      (delete(timelineDependencies)..where((t) => t.id.equals(id))).go();

  /// All dependencies where [activityId] is the downstream (`to`) side
  /// — i.e. the predecessors of this activity. Used by the activity
  /// edit form to populate its "Depends on" list.
  Future<List<TimelineDependency>> getInboundDependenciesFor(
          String activityId) =>
      (select(timelineDependencies)
            ..where((t) => t.toActivityId.equals(activityId)))
          .get();

  /// Atomically rewrites the inbound dependencies of [activityId] in
  /// [projectId] to match [desired]. Each [DependencySpec] is either an
  /// internal predecessor (points at another activity) or external
  /// (free-text label, no source activity). Rows present in the DB but
  /// not in [desired] are deleted; new entries are inserted; existing
  /// entries with a changed type are updated in-place.
  ///
  /// Runs as a transaction so the activity never has a half-rewritten
  /// dep set visible to the painter mid-save.
  Future<void> replaceInboundDependencies({
    required String projectId,
    required String activityId,
    required List<DependencySpec> desired,
  }) async {
    await transaction(() async {
      final existing = await getInboundDependenciesFor(activityId);

      // Bucket existing rows by their natural key so we can do a
      // diff-by-identity rather than blow-and-recreate.
      final existingInternalByFrom = <String, TimelineDependency>{};
      final existingExternalByLabel = <String, TimelineDependency>{};
      for (final r in existing) {
        if (r.externalLabel != null) {
          existingExternalByLabel[r.externalLabel!] = r;
        } else {
          existingInternalByFrom[r.fromActivityId] = r;
        }
      }

      final wantedInternal = <String, String>{}; // from → type
      final wantedExternal = <String, String>{}; // label → type
      for (final d in desired) {
        if (d.isExternal) {
          wantedExternal[d.externalLabel!] = d.dependencyType;
        } else {
          wantedInternal[d.fromActivityId!] = d.dependencyType;
        }
      }

      // Delete rows that no longer appear in the desired set.
      for (final row in existing) {
        final stillWanted = row.externalLabel != null
            ? wantedExternal.containsKey(row.externalLabel)
            : wantedInternal.containsKey(row.fromActivityId);
        if (!stillWanted) {
          await (delete(timelineDependencies)
                ..where((t) => t.id.equals(row.id)))
              .go();
        }
      }

      // Insert / update internal predecessors.
      for (final entry in wantedInternal.entries) {
        final existingRow = existingInternalByFrom[entry.key];
        if (existingRow == null) {
          await into(timelineDependencies).insert(
            TimelineDependenciesCompanion.insert(
              id: _internalDepId(entry.key, activityId),
              projectId: projectId,
              fromActivityId: entry.key,
              toActivityId: activityId,
              dependencyType: Value(entry.value),
            ),
          );
        } else if (existingRow.dependencyType != entry.value) {
          await (update(timelineDependencies)
                ..where((t) => t.id.equals(existingRow.id)))
              .write(TimelineDependenciesCompanion(
            dependencyType: Value(entry.value),
          ));
        }
      }

      // Insert / update externals — keyed by label, type is locked to
      // 'external' (the editor only offers one type for these, since
      // FS/SS/FF don't apply when there's no upstream activity).
      for (final entry in wantedExternal.entries) {
        final existingRow = existingExternalByLabel[entry.key];
        if (existingRow == null) {
          await into(timelineDependencies).insert(
            TimelineDependenciesCompanion.insert(
              id: _externalDepId(entry.key, activityId),
              projectId: projectId,
              fromActivityId: '',
              toActivityId: activityId,
              dependencyType: const Value('external'),
              externalLabel: Value(entry.key),
            ),
          );
        }
        // No type update for externals — type is fixed.
      }
    });
  }

  /// Stable id for an internal dep keyed by (from, to). A directed pair
  /// always produces the same id; the opposite direction gets its own.
  String _internalDepId(String fromId, String toId) =>
      'dep_${fromId}__$toId';

  /// Stable id for an external dep keyed by (label, to). Different
  /// labels on the same target activity get separate ids so the user
  /// can attach multiple externals without collisions.
  String _externalDepId(String label, String toId) {
    // Stable across rebuilds: hash the label so renames produce
    // genuinely new rows rather than colliding with a renamed-away
    // row that's still being deleted in the same transaction.
    final h = label.codeUnits.fold<int>(
        0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    return 'extdep_${h}__$toId';
  }

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

/// Editor-facing representation of one predecessor row, used by
/// [ProgrammeGanttDao.replaceInboundDependencies]. Two flavours:
///   - Internal: [fromActivityId] non-null, [externalLabel] null —
///     points at another activity in the plan.
///   - External: [externalLabel] non-null, [fromActivityId] null —
///     represents a dependency on something outside the plan (vendor
///     delivery, legal sign-off, etc.).
class DependencySpec {
  final String? fromActivityId;
  final String dependencyType;
  final String? externalLabel;

  const DependencySpec._({
    this.fromActivityId,
    required this.dependencyType,
    this.externalLabel,
  });

  /// Spec for a predecessor activity inside the plan.
  factory DependencySpec.internal({
    required String fromActivityId,
    required String dependencyType,
  }) =>
      DependencySpec._(
        fromActivityId: fromActivityId,
        dependencyType: dependencyType,
      );

  /// Spec for an external dependency. [label] is the human description
  /// (e.g. "Vendor X API release"); the dep type is implicitly
  /// 'external'.
  factory DependencySpec.external(String label) => DependencySpec._(
        dependencyType: 'external',
        externalLabel: label,
      );

  bool get isExternal => externalLabel != null;
}
