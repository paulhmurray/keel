part of '../database.dart';

/// A rail item for the Helm planning surface — an item from any project,
/// tagged with its project name so the global day view can attribute it.
typedef HelmActionItem = ({ProjectAction action, String projectName});
typedef HelmRiskItem = ({Risk risk, String projectName});
typedef HelmDecisionItem = ({Decision decision, String projectName});
typedef HelmIssueItem = ({Issue issue, String projectName});
typedef HelmAssumptionItem = ({Assumption assumption, String projectName});
typedef HelmDependencyItem = ({
  ProgramDependency dependency,
  String projectName
});

@DriftAccessor(tables: [
  DayPlans,
  DayPlanBlocks,
  Projects,
  ProjectActions,
  Risks,
  Issues,
  Assumptions,
  ProgramDependencies,
  Decisions,
])
class DayPlanDao extends DatabaseAccessor<AppDatabase>
    with _$DayPlanDaoMixin {
  DayPlanDao(super.db);

  static const _uuid = Uuid();

  // ── Plans ─────────────────────────────────────────────────────────────

  Stream<DayPlan?> watchPlanForDate(String isoDate) {
    return (select(dayPlans)..where((t) => t.planDate.equals(isoDate)))
        .watchSingleOrNull();
  }

  Future<DayPlan?> getPlanForDate(String isoDate) {
    return (select(dayPlans)..where((t) => t.planDate.equals(isoDate)))
        .getSingleOrNull();
  }

  Future<DayPlan> getOrCreatePlanForDate(String isoDate) async {
    final existing = await getPlanForDate(isoDate);
    if (existing != null) return existing;
    final id = _uuid.v4();
    await into(dayPlans).insert(DayPlansCompanion.insert(
      id: id,
      planDate: isoDate,
    ));
    return (select(dayPlans)..where((t) => t.id.equals(id))).getSingle();
  }

  // ── Blocks ────────────────────────────────────────────────────────────

  Stream<List<DayPlanBlock>> watchBlocksForPlan(String planId) {
    return (select(dayPlanBlocks)
          ..where((t) => t.dayPlanId.equals(planId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.revision),
            (t) => OrderingTerm.asc(t.startMinute),
          ]))
        .watch();
  }

  Future<List<DayPlanBlock>> getBlocksForPlan(String planId) {
    return (select(dayPlanBlocks)
          ..where((t) => t.dayPlanId.equals(planId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.revision),
            (t) => OrderingTerm.asc(t.startMinute),
          ]))
        .get();
  }

  /// The parent plan's updatedAt is the sync guard for the whole day —
  /// touch it on every block mutation.
  Future<void> _touchPlan(String planId) {
    return (update(dayPlans)..where((t) => t.id.equals(planId)))
        .write(DayPlansCompanion(updatedAt: Value(DateTime.now())));
  }

  Future<String> insertBlock({
    required String planId,
    required int revision,
    required int startMinute,
    required int endMinute,
    required String label,
    String kind = 'focus',
    String? projectId,
    String? linkedActionId,
  }) async {
    final id = _uuid.v4();
    await transaction(() async {
      await into(dayPlanBlocks).insert(DayPlanBlocksCompanion.insert(
        id: id,
        dayPlanId: planId,
        revision: Value(revision),
        startMinute: startMinute,
        endMinute: endMinute,
        kind: Value(kind),
        label: label,
        projectId: Value(projectId),
        linkedActionId: Value(linkedActionId),
      ));
      await _touchPlan(planId);
    });
    return id;
  }

  Future<void> updateBlock(String planId, DayPlanBlocksCompanion entry) async {
    await transaction(() async {
      await (update(dayPlanBlocks)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      await _touchPlan(planId);
    });
  }

  Future<void> moveBlock(
      String planId, String blockId, int newStartMinute) async {
    final block = await (select(dayPlanBlocks)
          ..where((t) => t.id.equals(blockId)))
        .getSingleOrNull();
    if (block == null) return;
    final duration = block.endMinute - block.startMinute;
    await transaction(() async {
      await (update(dayPlanBlocks)..where((t) => t.id.equals(blockId)))
          .write(DayPlanBlocksCompanion(
        startMinute: Value(newStartMinute),
        endMinute: Value(newStartMinute + duration),
        updatedAt: Value(DateTime.now()),
      ));
      await _touchPlan(planId);
    });
  }

  Future<void> setBlockDone(String planId, String blockId, bool done) async {
    await transaction(() async {
      await (update(dayPlanBlocks)..where((t) => t.id.equals(blockId)))
          .write(DayPlanBlocksCompanion(
        done: Value(done),
        updatedAt: Value(DateTime.now()),
      ));
      await _touchPlan(planId);
    });
  }

  Future<void> deleteBlock(String planId, String blockId) async {
    await transaction(() async {
      await (delete(dayPlanBlocks)..where((t) => t.id.equals(blockId))).go();
      await _touchPlan(planId);
    });
  }

  // ── Revisions (Cal Newport columns) ───────────────────────────────────

  /// Starts a new revision governing the day from [atMinute] onward.
  /// Blocks of the current revision that START at or after [atMinute] are
  /// copied forward into the new column as a starting point (the old
  /// copies stay behind as the superseded record); a block already in
  /// progress at [atMinute] stays governed by its old column.
  Future<int> startRevision(String planId, int atMinute) async {
    return transaction(() async {
      final plan = await (select(dayPlans)
            ..where((t) => t.id.equals(planId)))
          .getSingle();
      final starts = (jsonDecode(plan.revisionStartsJson) as List)
          .cast<int>()
          .toList();
      final newRevision = plan.currentRevision + 1;
      starts.add(atMinute);

      final toCopy = await (select(dayPlanBlocks)
            ..where((t) =>
                t.dayPlanId.equals(planId) &
                t.revision.equals(plan.currentRevision) &
                t.startMinute.isBiggerOrEqualValue(atMinute)))
          .get();
      for (final b in toCopy) {
        await into(dayPlanBlocks).insert(DayPlanBlocksCompanion.insert(
          id: _uuid.v4(),
          dayPlanId: planId,
          revision: Value(newRevision),
          startMinute: b.startMinute,
          endMinute: b.endMinute,
          kind: Value(b.kind),
          label: b.label,
          projectId: Value(b.projectId),
          linkedActionId: Value(b.linkedActionId),
          done: Value(b.done),
        ));
      }

      await (update(dayPlans)..where((t) => t.id.equals(planId)))
          .write(DayPlansCompanion(
        currentRevision: Value(newRevision),
        revisionStartsJson: Value(jsonEncode(starts)),
        updatedAt: Value(DateTime.now()),
      ));
      return newRevision;
    });
  }

  // ── Sync (export/import) ──────────────────────────────────────────────

  Future<List<DayPlan>> getAllPlans() {
    return (select(dayPlans)..orderBy([(t) => OrderingTerm.asc(t.planDate)]))
        .get();
  }

  Future<List<DayPlanBlock>> getAllBlocks() {
    return select(dayPlanBlocks).get();
  }

  /// Applies one imported day (plan + blocks), guarded by updatedAt.
  ///
  /// Day plans are global but ride in every project's sync blob, so a
  /// stale project pull must never clobber a newer local day. The local
  /// row is matched by planDate — two machines create the same date under
  /// different ids — and replaced wholesale (blocks included) only when
  /// the incoming copy is strictly newer. Returns true when applied.
  Future<bool> applyImportedPlan({
    required DayPlansCompanion plan,
    required List<DayPlanBlocksCompanion> blocks,
  }) async {
    return transaction(() async {
      final incomingDate = plan.planDate.value;
      final incomingUpdated =
          plan.updatedAt.present ? plan.updatedAt.value : null;
      final local = await getPlanForDate(incomingDate);
      if (local != null) {
        if (incomingUpdated == null ||
            !incomingUpdated.isAfter(local.updatedAt)) {
          return false; // local copy is same age or newer — keep it
        }
        await (delete(dayPlanBlocks)
              ..where((t) => t.dayPlanId.equals(local.id)))
            .go();
        await (delete(dayPlans)..where((t) => t.id.equals(local.id))).go();
      }
      await into(dayPlans).insert(plan);
      for (final b in blocks) {
        await into(dayPlanBlocks).insert(b);
      }
      return true;
    });
  }

  // ── Cross-project planning material ───────────────────────────────────
  // The Helm rail pulls from EVERY project, so these deliberately have no
  // projectId parameter. Cascaded copies (sourceProjectId set) are
  // excluded — the native row in the source project already appears.

  Stream<List<HelmActionItem>> watchOverdueActionsAllProjects() {
    final today = _todayIso();
    final q = select(projectActions).join([
      innerJoin(projects, projects.id.equalsExp(projectActions.projectId)),
    ])
      ..where(projectActions.dueDate.isNotNull() &
          projectActions.dueDate.isSmallerThanValue(today) &
          projectActions.status.equals('closed').not() &
          projectActions.sourceProjectId.isNull())
      ..orderBy([OrderingTerm.asc(projectActions.dueDate)]);
    return q.watch().map((rows) => rows
        .map((r) => (
              action: r.readTable(projectActions),
              projectName: r.readTable(projects).name,
            ))
        .toList());
  }

  Stream<List<HelmActionItem>> watchActionsDueTodayAllProjects() {
    final today = _todayIso();
    final q = select(projectActions).join([
      innerJoin(projects, projects.id.equalsExp(projectActions.projectId)),
    ])
      ..where(projectActions.dueDate.equals(today) &
          projectActions.status.equals('closed').not() &
          projectActions.sourceProjectId.isNull())
      ..orderBy([OrderingTerm.asc(projectActions.createdAt)]);
    return q.watch().map((rows) => rows
        .map((r) => (
              action: r.readTable(projectActions),
              projectName: r.readTable(projects).name,
            ))
        .toList());
  }

  Stream<List<HelmRiskItem>> watchUnownedOpenRisksAllProjects() {
    final q = select(risks).join([
      innerJoin(projects, projects.id.equalsExp(risks.projectId)),
    ])
      ..where(risks.status.equals('open') &
          (risks.owner.isNull() | risks.owner.equals('')) &
          risks.sourceProjectId.isNull())
      ..orderBy([OrderingTerm.desc(risks.updatedAt)]);
    return q.watch().map((rows) => rows
        .map((r) => (
              risk: r.readTable(risks),
              projectName: r.readTable(projects).name,
            ))
        .toList());
  }

  Stream<List<HelmDecisionItem>> watchPendingDecisionsAllProjects() {
    final q = select(decisions).join([
      innerJoin(projects, projects.id.equalsExp(decisions.projectId)),
    ])
      ..where(decisions.status.equals('pending') &
          decisions.sourceProjectId.isNull())
      ..orderBy([OrderingTerm.asc(decisions.dueDate)]);
    return q.watch().map((rows) => rows
        .map((r) => (
              decision: r.readTable(decisions),
              projectName: r.readTable(projects).name,
            ))
        .toList());
  }

  // ── Browse mode — the FULL open books, not just the urgent slices ─────
  // "Open" is defined per register from each form's status vocabulary:
  // anything closed or otherwise settled (resolved, accepted, validated,
  // rejected, deferred) stays out of the planning rail.

  Stream<List<HelmActionItem>> watchOpenActionsAllProjects() {
    final q = select(projectActions).join([
      innerJoin(projects, projects.id.equalsExp(projectActions.projectId)),
    ])
      ..where(projectActions.status.equals('closed').not() &
          projectActions.sourceProjectId.isNull())
      // Dated work first (soonest due leading), undated after.
      ..orderBy([
        OrderingTerm.asc(projectActions.dueDate.isNull()),
        OrderingTerm.asc(projectActions.dueDate),
      ]);
    return q.watch().map((rows) => rows
        .map((r) => (
              action: r.readTable(projectActions),
              projectName: r.readTable(projects).name,
            ))
        .toList());
  }

  Stream<List<HelmRiskItem>> watchOpenRisksAllProjects() {
    final q = select(risks).join([
      innerJoin(projects, projects.id.equalsExp(risks.projectId)),
    ])
      // Risk vocabulary: open / in progress / closed / accepted — the
      // first two are live, accepted is a settled posture.
      ..where(risks.status.isIn(['open', 'in progress']) &
          risks.sourceProjectId.isNull())
      ..orderBy([OrderingTerm.desc(risks.updatedAt)]);
    return q.watch().map((rows) => rows
        .map((r) => (
              risk: r.readTable(risks),
              projectName: r.readTable(projects).name,
            ))
        .toList());
  }

  Stream<List<HelmIssueItem>> watchOpenIssuesAllProjects() {
    final q = select(issues).join([
      innerJoin(projects, projects.id.equalsExp(issues.projectId)),
    ])
      ..where(issues.status.isIn(['open', 'in progress']) &
          issues.sourceProjectId.isNull())
      ..orderBy([OrderingTerm.desc(issues.updatedAt)]);
    return q.watch().map((rows) => rows
        .map((r) => (
              issue: r.readTable(issues),
              projectName: r.readTable(projects).name,
            ))
        .toList());
  }

  Stream<List<HelmAssumptionItem>> watchOpenAssumptionsAllProjects() {
    final q = select(assumptions).join([
      innerJoin(projects, projects.id.equalsExp(assumptions.projectId)),
    ])
      ..where(assumptions.status.equals('open') &
          assumptions.sourceProjectId.isNull())
      ..orderBy([OrderingTerm.desc(assumptions.updatedAt)]);
    return q.watch().map((rows) => rows
        .map((r) => (
              assumption: r.readTable(assumptions),
              projectName: r.readTable(projects).name,
            ))
        .toList());
  }

  Stream<List<HelmDependencyItem>> watchOpenDependenciesAllProjects() {
    final q = select(programDependencies).join([
      innerJoin(
          projects, projects.id.equalsExp(programDependencies.projectId)),
    ])
      ..where(programDependencies.status.isNotIn(['closed', 'resolved']) &
          programDependencies.sourceProjectId.isNull())
      ..orderBy([OrderingTerm.desc(programDependencies.updatedAt)]);
    return q.watch().map((rows) => rows
        .map((r) => (
              dependency: r.readTable(programDependencies),
              projectName: r.readTable(projects).name,
            ))
        .toList());
  }

  String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
