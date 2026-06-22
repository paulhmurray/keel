import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P1'));
  });

  tearDown(() async => db.close());

  Future<void> insertWp(String id, int sortOrder, {String name = 'WP'}) =>
      db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: id,
          projectId: 'p1',
          name: name,
          sortOrder: Value(sortOrder),
        ),
      );

  Future<void> insertActivity(
    String id,
    String wpId,
    int sortOrder, {
    String name = 'A',
  }) =>
      db.programmeGanttDao.upsertActivity(
        TimelineActivitiesCompanion.insert(
          id: id,
          projectId: 'p1',
          workPackageId: wpId,
          name: name,
          startMonth: const Value(0),
          endMonth: const Value(0),
          sortOrder: Value(sortOrder),
        ),
      );

  group('reorderWorkPackages', () {
    test('rewrites sortOrder so the listed ids match their list index',
        () async {
      await insertWp('a', 0);
      await insertWp('b', 1);
      await insertWp('c', 2);

      // Move c to the top.
      await db.programmeGanttDao
          .reorderWorkPackages('p1', ['c', 'a', 'b']);

      final wps = await db.programmeGanttDao.getWorkPackages('p1');
      expect(wps.map((w) => w.id).toList(), ['c', 'a', 'b']);
      expect(wps.map((w) => w.sortOrder).toList(), [0, 1, 2]);
    });

    test('is idempotent — running the same order twice is a no-op',
        () async {
      await insertWp('a', 0);
      await insertWp('b', 1);
      await db.programmeGanttDao.reorderWorkPackages('p1', ['b', 'a']);
      await db.programmeGanttDao.reorderWorkPackages('p1', ['b', 'a']);
      final wps = await db.programmeGanttDao.getWorkPackages('p1');
      expect(wps.map((w) => w.id).toList(), ['b', 'a']);
    });

    test('rejects ids that belong to a different project', () async {
      await insertWp('a', 0);
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p2', name: 'P2'));
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: 'foreign',
          projectId: 'p2',
          name: 'foreign',
        ),
      );

      // Passing a cross-project id should not reposition it under p1.
      await db.programmeGanttDao
          .reorderWorkPackages('p1', ['foreign', 'a']);

      // p1's WP `a` should still be the only WP in p1, untouched.
      final p1Wps = await db.programmeGanttDao.getWorkPackages('p1');
      expect(p1Wps.map((w) => w.id), ['a']);
      // The foreign WP stays in p2 with its original sortOrder.
      final p2Wps = await db.programmeGanttDao.getWorkPackages('p2');
      expect(p2Wps.single.id, 'foreign');
    });

    test('empty list is a no-op', () async {
      await insertWp('a', 0);
      await insertWp('b', 1);
      await db.programmeGanttDao.reorderWorkPackages('p1', const []);
      final wps = await db.programmeGanttDao.getWorkPackages('p1');
      expect(wps.map((w) => w.id), ['a', 'b']);
    });
  });

  group('reorderActivitiesWithinWp', () {
    test('rewrites sortOrder for activities under the given WP', () async {
      await insertWp('wp1', 0);
      await insertActivity('a1', 'wp1', 0);
      await insertActivity('a2', 'wp1', 1);
      await insertActivity('a3', 'wp1', 2);

      // Move a3 above a1.
      await db.programmeGanttDao
          .reorderActivitiesWithinWp('wp1', ['a3', 'a1', 'a2']);

      final acts =
          await db.programmeGanttDao.getActivitiesForWP('wp1');
      expect(acts.map((a) => a.id).toList(), ['a3', 'a1', 'a2']);
      expect(acts.map((a) => a.sortOrder).toList(), [0, 1, 2]);
    });

    test(
        'will not pull an activity belonging to a different WP into '
        'this WP — cross-WP ids are filtered out', () async {
      await insertWp('wp1', 0);
      await insertWp('wp2', 1);
      await insertActivity('a1', 'wp1', 0);
      await insertActivity('foreign', 'wp2', 0);

      // Pass an id from wp2 — it should NOT be repositioned under wp1.
      await db.programmeGanttDao.reorderActivitiesWithinWp(
        'wp1',
        ['foreign', 'a1'],
      );

      // a1 remains under wp1.
      final wp1Acts =
          await db.programmeGanttDao.getActivitiesForWP('wp1');
      expect(wp1Acts.map((a) => a.id), ['a1']);
      // foreign stays under wp2 untouched.
      final wp2Acts =
          await db.programmeGanttDao.getActivitiesForWP('wp2');
      expect(wp2Acts.single.id, 'foreign');
      expect(wp2Acts.single.workPackageId, 'wp2');
    });

    test('leaves sibling activities NOT in the list alone', () async {
      await insertWp('wp1', 0);
      await insertActivity('a1', 'wp1', 0);
      await insertActivity('a2', 'wp1', 1);
      await insertActivity('a3', 'wp1', 2);

      // Only renumber a2 and a3 (a1 should keep its sortOrder=0).
      await db.programmeGanttDao
          .reorderActivitiesWithinWp('wp1', ['a3', 'a2']);

      final acts =
          await db.programmeGanttDao.getActivitiesForWP('wp1');
      // Result ordering by sortOrder ASC: a1 (0), a3 (0)/a2 (1)
      // a1 keeps 0; a3 now 0; a2 now 1. Ties on 0 between a1/a3 — both
      // present, ordering between them is implementation-defined but
      // both must remain in the project.
      final ids = acts.map((a) => a.id).toSet();
      expect(ids, {'a1', 'a2', 'a3'});
      final byId = {for (final a in acts) a.id: a.sortOrder};
      expect(byId['a3'], 0);
      expect(byId['a2'], 1);
      expect(byId['a1'], 0); // untouched
    });
  });
}
