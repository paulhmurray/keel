import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/timeline/gantt/dependency_chains.dart';

/// Drift-free helpers — construct rows via the Companion + insert into
/// an in-memory db. Cheaper than mocking the entire data layer just to
/// exercise pure walk logic.
TimelineDependency _dep(String from, String to,
        {String type = 'finish_to_start'}) =>
    TimelineDependency(
      id: 'd-$from-$to',
      projectId: 'p1',
      fromActivityId: from,
      toActivityId: to,
      dependencyType: type,
      createdAt: DateTime(2026, 1, 1),
    );

TimelineActivity _act(
  String id, {
  int? start,
  int? end,
}) =>
    TimelineActivity(
      id: id,
      projectId: 'p1',
      workPackageId: 'wp1',
      name: id,
      activityType: 'activity',
      status: 'not_started',
      startMonth: start,
      endMonth: end,
      isCritical: false,
      isBaseline: false,
      sortOrder: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('DependencyChains.upstreamOf', () {
    test('walks back through all predecessors transitively', () {
      // a → b → c → d
      final deps = [_dep('a', 'b'), _dep('b', 'c'), _dep('c', 'd')];
      expect(DependencyChains.upstreamOf('d', deps), {'a', 'b', 'c'});
      expect(DependencyChains.upstreamOf('c', deps), {'a', 'b'});
      expect(DependencyChains.upstreamOf('a', deps), isEmpty);
    });

    test('handles a fan-in — multiple direct predecessors', () {
      // a ↘
      //    c
      // b ↗
      final deps = [_dep('a', 'c'), _dep('b', 'c')];
      expect(DependencyChains.upstreamOf('c', deps), {'a', 'b'});
    });

    test('cycle-safe — does not stack-overflow on a → b → a', () {
      final deps = [_dep('a', 'b'), _dep('b', 'a')];
      // Either set is reasonable as long as the call terminates.
      final out = DependencyChains.upstreamOf('a', deps);
      expect(out, contains('b'));
    });
  });

  group('DependencyChains.downstreamOf', () {
    test('walks forward through successors transitively', () {
      final deps = [_dep('a', 'b'), _dep('b', 'c'), _dep('c', 'd')];
      expect(DependencyChains.downstreamOf('a', deps), {'b', 'c', 'd'});
      expect(DependencyChains.downstreamOf('b', deps), {'c', 'd'});
      expect(DependencyChains.downstreamOf('d', deps), isEmpty);
    });

    test('handles a fan-out — multiple direct successors', () {
      final deps = [_dep('a', 'b'), _dep('a', 'c')];
      expect(DependencyChains.downstreamOf('a', deps), {'b', 'c'});
    });
  });

  group('DependencyChains.isBroken', () {
    test(
        'FS: broken when successor starts before predecessor finishes',
        () {
      final byId = {
        'a': _act('a', start: 0, end: 4),
        'b': _act('b', start: 2, end: 6),
      };
      expect(DependencyChains.isBroken(_dep('a', 'b'), byId), isTrue);
    });

    test('FS: not broken when successor starts at predecessor finish',
        () {
      final byId = {
        'a': _act('a', start: 0, end: 4),
        'b': _act('b', start: 4, end: 6),
      };
      expect(DependencyChains.isBroken(_dep('a', 'b'), byId), isFalse);
    });

    test('SS: broken when successor starts before predecessor starts',
        () {
      final byId = {
        'a': _act('a', start: 4, end: 6),
        'b': _act('b', start: 2, end: 5),
      };
      expect(
        DependencyChains.isBroken(
            _dep('a', 'b', type: 'start_to_start'), byId),
        isTrue,
      );
    });

    test('FF: broken when successor finishes before predecessor finishes',
        () {
      final byId = {
        'a': _act('a', start: 0, end: 6),
        'b': _act('b', start: 0, end: 4),
      };
      expect(
        DependencyChains.isBroken(
            _dep('a', 'b', type: 'finish_to_finish'), byId),
        isTrue,
      );
    });

    test('external is never broken', () {
      final byId = {
        'a': _act('a', start: 5, end: 8),
        'b': _act('b', start: 0, end: 2),
      };
      expect(
        DependencyChains.isBroken(
            _dep('a', 'b', type: 'external'), byId),
        isFalse,
      );
    });

    test('missing dates → not broken (we can\'t prove violation)', () {
      final byId = {
        'a': _act('a'), // no dates
        'b': _act('b', start: 2),
      };
      expect(DependencyChains.isBroken(_dep('a', 'b'), byId), isFalse);
    });

    test('missing activity → not broken', () {
      final byId = {'a': _act('a', start: 0, end: 4)};
      expect(DependencyChains.isBroken(_dep('a', 'missing'), byId),
          isFalse);
    });
  });

  group('DependencyChains.shortLabel', () {
    test('maps the four canonical dep types to compact labels', () {
      expect(DependencyChains.shortLabel('finish_to_start'), 'FS');
      expect(DependencyChains.shortLabel('start_to_start'), 'SS');
      expect(DependencyChains.shortLabel('finish_to_finish'), 'FF');
      expect(DependencyChains.shortLabel('external'), 'EXT');
    });

    test('unknown type defaults to FS', () {
      expect(DependencyChains.shortLabel('weird_new_type'), 'FS');
    });
  });

  group('replaceInboundDependencies (DAO)', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.memory();
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P1'));
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: 'wp1',
          projectId: 'p1',
          name: 'WP1',
        ),
      );
      for (final id in ['a', 'b', 'c', 'd']) {
        await db.programmeGanttDao.upsertActivity(
          TimelineActivitiesCompanion.insert(
            id: id,
            projectId: 'p1',
            workPackageId: 'wp1',
            name: id,
            startMonth: const Value(0),
            endMonth: const Value(0),
          ),
        );
      }
    });
    tearDown(() async => db.close());

    test('inserts new rows for previously-empty inbound set', () async {
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [
          DependencySpec.internal(
              fromActivityId: 'a', dependencyType: 'finish_to_start'),
          DependencySpec.internal(
              fromActivityId: 'b', dependencyType: 'start_to_start'),
        ],
      );
      final rows =
          await db.programmeGanttDao.getInboundDependenciesFor('d');
      expect(rows, hasLength(2));
      final byFrom = {for (final r in rows) r.fromActivityId: r};
      expect(byFrom['a']!.dependencyType, 'finish_to_start');
      expect(byFrom['b']!.dependencyType, 'start_to_start');
    });

    test('removes rows no longer in desired set', () async {
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [
          DependencySpec.internal(
              fromActivityId: 'a', dependencyType: 'finish_to_start'),
          DependencySpec.internal(
              fromActivityId: 'b', dependencyType: 'finish_to_start'),
        ],
      );
      // Then ask for just `a`.
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [
          DependencySpec.internal(
              fromActivityId: 'a', dependencyType: 'finish_to_start'),
        ],
      );
      final rows =
          await db.programmeGanttDao.getInboundDependenciesFor('d');
      expect(rows.map((r) => r.fromActivityId), ['a']);
    });

    test('updates an existing row when the type changes', () async {
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [
          DependencySpec.internal(
              fromActivityId: 'a', dependencyType: 'finish_to_start'),
        ],
      );
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [
          DependencySpec.internal(
              fromActivityId: 'a', dependencyType: 'start_to_start'),
        ],
      );
      final rows =
          await db.programmeGanttDao.getInboundDependenciesFor('d');
      expect(rows.single.dependencyType, 'start_to_start');
    });

    test(
        'inbound rows for OTHER activities are untouched', () async {
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'c',
        desired: [
          DependencySpec.internal(
              fromActivityId: 'a', dependencyType: 'finish_to_start'),
        ],
      );
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [
          DependencySpec.internal(
              fromActivityId: 'b', dependencyType: 'finish_to_start'),
        ],
      );
      expect(
        (await db.programmeGanttDao.getInboundDependenciesFor('c'))
            .map((r) => r.fromActivityId),
        ['a'],
      );
      expect(
        (await db.programmeGanttDao.getInboundDependenciesFor('d'))
            .map((r) => r.fromActivityId),
        ['b'],
      );
    });

    test('persists an external dep with its label and EXT type',
        () async {
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [DependencySpec.external('Vendor API release')],
      );
      final row = (await db.programmeGanttDao
              .getInboundDependenciesFor('d'))
          .single;
      expect(row.externalLabel, 'Vendor API release');
      expect(row.dependencyType, 'external');
      // No source activity for externals — stored as empty string
      // sentinel so the not-null constraint holds.
      expect(row.fromActivityId, '');
    });

    test(
        'mixed internal + external: both kinds round-trip in one call',
        () async {
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [
          DependencySpec.internal(
              fromActivityId: 'a', dependencyType: 'finish_to_start'),
          DependencySpec.external('Legal sign-off'),
        ],
      );
      final rows =
          await db.programmeGanttDao.getInboundDependenciesFor('d');
      expect(rows, hasLength(2));
      final internals =
          rows.where((r) => r.externalLabel == null).toList();
      final externals =
          rows.where((r) => r.externalLabel != null).toList();
      expect(internals.single.fromActivityId, 'a');
      expect(externals.single.externalLabel, 'Legal sign-off');
    });

    test('removing an external by dropping it from desired works',
        () async {
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [
          DependencySpec.external('Vendor A'),
          DependencySpec.external('Vendor B'),
        ],
      );
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [DependencySpec.external('Vendor A')],
      );
      final rows =
          await db.programmeGanttDao.getInboundDependenciesFor('d');
      expect(rows.map((r) => r.externalLabel), ['Vendor A']);
    });

    test(
        'externals keyed by label — same label twice does NOT '
        'duplicate the row on re-save', () async {
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [DependencySpec.external('Vendor A')],
      );
      await db.programmeGanttDao.replaceInboundDependencies(
        projectId: 'p1',
        activityId: 'd',
        desired: [DependencySpec.external('Vendor A')],
      );
      expect(
        (await db.programmeGanttDao.getInboundDependenciesFor('d')),
        hasLength(1),
      );
    });
  });
}
