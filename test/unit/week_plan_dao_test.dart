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

  group('week helpers', () {
    test('mondayOf lands on the Monday of any weekday', () {
      // 2026-08-27 is a Thursday.
      expect(mondayOf(DateTime(2026, 8, 27)), DateTime(2026, 8, 24));
      expect(mondayOf(DateTime(2026, 8, 24)), DateTime(2026, 8, 24));
      expect(mondayOf(DateTime(2026, 8, 30)), DateTime(2026, 8, 24));
    });

    test('parseDayMissions round-trips and survives malformed json', () {
      expect(parseDayMissions('{"0":"Deep work","4":"Admin day"}'),
          {0: 'Deep work', 4: 'Admin day'});
      expect(parseDayMissions('not json'), isEmpty);
    });
  });

  group('plans, missions, objectives', () {
    test('getOrCreatePlanForWeek is idempotent per week', () async {
      final a = await db.weekPlanDao.getOrCreatePlanForWeek('2026-08-24');
      final b = await db.weekPlanDao.getOrCreatePlanForWeek('2026-08-24');
      expect(a.id, b.id);
    });

    test('mission and objective mutations touch the plan updatedAt '
        '(the sync guard)', () async {
      final plan =
          await db.weekPlanDao.getOrCreatePlanForWeek('2026-08-24');
      final old = DateTime(2020, 1, 1);
      Future<void> backdate() => (db.update(db.weekPlans)
            ..where((t) => t.id.equals(plan.id)))
          .write(WeekPlansCompanion(updatedAt: Value(old)));
      Future<DateTime> updatedAt() async =>
          (await db.weekPlanDao.getPlanForWeek('2026-08-24'))!.updatedAt;

      await backdate();
      await db.weekPlanDao.setDayMission(plan.id, 2, 'Deep work day');
      expect((await updatedAt()).isAfter(old), isTrue);

      await backdate();
      final oid = await db.weekPlanDao
          .insertObjective(planId: plan.id, label: 'Big rock');
      expect((await updatedAt()).isAfter(old), isTrue);

      await backdate();
      await db.weekPlanDao.setObjectiveDone(plan.id, oid, true);
      expect((await updatedAt()).isAfter(old), isTrue);
    });

    test('deleting an objective unlinks its blocks but keeps them',
        () async {
      final week =
          await db.weekPlanDao.getOrCreatePlanForWeek('2026-08-24');
      final oid = await db.weekPlanDao
          .insertObjective(planId: week.id, label: 'Rock');
      final day = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-25');
      final blockId = await db.dayPlanDao.insertBlock(
          planId: day.id,
          revision: 0,
          startMinute: 540,
          endMinute: 600,
          label: 'Rock work',
          objectiveId: oid);

      await db.weekPlanDao.deleteObjective(week.id, oid);
      final blocks = await db.dayPlanDao.getBlocksForPlan(day.id);
      expect(blocks.single.id, blockId);
      expect(blocks.single.objectiveId, isNull);
      expect(blocks.single.label, 'Rock work');
    });
  });

  group('objective progress', () {
    test('counts done effective blocks only — superseded copies excluded',
        () async {
      final week =
          await db.weekPlanDao.getOrCreatePlanForWeek('2026-08-24');
      final oid = await db.weekPlanDao
          .insertObjective(planId: week.id, label: 'Rock', targetBlocks: 3);
      final day = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-25');
      // Done block in the morning (stays effective after revision).
      final b1 = await db.dayPlanDao.insertBlock(
          planId: day.id,
          revision: 0,
          startMinute: 420,
          endMinute: 480,
          label: 'r1',
          objectiveId: oid);
      await db.dayPlanDao.setBlockDone(day.id, b1, true);
      // Afternoon block that gets superseded by a revision at 09:00 —
      // its copy in revision 1 is the one that counts.
      final b2 = await db.dayPlanDao.insertBlock(
          planId: day.id,
          revision: 0,
          startMinute: 600,
          endMinute: 660,
          label: 'r2',
          objectiveId: oid);
      await db.dayPlanDao.setBlockDone(day.id, b2, true);
      await db.dayPlanDao.startRevision(day.id, 540);

      final rows = await db.weekPlanDao
          .watchBlocksForWeek('2026-08-24', '2026-08-30')
          .first;
      final startsByPlan = <String, List<int>>{
        for (final r in rows)
          r.plan.id: parseRevisionStarts(r.plan.revisionStartsJson),
      };
      final done = objectiveDoneBlocks(
          oid, rows.map((r) => r.block).toList(), startsByPlan);
      // b1 (rev 0, morning) + the rev-1 copy of b2 — NOT the superseded
      // rev-0 b2, which would double-count.
      expect(done, 2);
    });

    test('watchBlocksForWeek only returns the requested week', () async {
      final inWeek =
          await db.dayPlanDao.getOrCreatePlanForDate('2026-08-26');
      final outOfWeek =
          await db.dayPlanDao.getOrCreatePlanForDate('2026-09-02');
      await db.dayPlanDao.insertBlock(
          planId: inWeek.id,
          revision: 0,
          startMinute: 540,
          endMinute: 600,
          label: 'in');
      await db.dayPlanDao.insertBlock(
          planId: outOfWeek.id,
          revision: 0,
          startMinute: 540,
          endMinute: 600,
          label: 'out');

      final rows = await db.weekPlanDao
          .watchBlocksForWeek('2026-08-24', '2026-08-30')
          .first;
      expect(rows.single.block.label, 'in');
    });
  });

  group('sync', () {
    test('stale incoming week never clobbers a newer local one', () async {
      await db.weekPlanDao.applyImportedPlan(
        plan: WeekPlansCompanion(
          id: const Value('local'),
          weekStartDate: const Value('2026-08-24'),
          createdAt: Value(DateTime(2026, 8, 24)),
          updatedAt: Value(DateTime(2026, 8, 26, 12)),
        ),
        objectives: const [],
      );
      final applied = await db.weekPlanDao.applyImportedPlan(
        plan: WeekPlansCompanion(
          id: const Value('other-machine'),
          weekStartDate: const Value('2026-08-24'),
          createdAt: Value(DateTime(2026, 8, 24)),
          updatedAt: Value(DateTime(2026, 8, 25)),
        ),
        objectives: const [],
      );
      expect(applied, isFalse);
      expect((await db.weekPlanDao.getPlanForWeek('2026-08-24'))!.id,
          'local');
    });

    test('week plans + objectives + block links round-trip the blob',
        () async {
      await db.projectDao.upsertProject(const ProjectsCompanion(
        id: Value('p1'),
        name: Value('Alpha'),
      ));
      final week =
          await db.weekPlanDao.getOrCreatePlanForWeek('2026-08-24');
      await db.weekPlanDao.setDayMission(week.id, 0, 'Clear the decks');
      final oid = await db.weekPlanDao.insertObjective(
          planId: week.id, label: 'Ship weekly planner', targetBlocks: 4);
      final day = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-27');
      await db.dayPlanDao.insertBlock(
          planId: day.id,
          revision: 0,
          startMinute: 540,
          endMinute: 630,
          label: 'Ship it',
          objectiveId: oid);

      final blob = await JsonExporter.exportProjectToString(
          projectId: 'p1', db: db);
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db2.close);
      await JsonImporter.importFromString(blob, db2);

      final imported = await db2.weekPlanDao.getPlanForWeek('2026-08-24');
      expect(imported, isNotNull);
      expect(parseDayMissions(imported!.dayMissionsJson)[0],
          'Clear the decks');
      final objectives =
          await db2.weekPlanDao.getObjectivesForPlan(imported.id);
      expect(objectives.single.label, 'Ship weekly planner');
      expect(objectives.single.targetBlocks, 4);
      final dayPlan = await db2.dayPlanDao.getPlanForDate('2026-08-27');
      final blocks = await db2.dayPlanDao.getBlocksForPlan(dayPlan!.id);
      expect(blocks.single.objectiveId, oid);
    });
  });
}
