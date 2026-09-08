part of '../database.dart';

/// A weekly objective joined with its week plan — the quarter view reads
/// a whole quarter of objectives in one query for the week strip and
/// goal progress.
typedef QuarterObjectiveRow = ({
  WeekPlanObjective objective,
  WeekPlan weekPlan,
});

@DriftAccessor(tables: [
  QuarterPlans,
  QuarterGoals,
  WeekPlans,
  WeekPlanObjectives,
])
class QuarterPlanDao extends DatabaseAccessor<AppDatabase>
    with _$QuarterPlanDaoMixin {
  QuarterPlanDao(super.db);

  static const _uuid = Uuid();

  // ── Plans ─────────────────────────────────────────────────────────────

  Stream<QuarterPlan?> watchPlanForQuarter(String startIso) {
    return (select(quarterPlans)
          ..where((t) => t.quarterStartDate.equals(startIso)))
        .watchSingleOrNull();
  }

  Future<QuarterPlan?> getPlanForQuarter(String startIso) {
    return (select(quarterPlans)
          ..where((t) => t.quarterStartDate.equals(startIso)))
        .getSingleOrNull();
  }

  Future<QuarterPlan> getOrCreatePlanForQuarter(String startIso) async {
    final existing = await getPlanForQuarter(startIso);
    if (existing != null) return existing;
    final id = _uuid.v4();
    await into(quarterPlans).insert(QuarterPlansCompanion.insert(
      id: id,
      quarterStartDate: startIso,
    ));
    return (select(quarterPlans)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  /// The parent plan's updatedAt is the sync guard for the whole quarter.
  Future<void> _touchPlan(String planId) {
    return (update(quarterPlans)..where((t) => t.id.equals(planId)))
        .write(QuarterPlansCompanion(updatedAt: Value(DateTime.now())));
  }

  /// Sets (or clears, with an empty string) the mission for a month of
  /// the quarter. [monthIndex] is 0 | 1 | 2.
  Future<void> setMonthMission(
      String planId, int monthIndex, String mission) async {
    await transaction(() async {
      final plan = await (select(quarterPlans)
            ..where((t) => t.id.equals(planId)))
          .getSingle();
      final missions = <String, dynamic>{};
      try {
        missions.addAll(
            jsonDecode(plan.monthMissionsJson) as Map<String, dynamic>);
      } catch (_) {}
      if (mission.trim().isEmpty) {
        missions.remove('$monthIndex');
      } else {
        missions['$monthIndex'] = mission.trim();
      }
      await (update(quarterPlans)..where((t) => t.id.equals(planId)))
          .write(QuarterPlansCompanion(
        monthMissionsJson: Value(jsonEncode(missions)),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  // ── Goals ─────────────────────────────────────────────────────────────

  Stream<List<QuarterGoal>> watchGoalsForPlan(String planId) {
    return (select(quarterGoals)
          ..where((t) => t.quarterPlanId.equals(planId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Future<List<QuarterGoal>> getGoalsForPlan(String planId) {
    return (select(quarterGoals)
          ..where((t) => t.quarterPlanId.equals(planId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
  }

  Future<String> insertGoal({
    required String planId,
    required String label,
    String? why,
    String? projectId,
    String? linkedActionId,
    int? targetObjectives,
  }) async {
    final id = _uuid.v4();
    await transaction(() async {
      final count = await (select(quarterGoals)
            ..where((t) => t.quarterPlanId.equals(planId)))
          .get();
      await into(quarterGoals).insert(QuarterGoalsCompanion.insert(
        id: id,
        quarterPlanId: planId,
        sortOrder: Value(count.length),
        label: label,
        why: Value(why),
        projectId: Value(projectId),
        linkedActionId: Value(linkedActionId),
        targetObjectives: Value(targetObjectives),
      ));
      await _touchPlan(planId);
    });
    return id;
  }

  Future<void> updateGoal(
      String planId, QuarterGoalsCompanion entry) async {
    await transaction(() async {
      await (update(quarterGoals)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      await _touchPlan(planId);
    });
  }

  Future<void> setGoalDone(String planId, String goalId, bool done) async {
    await updateGoal(
        planId, QuarterGoalsCompanion(id: Value(goalId), done: Value(done)));
  }

  Future<void> deleteGoal(String planId, String goalId) async {
    await transaction(() async {
      // Unlink any weekly objectives pointing at it — labels are
      // denormalised, nothing user-visible is lost.
      await (update(weekPlanObjectives)
            ..where((t) => t.goalId.equals(goalId)))
          .write(const WeekPlanObjectivesCompanion(goalId: Value(null)));
      await (delete(quarterGoals)..where((t) => t.id.equals(goalId))).go();
      await _touchPlan(planId);
    });
  }

  // ── Quarter-of-weeks readout ──────────────────────────────────────────

  Stream<List<WeekPlan>> watchWeekPlansForQuarter(
      String startIso, String endIso) {
    return (select(weekPlans)
          ..where((t) =>
              t.weekStartDate.isBiggerOrEqualValue(startIso) &
              t.weekStartDate.isSmallerOrEqualValue(endIso))
          ..orderBy([(t) => OrderingTerm.asc(t.weekStartDate)]))
        .watch();
  }

  /// Every weekly objective in the quarter, joined with its week — one
  /// stream for the week strip and goal progress alike. The range is
  /// over week START dates (a week belongs to the quarter containing
  /// its Monday).
  Stream<List<QuarterObjectiveRow>> watchObjectivesForQuarter(
      String startIso, String endIso) {
    final q = select(weekPlanObjectives).join([
      innerJoin(
          weekPlans, weekPlans.id.equalsExp(weekPlanObjectives.weekPlanId)),
    ])
      ..where(weekPlans.weekStartDate.isBiggerOrEqualValue(startIso) &
          weekPlans.weekStartDate.isSmallerOrEqualValue(endIso))
      ..orderBy([
        OrderingTerm.asc(weekPlans.weekStartDate),
        OrderingTerm.asc(weekPlanObjectives.sortOrder),
      ]);
    return q.watch().map((rows) => rows
        .map((r) => (
              objective: r.readTable(weekPlanObjectives),
              weekPlan: r.readTable(weekPlans),
            ))
        .toList());
  }

  // ── Sync (export/import) ──────────────────────────────────────────────

  Future<List<QuarterPlan>> getAllPlans() {
    return (select(quarterPlans)
          ..orderBy([(t) => OrderingTerm.asc(t.quarterStartDate)]))
        .get();
  }

  Future<List<QuarterGoal>> getAllGoals() {
    return select(quarterGoals).get();
  }

  /// Same guarded replace as the day/week layers — matched by
  /// quarterStartDate, replaced wholesale only when strictly newer.
  Future<bool> applyImportedPlan({
    required QuarterPlansCompanion plan,
    required List<QuarterGoalsCompanion> goals,
  }) async {
    return transaction(() async {
      final incomingStart = plan.quarterStartDate.value;
      final incomingUpdated =
          plan.updatedAt.present ? plan.updatedAt.value : null;
      final local = await getPlanForQuarter(incomingStart);
      if (local != null) {
        if (incomingUpdated == null ||
            !incomingUpdated.isAfter(local.updatedAt)) {
          return false; // local copy is same age or newer — keep it
        }
        await (delete(quarterGoals)
              ..where((t) => t.quarterPlanId.equals(local.id)))
            .go();
        await (delete(quarterPlans)..where((t) => t.id.equals(local.id)))
            .go();
      }
      await into(quarterPlans).insert(plan);
      for (final g in goals) {
        await into(quarterGoals).insert(g);
      }
      return true;
    });
  }
}
