part of '../database.dart';

/// A day-plan block joined with its day's date — the week view reads a
/// whole week of blocks in one query for day-card readouts and
/// objective progress.
typedef WeekBlockRow = ({DayPlanBlock block, DayPlan plan});

@DriftAccessor(tables: [
  WeekPlans,
  WeekPlanObjectives,
  DayPlans,
  DayPlanBlocks,
])
class WeekPlanDao extends DatabaseAccessor<AppDatabase>
    with _$WeekPlanDaoMixin {
  WeekPlanDao(super.db);

  static const _uuid = Uuid();

  // ── Plans ─────────────────────────────────────────────────────────────

  Stream<WeekPlan?> watchPlanForWeek(String mondayIso) {
    return (select(weekPlans)
          ..where((t) => t.weekStartDate.equals(mondayIso)))
        .watchSingleOrNull();
  }

  Future<WeekPlan?> getPlanForWeek(String mondayIso) {
    return (select(weekPlans)
          ..where((t) => t.weekStartDate.equals(mondayIso)))
        .getSingleOrNull();
  }

  Future<WeekPlan> getOrCreatePlanForWeek(String mondayIso) async {
    final existing = await getPlanForWeek(mondayIso);
    if (existing != null) return existing;
    final id = _uuid.v4();
    await into(weekPlans).insert(WeekPlansCompanion.insert(
      id: id,
      weekStartDate: mondayIso,
    ));
    return (select(weekPlans)..where((t) => t.id.equals(id))).getSingle();
  }

  /// The parent plan's updatedAt is the sync guard for the whole week —
  /// touch it on every objective/mission mutation.
  Future<void> _touchPlan(String planId) {
    return (update(weekPlans)..where((t) => t.id.equals(planId)))
        .write(WeekPlansCompanion(updatedAt: Value(DateTime.now())));
  }

  /// Sets (or clears, with an empty string) the one-line mission for a
  /// weekday. [weekday] is 0 = Monday … 6 = Sunday.
  Future<void> setDayMission(
      String planId, int weekday, String mission) async {
    await transaction(() async {
      final plan = await (select(weekPlans)
            ..where((t) => t.id.equals(planId)))
          .getSingle();
      final missions = <String, dynamic>{};
      try {
        missions.addAll(
            jsonDecode(plan.dayMissionsJson) as Map<String, dynamic>);
      } catch (_) {}
      if (mission.trim().isEmpty) {
        missions.remove('$weekday');
      } else {
        missions['$weekday'] = mission.trim();
      }
      await (update(weekPlans)..where((t) => t.id.equals(planId)))
          .write(WeekPlansCompanion(
        dayMissionsJson: Value(jsonEncode(missions)),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  // ── Objectives ────────────────────────────────────────────────────────

  Stream<List<WeekPlanObjective>> watchObjectivesForPlan(String planId) {
    return (select(weekPlanObjectives)
          ..where((t) => t.weekPlanId.equals(planId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Future<List<WeekPlanObjective>> getObjectivesForPlan(String planId) {
    return (select(weekPlanObjectives)
          ..where((t) => t.weekPlanId.equals(planId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
  }

  Future<String> insertObjective({
    required String planId,
    required String label,
    String? projectId,
    String? linkedActionId,
    String? goalId,
    int? targetBlocks,
  }) async {
    final id = _uuid.v4();
    await transaction(() async {
      final count = await (select(weekPlanObjectives)
            ..where((t) => t.weekPlanId.equals(planId)))
          .get();
      await into(weekPlanObjectives)
          .insert(WeekPlanObjectivesCompanion.insert(
        id: id,
        weekPlanId: planId,
        sortOrder: Value(count.length),
        label: label,
        projectId: Value(projectId),
        linkedActionId: Value(linkedActionId),
        goalId: Value(goalId),
        targetBlocks: Value(targetBlocks),
      ));
      await _touchPlan(planId);
    });
    return id;
  }

  Future<void> updateObjective(
      String planId, WeekPlanObjectivesCompanion entry) async {
    await transaction(() async {
      await (update(weekPlanObjectives)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      await _touchPlan(planId);
    });
  }

  Future<void> setObjectiveDone(
      String planId, String objectiveId, bool done) async {
    await updateObjective(
        planId,
        WeekPlanObjectivesCompanion(
          id: Value(objectiveId),
          done: Value(done),
        ));
  }

  Future<void> deleteObjective(String planId, String objectiveId) async {
    await transaction(() async {
      // Unlink any blocks pointing at it — their labels are denormalised
      // so nothing user-visible is lost.
      await (update(dayPlanBlocks)
            ..where((t) => t.objectiveId.equals(objectiveId)))
          .write(const DayPlanBlocksCompanion(objectiveId: Value(null)));
      await (delete(weekPlanObjectives)
            ..where((t) => t.id.equals(objectiveId)))
          .go();
      await _touchPlan(planId);
    });
  }

  // ── Week-of-days readout ──────────────────────────────────────────────

  Stream<List<DayPlan>> watchDayPlansForWeek(
      String mondayIso, String sundayIso) {
    return (select(dayPlans)
          ..where((t) =>
              t.planDate.isBiggerOrEqualValue(mondayIso) &
              t.planDate.isSmallerOrEqualValue(sundayIso))
          ..orderBy([(t) => OrderingTerm.asc(t.planDate)]))
        .watch();
  }

  /// Every block in the week, joined with its day plan — one stream for
  /// day-card readouts and objective progress alike.
  Stream<List<WeekBlockRow>> watchBlocksForWeek(
      String mondayIso, String sundayIso) {
    final q = select(dayPlanBlocks).join([
      innerJoin(dayPlans, dayPlans.id.equalsExp(dayPlanBlocks.dayPlanId)),
    ])
      ..where(dayPlans.planDate.isBiggerOrEqualValue(mondayIso) &
          dayPlans.planDate.isSmallerOrEqualValue(sundayIso))
      ..orderBy([
        OrderingTerm.asc(dayPlans.planDate),
        OrderingTerm.asc(dayPlanBlocks.startMinute),
      ]);
    return q.watch().map((rows) => rows
        .map((r) => (
              block: r.readTable(dayPlanBlocks),
              plan: r.readTable(dayPlans),
            ))
        .toList());
  }

  // ── Sync (export/import) ──────────────────────────────────────────────

  Future<List<WeekPlan>> getAllPlans() {
    return (select(weekPlans)
          ..orderBy([(t) => OrderingTerm.asc(t.weekStartDate)]))
        .get();
  }

  Future<List<WeekPlanObjective>> getAllObjectives() {
    return select(weekPlanObjectives).get();
  }

  /// Same guarded replace as DayPlanDao.applyImportedPlan — matched by
  /// weekStartDate (ids differ across machines), replaced wholesale only
  /// when the incoming copy is strictly newer.
  Future<bool> applyImportedPlan({
    required WeekPlansCompanion plan,
    required List<WeekPlanObjectivesCompanion> objectives,
  }) async {
    return transaction(() async {
      final incomingWeek = plan.weekStartDate.value;
      final incomingUpdated =
          plan.updatedAt.present ? plan.updatedAt.value : null;
      final local = await getPlanForWeek(incomingWeek);
      if (local != null) {
        if (incomingUpdated == null ||
            !incomingUpdated.isAfter(local.updatedAt)) {
          return false; // local copy is same age or newer — keep it
        }
        await (delete(weekPlanObjectives)
              ..where((t) => t.weekPlanId.equals(local.id)))
            .go();
        await (delete(weekPlans)..where((t) => t.id.equals(local.id)))
            .go();
      }
      await into(weekPlans).insert(plan);
      for (final o in objectives) {
        await into(weekPlanObjectives).insert(o);
      }
      return true;
    });
  }
}
