import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';

const _projectId = 'p-test';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.into(db.projects).insert(ProjectsCompanion.insert(
          id: _projectId,
          name: 'Test',
        ));
    await db.programmeGanttDao
        .upsertWorkPackage(TimelineWorkPackagesCompanion(
      id: const Value('wp1'),
      projectId: const Value(_projectId),
      name: const Value('Networking'),
    ));
  });

  tearDown(() => db.close());

  Future<void> seedActivity({
    required String id,
    String? parentId,
    int? startMonth,
    int? endMonth,
    String? startDate,
    String? endDate,
  }) {
    return db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion(
      id: Value(id),
      workPackageId: const Value('wp1'),
      projectId: const Value(_projectId),
      name: Value(id),
      parentActivityId: Value(parentId),
      startMonth: Value(startMonth),
      endMonth: Value(endMonth),
      startDate: Value(startDate),
      endDate: Value(endDate),
    ));
  }

  test('an existing parent window is a commitment — tasks never move it',
      () async {
    await seedActivity(id: 'net', startMonth: 1, endMonth: 2);
    await seedActivity(
        id: 'tg-design', parentId: 'net', startMonth: 2, endMonth: 4);

    await db.programmeGanttDao.seedParentSpanFromTasks('net');

    final net = (await db.programmeGanttDao.getActivityById('net'))!;
    expect(net.startMonth, 1);
    expect(net.endMonth, 2);
  });

  test('a parent with no window gets seeded from its tasks', () async {
    await seedActivity(id: 'net');
    await seedActivity(
        id: 't1',
        parentId: 'net',
        startMonth: 1,
        endMonth: 1,
        startDate: '2026-07-06',
        endDate: '2026-07-17');
    await seedActivity(
        id: 't2',
        parentId: 'net',
        startMonth: 1,
        endMonth: 2,
        startDate: '2026-07-20',
        endDate: '2026-08-07');

    await db.programmeGanttDao.seedParentSpanFromTasks('net');

    final net = (await db.programmeGanttDao.getActivityById('net'))!;
    expect(net.startMonth, 1);
    expect(net.endMonth, 2);
    expect(net.startDate, '2026-07-06');
    expect(net.endDate, '2026-08-07');
  });

  test('seed is a no-op for a childless activity', () async {
    await seedActivity(id: 'solo', startMonth: 4, endMonth: 5);
    await db.programmeGanttDao.seedParentSpanFromTasks('solo');
    final acts =
        await db.programmeGanttDao.getActivitiesForProject(_projectId);
    expect(acts.single.startMonth, 4);
    expect(acts.single.endMonth, 5);
  });

  test('getTasksForActivity returns only the parent\'s tasks', () async {
    await seedActivity(id: 'net');
    await seedActivity(id: 't1', parentId: 'net');
    await seedActivity(id: 'other');
    final tasks = await db.programmeGanttDao.getTasksForActivity('net');
    expect(tasks.map((t) => t.id), ['t1']);
  });

  group('addTask (quick add)', () {
    test('inherits the parent WP and span, appends sort order', () async {
      await seedActivity(
          id: 'net',
          startMonth: 1,
          endMonth: 3,
          startDate: '2026-07-06',
          endDate: '2026-09-18');

      final id1 = await db.programmeGanttDao
          .addTask(id: 'tg', parentId: 'net', name: 'Transit Gateway design');
      final id2 = await db.programmeGanttDao
          .addTask(id: 'vpc', parentId: 'net', name: 'VPC/subnet');

      expect(id1, 'tg');
      expect(id2, 'vpc');
      final tasks = await db.programmeGanttDao.getTasksForActivity('net');
      expect(tasks.map((t) => t.name),
          ['Transit Gateway design', 'VPC/subnet']);
      expect(tasks.first.workPackageId, 'wp1');
      expect(tasks.first.startMonth, 1);
      expect(tasks.first.endMonth, 3);
      expect(tasks.first.startDate, '2026-07-06');
      expect(tasks.last.sortOrder, 1);

      // The parent's committed window is untouched by quick-adds.
      final net = (await db.programmeGanttDao.getActivityById('net'))!;
      expect(net.startMonth, 1);
      expect(net.endMonth, 3);
    });

    test('returns null for a missing parent and creates nothing', () async {
      final id = await db.programmeGanttDao
          .addTask(id: 'x', parentId: 'ghost', name: 'orphan');
      expect(id, isNull);
      expect(await db.programmeGanttDao.getActivityById('x'), isNull);
    });
  });
}
