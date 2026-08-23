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

  Future<void> seedProject(String id, String name) {
    return db.projectDao.upsertProject(ProjectsCompanion(
      id: Value(id),
      name: Value(name),
    ));
  }

  group('plans and blocks', () {
    test('getOrCreatePlanForDate is idempotent per date', () async {
      final a = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-20');
      final b = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-20');
      expect(a.id, b.id);
      final other = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-21');
      expect(other.id, isNot(a.id));
    });

    test('block mutations touch the parent plan updatedAt (sync guard)',
        () async {
      final plan = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-20');
      // Backdate the plan so the touch is observable regardless of the
      // second-granularity DateTime storage.
      final old = DateTime(2020, 1, 1);
      await (db.update(db.dayPlans)
            ..where((t) => t.id.equals(plan.id)))
          .write(DayPlansCompanion(updatedAt: Value(old)));

      await db.dayPlanDao.insertBlock(
        planId: plan.id,
        revision: 0,
        startMinute: 540,
        endMinute: 600,
        label: 'Deep work',
      );

      final refreshed =
          await db.dayPlanDao.getPlanForDate('2026-08-20');
      expect(refreshed!.updatedAt.isAfter(old), isTrue);
    });
  });

  group('startRevision', () {
    test('copies forward blocks starting at/after the revision point '
        'and leaves the old column as the record', () async {
      final plan = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-20');
      await db.dayPlanDao.insertBlock(
          planId: plan.id,
          revision: 0,
          startMinute: 420,
          endMinute: 480,
          label: 'Morning block');
      await db.dayPlanDao.insertBlock(
          planId: plan.id,
          revision: 0,
          startMinute: 510,
          endMinute: 570,
          label: 'Straddler');
      await db.dayPlanDao.insertBlock(
          planId: plan.id,
          revision: 0,
          startMinute: 600,
          endMinute: 660,
          label: 'Afternoon block');

      final rev = await db.dayPlanDao.startRevision(plan.id, 540);
      expect(rev, 1);

      final refreshed = await db.dayPlanDao.getPlanForDate('2026-08-20');
      expect(refreshed!.currentRevision, 1);
      expect(parseRevisionStarts(refreshed.revisionStartsJson), [540]);

      final blocks = await db.dayPlanDao.getBlocksForPlan(plan.id);
      final rev0 = blocks.where((b) => b.revision == 0).toList();
      final rev1 = blocks.where((b) => b.revision == 1).toList();
      // Old column intact; only the 15:00 block (start >= 09:00) copied.
      expect(rev0.length, 3);
      expect(rev1.map((b) => b.label), ['Afternoon block']);

      // Effective schedule: morning + straddler from rev 0, copy from rev 1.
      final schedule =
          effectiveSchedule(blocks, parseRevisionStarts(refreshed.revisionStartsJson));
      expect(schedule.map((b) => '${b.label}/r${b.revision}'), [
        'Morning block/r0',
        'Straddler/r0',
        'Afternoon block/r1',
      ]);
    });
  });

  group('applyImportedPlan (sync guard)', () {
    DayPlansCompanion planCompanion({
      required String id,
      required String date,
      required DateTime updatedAt,
    }) {
      return DayPlansCompanion(
        id: Value(id),
        planDate: Value(date),
        currentRevision: const Value(0),
        revisionStartsJson: const Value('[]'),
        createdAt: Value(updatedAt),
        updatedAt: Value(updatedAt),
      );
    }

    DayPlanBlocksCompanion blockCompanion({
      required String id,
      required String planId,
      String label = 'imported',
    }) {
      final now = DateTime(2026, 1, 1);
      return DayPlanBlocksCompanion(
        id: Value(id),
        dayPlanId: Value(planId),
        revision: const Value(0),
        startMinute: const Value(540),
        endMinute: const Value(600),
        kind: const Value('focus'),
        label: Value(label),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
    }

    test('inserts when the date is unknown locally', () async {
      final applied = await db.dayPlanDao.applyImportedPlan(
        plan: planCompanion(
            id: 'remote-1',
            date: '2026-08-20',
            updatedAt: DateTime(2026, 8, 20, 8)),
        blocks: [blockCompanion(id: 'rb-1', planId: 'remote-1')],
      );
      expect(applied, isTrue);
      final local = await db.dayPlanDao.getPlanForDate('2026-08-20');
      expect(local!.id, 'remote-1');
      expect((await db.dayPlanDao.getBlocksForPlan('remote-1')).length, 1);
    });

    test('a stale incoming copy never clobbers a newer local day — '
        'matched by date even when ids differ', () async {
      await db.dayPlanDao.applyImportedPlan(
        plan: planCompanion(
            id: 'local-1',
            date: '2026-08-20',
            updatedAt: DateTime(2026, 8, 20, 12)),
        blocks: [
          blockCompanion(id: 'lb-1', planId: 'local-1', label: 'newer')
        ],
      );

      final applied = await db.dayPlanDao.applyImportedPlan(
        plan: planCompanion(
            id: 'other-machine',
            date: '2026-08-20',
            updatedAt: DateTime(2026, 8, 20, 9)),
        blocks: [
          blockCompanion(
              id: 'ob-1', planId: 'other-machine', label: 'stale')
        ],
      );
      expect(applied, isFalse);
      final local = await db.dayPlanDao.getPlanForDate('2026-08-20');
      expect(local!.id, 'local-1');
    });

    test('a newer incoming copy replaces the local day wholesale '
        '(block deletions propagate)', () async {
      await db.dayPlanDao.applyImportedPlan(
        plan: planCompanion(
            id: 'local-1',
            date: '2026-08-20',
            updatedAt: DateTime(2026, 8, 20, 9)),
        blocks: [
          blockCompanion(id: 'lb-1', planId: 'local-1'),
          blockCompanion(id: 'lb-2', planId: 'local-1'),
        ],
      );

      final applied = await db.dayPlanDao.applyImportedPlan(
        plan: planCompanion(
            id: 'other-machine',
            date: '2026-08-20',
            updatedAt: DateTime(2026, 8, 20, 15)),
        blocks: [
          blockCompanion(id: 'ob-1', planId: 'other-machine'),
        ],
      );
      expect(applied, isTrue);
      final local = await db.dayPlanDao.getPlanForDate('2026-08-20');
      expect(local!.id, 'other-machine');
      final blocks =
          await db.dayPlanDao.getBlocksForPlan('other-machine');
      expect(blocks.length, 1);
      expect(await db.dayPlanDao.getBlocksForPlan('local-1'), isEmpty);
    });
  });

  group('cross-project planning material', () {
    test('overdue query spans projects, excludes closed and cascaded rows',
        () async {
      await seedProject('p1', 'Alpha');
      await seedProject('p2', 'Beta');
      Future<void> action(String id, String pid, String desc,
          {String status = 'open', String? sourceProjectId}) {
        return db.actionsDao.insertAction(ProjectActionsCompanion.insert(
          id: id,
          projectId: pid,
          description: desc,
          dueDate: const Value('2020-01-01'),
          status: Value(status),
          sourceProjectId: Value(sourceProjectId),
        ));
      }

      await action('a1', 'p1', 'Fix Alpha thing');
      await action('a2', 'p2', 'Fix Beta thing');
      await action('a3', 'p1', 'Already done', status: 'closed');
      await action('a4', 'p2', 'Cascaded copy', sourceProjectId: 'p1');

      final items =
          await db.dayPlanDao.watchOverdueActionsAllProjects().first;
      expect(items.map((i) => i.action.id).toSet(), {'a1', 'a2'});
      expect(
        items.map((i) => i.projectName).toSet(),
        {'Alpha', 'Beta'},
      );
    });

    test('browse query lists ALL open actions across projects, '
        'dated first, closed and cascaded excluded', () async {
      await seedProject('p1', 'Alpha');
      await seedProject('p2', 'Beta');
      Future<void> action(String id, String pid, String desc,
          {String? dueDate,
          String status = 'open',
          String? sourceProjectId}) {
        return db.actionsDao.insertAction(ProjectActionsCompanion.insert(
          id: id,
          projectId: pid,
          description: desc,
          dueDate: Value(dueDate),
          status: Value(status),
          sourceProjectId: Value(sourceProjectId),
        ));
      }

      await action('undated', 'p1', 'Someday thing');
      await action('later', 'p2', 'Later thing', dueDate: '2030-06-01');
      await action('soon', 'p1', 'Soon thing', dueDate: '2026-09-01');
      await action('closed', 'p1', 'Done thing',
          dueDate: '2026-09-01', status: 'closed');
      await action('cascaded', 'p2', 'Copy', sourceProjectId: 'p1');

      final items =
          await db.dayPlanDao.watchOpenActionsAllProjects().first;
      expect(items.map((i) => i.action.id), ['soon', 'later', 'undated']);
    });

    test('browse risks include open and in-progress, never settled states',
        () async {
      await seedProject('p1', 'Alpha');
      Future<void> risk(String id, String status) {
        return db.raidDao.upsertRisk(RisksCompanion.insert(
          id: id,
          projectId: 'p1',
          description: 'Risk $id',
          status: Value(status),
        ));
      }

      await risk('r-open', 'open');
      await risk('r-prog', 'in progress');
      await risk('r-closed', 'closed');
      await risk('r-accepted', 'accepted');

      final items = await db.dayPlanDao.watchOpenRisksAllProjects().first;
      expect(items.map((i) => i.risk.id).toSet(), {'r-open', 'r-prog'});
    });
  });

  group('sync round trip', () {
    test('day plans ride in the project blob and re-import on a fresh '
        'machine', () async {
      await seedProject('p1', 'Alpha');
      final plan = await db.dayPlanDao.getOrCreatePlanForDate('2026-08-20');
      await db.dayPlanDao.insertBlock(
          planId: plan.id,
          revision: 0,
          startMinute: 540,
          endMinute: 630,
          label: 'Re-plan AWS enablement',
          kind: 'focus',
          projectId: 'p1');

      final blob = await JsonExporter.exportProjectToString(
          projectId: 'p1', db: db);

      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db2.close);
      await JsonImporter.importFromString(blob, db2);

      final imported = await db2.dayPlanDao.getPlanForDate('2026-08-20');
      expect(imported, isNotNull);
      final blocks = await db2.dayPlanDao.getBlocksForPlan(imported!.id);
      expect(blocks.single.label, 'Re-plan AWS enablement');
      expect(blocks.single.startMinute, 540);
      expect(blocks.single.projectId, 'p1');
    });
  });
}
