import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/dependency_plan_link.dart';
import 'package:keel/core/raid/raid_conversion_service.dart';

const _pid = 'p-plan-link';

Future<void> _seedPlan(AppDatabase db) async {
  await db.into(db.projects).insert(
      ProjectsCompanion.insert(id: _pid, name: 'Plan link test'));
  await db.programmeGanttDao.upsertWorkPackage(TimelineWorkPackagesCompanion(
    id: const Value('wp1'),
    projectId: const Value(_pid),
    name: const Value('WP1'),
    sortOrder: const Value(0),
  ));
  await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion(
    id: const Value('act1'),
    workPackageId: const Value('wp1'),
    projectId: const Value(_pid),
    name: const Value('Build'),
    startMonth: const Value(2),
    endMonth: const Value(4),
    sortOrder: const Value(0),
  ));
  await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion(
    id: const Value('act2'),
    workPackageId: const Value('wp1'),
    projectId: const Value(_pid),
    name: const Value('Test'),
    startMonth: const Value(4),
    endMonth: const Value(5),
    sortOrder: const Value(1),
  ));
}

Future<void> _seedDependency(AppDatabase db,
    {String id = 'dep1', String type = 'inbound'}) async {
  await db.raidDao.upsertDependency(ProgramDependenciesCompanion(
    id: Value(id),
    projectId: const Value(_pid),
    ref: const Value('D7'),
    description: const Value('Vendor delivers the signed API contract'),
    dependencyType: Value(type),
    planActivityId: const Value('act1'),
  ));
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await _seedPlan(db);
  });

  tearDown(() => db.close());

  group('pure helpers', () {
    test('note round-trips the dependency id', () {
      final note = DependencyPlanLink.noteFor('abc');
      expect(DependencyPlanLink.dependencyIdFromNote(note), 'abc');
      expect(DependencyPlanLink.dependencyIdFromNote('free text'), isNull);
      expect(DependencyPlanLink.dependencyIdFromNote(null), isNull);
    });

    test('label is "ref · description", truncated', () {
      expect(DependencyPlanLink.labelFor(ref: 'D3', description: 'Keys'),
          'D3 · Keys');
      expect(DependencyPlanLink.labelFor(ref: null, description: 'Keys'),
          'Keys');
      final long = 'x' * 80;
      final label = DependencyPlanLink.labelFor(ref: 'D1', description: long);
      expect(label.length, lessThan(70));
      expect(label, endsWith('…'));
    });

    test('decision markers use their own prefix and never collide', () {
      final dep = DependencyPlanLink.noteFor('x');
      final dec = DependencyPlanLink.noteFor('x', kind: PlanLinkKind.decision);
      expect(dep, isNot(dec));
      expect(DependencyPlanLink.itemIdFromNote(dec, kind: PlanLinkKind.decision), 'x');
      expect(DependencyPlanLink.itemIdFromNote(dec), isNull);
      expect(DependencyPlanLink.dependencyIdFromNote(dep), 'x');
    });

    test('only inbound and bilateral can be drawn into the plan', () {
      expect(DependencyPlanLink.canShowOnPlan('inbound'), isTrue);
      expect(DependencyPlanLink.canShowOnPlan('bilateral'), isTrue);
      expect(DependencyPlanLink.canShowOnPlan('outbound'), isFalse);
    });
  });

  group('sync', () {
    test('creates an external timeline dependency into the activity',
        () async {
      await _seedDependency(db);
      await DependencyPlanLink.sync(db,
          projectId: _pid,
          dependencyId: 'dep1',
          ref: 'D7',
          description: 'Vendor delivers the signed API contract',
          dependencyType: 'inbound',
          activityId: 'act1',
          show: true);

      final rows = await db.programmeGanttDao.getDependencies(_pid);
      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.dependencyType, 'external');
      expect(r.fromActivityId, '');
      expect(r.toActivityId, 'act1');
      expect(r.externalLabel, 'D7 · Vendor delivers the signed API contract');
      expect(r.notes, DependencyPlanLink.noteFor('dep1'));
      expect((await DependencyPlanLink.find(db, _pid, 'dep1'))?.id, r.id);
    });

    test('re-sync moves and re-labels the same row rather than duplicating',
        () async {
      await _seedDependency(db);
      Future<void> run(String desc, String act) => DependencyPlanLink.sync(db,
          projectId: _pid,
          dependencyId: 'dep1',
          ref: 'D7',
          description: desc,
          dependencyType: 'inbound',
          activityId: act,
          show: true);
      await run('first', 'act1');
      final before = (await db.programmeGanttDao.getDependencies(_pid)).single;
      await run('second', 'act2');
      final after = (await db.programmeGanttDao.getDependencies(_pid)).single;
      expect(after.id, before.id);
      expect(after.toActivityId, 'act2');
      expect(after.externalLabel, 'D7 · second');
    });

    test('unticking show removes the row', () async {
      await _seedDependency(db);
      await DependencyPlanLink.sync(db,
          projectId: _pid,
          dependencyId: 'dep1',
          ref: 'D7',
          description: 'd',
          dependencyType: 'inbound',
          activityId: 'act1',
          show: true);
      await DependencyPlanLink.sync(db,
          projectId: _pid,
          dependencyId: 'dep1',
          ref: 'D7',
          description: 'd',
          dependencyType: 'inbound',
          activityId: 'act1',
          show: false);
      expect(await db.programmeGanttDao.getDependencies(_pid), isEmpty);
    });

    test('outbound never writes a plan row even when asked', () async {
      await _seedDependency(db, type: 'outbound');
      await DependencyPlanLink.sync(db,
          projectId: _pid,
          dependencyId: 'dep1',
          ref: 'D7',
          description: 'd',
          dependencyType: 'outbound',
          activityId: 'act1',
          show: true);
      expect(await db.programmeGanttDao.getDependencies(_pid), isEmpty);
    });

    test('leaves unrelated timeline dependencies alone', () async {
      await db.programmeGanttDao.upsertDependency(TimelineDependenciesCompanion(
        id: const Value('hand-made'),
        projectId: const Value(_pid),
        fromActivityId: const Value('act1'),
        toActivityId: const Value('act2'),
        dependencyType: const Value('finish_to_start'),
      ));
      await _seedDependency(db);
      await DependencyPlanLink.sync(db,
          projectId: _pid,
          dependencyId: 'dep1',
          ref: 'D7',
          description: 'd',
          dependencyType: 'inbound',
          activityId: 'act1',
          show: false);
      await DependencyPlanLink.remove(db, _pid, 'dep1');
      final rows = await db.programmeGanttDao.getDependencies(_pid);
      expect(rows.map((r) => r.id), ['hand-made']);
    });
  });

  group('decision kind', () {
    test('a decision and a dependency can both point at one activity',
        () async {
      await _seedDependency(db);
      await DependencyPlanLink.sync(db,
          projectId: _pid,
          dependencyId: 'dep1',
          ref: 'D7',
          description: 'contract',
          dependencyType: 'inbound',
          activityId: 'act1',
          show: true);
      await DependencyPlanLink.sync(db,
          projectId: _pid,
          dependencyId: 'dc1',
          ref: 'DC1',
          description: 'gateway choice',
          dependencyType: 'inbound',
          activityId: 'act1',
          show: true,
          kind: PlanLinkKind.decision);
      final rows = await db.programmeGanttDao.getDependencies(_pid);
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.externalLabel).toSet(),
          {'D7 · contract', 'DC1 · gateway choice'});

      await DependencyPlanLink.remove(db, _pid, 'dc1',
          kind: PlanLinkKind.decision);
      final left = await db.programmeGanttDao.getDependencies(_pid);
      expect(left.single.externalLabel, 'D7 · contract');
    });
  });

  group('lifecycle', () {
    test('converting the dependency to a risk drops its plan row', () async {
      await _seedDependency(db);
      await DependencyPlanLink.sync(db,
          projectId: _pid,
          dependencyId: 'dep1',
          ref: 'D7',
          description: 'd',
          dependencyType: 'inbound',
          activityId: 'act1',
          show: true);
      expect(await db.programmeGanttDao.getDependencies(_pid), hasLength(1));

      await RaidConversionService(db)
          .convert(id: 'dep1', from: RaidKind.dependency, to: RaidKind.risk);

      expect(await db.programmeGanttDao.getDependencies(_pid), isEmpty);
      expect(await db.raidDao.getDependencyById('dep1'), isNull);
      expect(await db.raidDao.getRiskById('dep1'), isNotNull);
    });
  });
}
