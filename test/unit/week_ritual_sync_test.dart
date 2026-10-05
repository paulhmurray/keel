import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/import/json_importer.dart';

/// The v67 week-ritual columns ride the sync blob like the rest of the
/// week layer. An export from one machine imported on another must keep
/// the day allocations, the carry-over link and the charted/reviewed
/// stamps — the importer enumerates columns by hand, so this is the test
/// that catches a forgotten field.
void main() {
  late AppDatabase db;
  late AppDatabase other;

  setUp(() async {
    db = AppDatabase.memory();
    other = AppDatabase.memory();
    for (final d in [db, other]) {
      await d.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P'));
    }
  });
  tearDown(() async {
    await db.close();
    await other.close();
  });

  test('allocations, carry-over and stamps survive export and import',
      () async {
    final last = await db.weekPlanDao.getOrCreatePlanForWeek('2026-09-28');
    final oldId = await db.weekPlanDao.insertObjective(
        planId: last.id, label: 'Finish the adapter', targetBlocks: 6);
    await db.weekPlanDao.setReview(last.id, note: 'Too many meetings on Tuesday.');

    final week = await db.weekPlanDao.getOrCreatePlanForWeek('2026-10-05');
    final id = await db.weekPlanDao.insertObjective(
      planId: week.id,
      label: 'Finish the adapter',
      targetBlocks: 6,
      dayAllocationsJson: '{"0":2,"2":4}',
      carriedFromId: oldId,
    );
    await db.weekPlanDao.setDayMission(week.id, 0, 'Adapter, heads down');
    await db.weekPlanDao.markCharted(week.id);

    final blob = await JsonExporter.exportProjectToString(projectId: 'p1', db: db);
    await JsonImporter.importFromString(blob, other);

    final importedWeek = (await other.weekPlanDao.getPlanForWeek('2026-10-05'))!;
    expect(importedWeek.chartedAt, isNotNull);
    expect(importedWeek.reviewedAt, isNull);
    final objs = await other.weekPlanDao.getObjectivesForPlan(importedWeek.id);
    expect(objs.single.id, id);
    expect(objs.single.dayAllocationsJson, '{"0":2,"2":4}');
    expect(objs.single.carriedFromId, oldId);
    expect(objs.single.targetBlocks, 6);

    final importedLast = (await other.weekPlanDao.getPlanForWeek('2026-09-28'))!;
    expect(importedLast.reviewedAt, isNotNull);
    expect(importedLast.reviewNote, 'Too many meetings on Tuesday.');
  });

  test('a pre-v67 blob imports with the new fields at their defaults',
      () async {
    final week = await db.weekPlanDao.getOrCreatePlanForWeek('2026-10-05');
    await db.weekPlanDao.insertObjective(planId: week.id, label: 'x');
    final blob = await JsonExporter.exportProjectToString(projectId: 'p1', db: db);
    // Strip the new keys as an older Keel would never have written them.
    final stripped = blob
        .replaceAll(RegExp(r'"day_allocations_json":"[^"]*",?'), '')
        .replaceAll(RegExp(r'"charted_at":[^,}]*,?'), '')
        .replaceAll(RegExp(r'"carried_from_id":[^,}]*,?'), '');
    await JsonImporter.importFromString(stripped, other);
    final w = (await other.weekPlanDao.getPlanForWeek('2026-10-05'))!;
    expect(w.chartedAt, isNull);
    final o = (await other.weekPlanDao.getObjectivesForPlan(w.id)).single;
    expect(o.dayAllocationsJson, '{}');
    expect(o.carriedFromId, isNull);
  });

  test('the stamps touch the week so the sync guard sees them', () async {
    final week = await db.weekPlanDao.getOrCreatePlanForWeek('2026-10-05');
    final before = week.updatedAt;
    await db.weekPlanDao.markCharted(week.id);
    final after = (await db.weekPlanDao.getPlanForWeek('2026-10-05'))!;
    expect(after.chartedAt, isNotNull);
    // Stored at second precision, so "not earlier" is what can be proven.
    expect(after.updatedAt.isBefore(before), isFalse);
    await db.weekPlanDao.updateObjective(
        week.id,
        WeekPlanObjectivesCompanion(
          id: Value(await db.weekPlanDao.insertObjective(planId: week.id, label: 'y')),
          dayAllocationsJson: const Value('{"1":3}'),
        ));
    final objs = await db.weekPlanDao.getObjectivesForPlan(week.id);
    expect(objs.single.dayAllocationsJson, '{"1":3}');
  });
}
