import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/helm/day_plan_logic.dart';
import 'package:keel/core/import/json_importer.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('quarter helpers', () {
    test('calendar anchor snaps to Jan/Apr/Jul/Oct', () {
      expect(quarterStartOf(DateTime(2026, 8, 31), 1), DateTime(2026, 7, 1));
      expect(quarterStartOf(DateTime(2026, 1, 1), 1), DateTime(2026, 1, 1));
      expect(quarterStartOf(DateTime(2026, 12, 15), 1),
          DateTime(2026, 10, 1));
    });

    test('July anchor snaps to Jul/Oct/Jan/Apr, crossing year ends', () {
      expect(quarterStartOf(DateTime(2026, 8, 31), 7), DateTime(2026, 7, 1));
      expect(quarterStartOf(DateTime(2026, 11, 2), 7),
          DateTime(2026, 10, 1));
      // Feb 2027 belongs to the quarter starting Jan 2027 (Q3 FY27).
      expect(quarterStartOf(DateTime(2027, 2, 10), 7),
          DateTime(2027, 1, 1));
      // June 2026 belongs to Apr 2026 (Q4 FY26).
      expect(quarterStartOf(DateTime(2026, 6, 30), 7),
          DateTime(2026, 4, 1));
    });

    test('labels: calendar is plain, FY names the ending year', () {
      expect(quarterLabel(DateTime(2026, 7, 1), 1), 'Q3 2026');
      expect(quarterLabel(DateTime(2026, 7, 1), 7),
          'Q1 FY27 · Jul–Sep 2026');
      expect(quarterLabel(DateTime(2027, 1, 1), 7),
          'Q3 FY27 · Jan–Mar 2027');
    });
  });

  group('plans, missions, goals', () {
    test('getOrCreatePlanForQuarter is idempotent per quarter', () async {
      final a =
          await db.quarterPlanDao.getOrCreatePlanForQuarter('2026-07-01');
      final b =
          await db.quarterPlanDao.getOrCreatePlanForQuarter('2026-07-01');
      expect(a.id, b.id);
    });

    test('mission and goal mutations touch the plan updatedAt '
        '(the sync guard)', () async {
      final plan =
          await db.quarterPlanDao.getOrCreatePlanForQuarter('2026-07-01');
      final old = DateTime(2020, 1, 1);
      Future<void> backdate() => (db.update(db.quarterPlans)
            ..where((t) => t.id.equals(plan.id)))
          .write(QuarterPlansCompanion(updatedAt: Value(old)));
      Future<DateTime> updatedAt() async =>
          (await db.quarterPlanDao.getPlanForQuarter('2026-07-01'))!
              .updatedAt;

      await backdate();
      await db.quarterPlanDao.setMonthMission(plan.id, 1, 'Build month');
      expect((await updatedAt()).isAfter(old), isTrue);

      await backdate();
      final gid = await db.quarterPlanDao
          .insertGoal(planId: plan.id, label: 'Land the platform');
      expect((await updatedAt()).isAfter(old), isTrue);

      await backdate();
      await db.quarterPlanDao.setGoalDone(plan.id, gid, true);
      expect((await updatedAt()).isAfter(old), isTrue);
    });

    test('deleting a goal unlinks its weekly objectives but keeps them',
        () async {
      final quarter =
          await db.quarterPlanDao.getOrCreatePlanForQuarter('2026-07-01');
      final gid = await db.quarterPlanDao
          .insertGoal(planId: quarter.id, label: 'Goal');
      final week =
          await db.weekPlanDao.getOrCreatePlanForWeek('2026-08-24');
      final oid = await db.weekPlanDao.insertObjective(
          planId: week.id, label: 'Weekly slice', goalId: gid);

      await db.quarterPlanDao.deleteGoal(quarter.id, gid);
      final objectives =
          await db.weekPlanDao.getObjectivesForPlan(week.id);
      expect(objectives.single.id, oid);
      expect(objectives.single.goalId, isNull);
      expect(objectives.single.label, 'Weekly slice');
    });
  });

  group('the block → objective → goal cascade', () {
    test('goal progress counts MET objectives: manual done or block '
        'target reached', () async {
      final quarter =
          await db.quarterPlanDao.getOrCreatePlanForQuarter('2026-07-01');
      final gid = await db.quarterPlanDao.insertGoal(
          planId: quarter.id, label: 'Rock', targetObjectives: 3);

      final week =
          await db.weekPlanDao.getOrCreatePlanForWeek('2026-08-24');
      // Objective A: met by manual tick.
      final a = await db.weekPlanDao.insertObjective(
          planId: week.id, label: 'A', goalId: gid);
      await db.weekPlanDao.setObjectiveDone(week.id, a, true);
      // Objective B: met by block target (1 done block).
      final b = await db.weekPlanDao.insertObjective(
          planId: week.id, label: 'B', goalId: gid, targetBlocks: 1);
      final day = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-25');
      final blockId = await db.dayPlanDao.insertBlock(
          planId: day.id,
          revision: 0,
          startMinute: 540,
          endMinute: 600,
          label: 'B work',
          objectiveId: b);
      await db.dayPlanDao.setBlockDone(day.id, blockId, true);
      // Objective C: open — target not reached, not ticked.
      await db.weekPlanDao.insertObjective(
          planId: week.id, label: 'C', goalId: gid, targetBlocks: 2);

      final objectiveRows = await db.quarterPlanDao
          .watchObjectivesForQuarter('2026-07-01', '2026-09-30')
          .first;
      final blockRows = await db.weekPlanDao
          .watchBlocksForWeek('2026-07-01', '2026-09-30')
          .first;
      final startsByPlan = <String, List<int>>{
        for (final r in blockRows)
          r.plan.id: parseRevisionStarts(r.plan.revisionStartsJson),
      };
      final blocks = blockRows.map((r) => r.block).toList();
      final met = goalMetObjectives(
        gid,
        objectiveRows.map((r) => r.objective).toList(),
        (o) => objectiveMet(o, blocks, startsByPlan),
      );
      expect(met, 2); // A (manual) + B (block target); C still open
    });

    test('objectives outside the quarter do not count', () async {
      final quarter =
          await db.quarterPlanDao.getOrCreatePlanForQuarter('2026-07-01');
      final gid = await db.quarterPlanDao
          .insertGoal(planId: quarter.id, label: 'Rock');
      // Week in the NEXT quarter carrying the same goal id.
      final outWeek =
          await db.weekPlanDao.getOrCreatePlanForWeek('2026-10-05');
      final o = await db.weekPlanDao.insertObjective(
          planId: outWeek.id, label: 'Out', goalId: gid);
      await db.weekPlanDao.setObjectiveDone(outWeek.id, o, true);

      final rows = await db.quarterPlanDao
          .watchObjectivesForQuarter('2026-07-01', '2026-09-30')
          .first;
      expect(rows, isEmpty);
    });
  });

  group('sync', () {
    test('stale incoming quarter never clobbers a newer local one',
        () async {
      await db.quarterPlanDao.applyImportedPlan(
        plan: QuarterPlansCompanion(
          id: const Value('local'),
          quarterStartDate: const Value('2026-07-01'),
          createdAt: Value(DateTime(2026, 7, 1)),
          updatedAt: Value(DateTime(2026, 8, 20)),
        ),
        goals: const [],
      );
      final applied = await db.quarterPlanDao.applyImportedPlan(
        plan: QuarterPlansCompanion(
          id: const Value('other-machine'),
          quarterStartDate: const Value('2026-07-01'),
          createdAt: Value(DateTime(2026, 7, 1)),
          updatedAt: Value(DateTime(2026, 8, 10)),
        ),
        goals: const [],
      );
      expect(applied, isFalse);
      expect(
          (await db.quarterPlanDao.getPlanForQuarter('2026-07-01'))!.id,
          'local');
    });

    test('quarter plans + goals + objective links round-trip the blob',
        () async {
      await db.projectDao.upsertProject(const ProjectsCompanion(
        id: Value('p1'),
        name: Value('Alpha'),
      ));
      final quarter =
          await db.quarterPlanDao.getOrCreatePlanForQuarter('2026-07-01');
      await db.quarterPlanDao.setMonthMission(quarter.id, 0, 'Discovery');
      final gid = await db.quarterPlanDao.insertGoal(
          planId: quarter.id,
          label: 'Land the platform re-plan',
          why: 'It unblocks everything else this half',
          targetObjectives: 6);
      final week =
          await db.weekPlanDao.getOrCreatePlanForWeek('2026-08-24');
      await db.weekPlanDao.insertObjective(
          planId: week.id, label: 'Slice one', goalId: gid);

      final blob = await JsonExporter.exportProjectToString(
          projectId: 'p1', db: db);
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db2.close);
      await JsonImporter.importFromString(blob, db2);

      final imported =
          await db2.quarterPlanDao.getPlanForQuarter('2026-07-01');
      expect(imported, isNotNull);
      expect(parseDayMissions(imported!.monthMissionsJson)[0], 'Discovery');
      final goals =
          await db2.quarterPlanDao.getGoalsForPlan(imported.id);
      expect(goals.single.label, 'Land the platform re-plan');
      expect(goals.single.why, 'It unblocks everything else this half');
      expect(goals.single.targetObjectives, 6);
      final weekPlan = await db2.weekPlanDao.getPlanForWeek('2026-08-24');
      final objectives =
          await db2.weekPlanDao.getObjectivesForPlan(weekPlan!.id);
      expect(objectives.single.goalId, gid);
    });
  });
}
