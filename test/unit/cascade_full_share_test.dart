import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_service.dart';
import 'package:keel/core/database/database.dart';

/// Full-detail cascade: plan activities, tasks and arrows flowing from a
/// project onto a programme, plus the per-link share gate.
class _FakeGateway implements CascadeGateway {
  final pushes = <({String code, String kind, String id, Map<String, dynamic> payload})>[];
  final deletes = <({String code, String kind, String id})>[];
  final Map<String, CascadePullSnapshot> _byCode = {};
  void scriptPull(String code, List<CascadeRecord> items) =>
      _byCode[code] = CascadePullSnapshot(items: items, cursor: 'c');

  @override
  Future<void> push({
    required String code,
    required String sourceEntityId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  }) async =>
      pushes.add((code: code, kind: itemKind, id: itemId, payload: payload));

  @override
  Future<CascadePullSnapshot> pull({required String code, String? since}) async =>
      _byCode[code] ?? const CascadePullSnapshot(items: [], cursor: '');

  @override
  Future<void> delete({
    required String code,
    required String itemKind,
    required String itemId,
  }) async =>
      deletes.add((code: code, kind: itemKind, id: itemId));
}

void main() {
  late AppDatabase db;
  late String code;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(
        ProjectsCompanion.insert(id: 'proj', name: 'Sub Project'));
    await db.projectDao.insertProject(ProjectsCompanion.insert(
        id: 'prog', name: 'Programme', kind: const Value('programme')));
    final share = await db.programmeLinksDao
        .generateCodeForEntity(ownerEntityId: 'prog', ownerKind: 'programme');
    await db.programmeLinksDao
        .redeemCode(code: share, ownerEntityId: 'proj', ownerKind: 'project');
    code = share.split('#').first;
  });
  tearDown(() => db.close());

  Future<void> setLevel(String level) async {
    for (final l in await db.programmeLinksDao.getLinksForEntity('proj')) {
      await db.programmeLinksDao.setShareLevel(l.id, level);
    }
  }

  Future<TimelineActivity> seedActivity({
    String id = 'act-1',
    String wp = 'wp-1',
    int? start = 3,
    int? end = 5,
    String? parent,
    String type = 'activity',
  }) async {
    await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion.insert(
      id: id,
      workPackageId: wp,
      projectId: 'proj',
      name: 'Act $id',
      activityType: Value(type),
      startMonth: Value(start),
      endMonth: Value(end),
      parentActivityId: Value(parent),
    ));
    return (await db.programmeGanttDao.getActivityById(id))!;
  }

  group('share gate', () {
    test('same-machine redeem activates at full detail on both rows', () async {
      final rows = await db.programmeLinksDao.getByCode(code);
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.shareLevel).toSet(), {'full'});
    });

    test('setShareLevel mirrors onto the same-machine partner row', () async {
      final mine = (await db.programmeLinksDao.getLinksForEntity('proj')).single;
      await db.programmeLinksDao.setShareLevel(mine.id, 'escalated');
      final rows = await db.programmeLinksDao.getByCode(code);
      expect(rows.map((r) => r.shareLevel).toSet(), {'escalated'});
    });

    test('activities push only over full-detail links', () async {
      await db.programmeGanttDao.upsertWorkPackage(TimelineWorkPackagesCompanion
          .insert(id: 'wp-1', projectId: 'proj', name: 'WP'));
      final act = await seedActivity();
      final gw = _FakeGateway();
      final svc = CascadeService(db, gateway: gw);
      await svc.pushActivity(act);
      expect(gw.pushes.single.kind, CascadeKinds.activity);
      expect(gw.pushes.single.payload['work_package_id'], 'wp-1');
      expect(gw.pushes.single.payload['start_month'], 3);

      gw.pushes.clear();
      await setLevel('escalated');
      await svc.pushActivity(act);
      expect(gw.pushes, isEmpty);
      await svc.pushAllActivities('proj');
      expect(gw.pushes, isEmpty);
    });

    test('a source anchor adds the start month as an absolute date', () async {
      await db.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion.insert(
          id: 'h-proj', projectId: 'proj', month0Date: const Value('2026-01-01')));
      final act = await seedActivity(start: 3, end: 4);
      final gw = _FakeGateway();
      await CascadeService(db, gateway: gw).pushActivity(act);
      expect(gw.pushes.single.payload['start_month_date'],
          startsWith('2026-04-01'));
    });

    test('pushPlanDetailForWp sends the WP\'s activities and their arrows',
        () async {
      await seedActivity(id: 'a1');
      await seedActivity(id: 'a2', start: 6, end: 7);
      await seedActivity(id: 'other', wp: 'wp-2');
      await db.programmeGanttDao.upsertDependency(TimelineDependenciesCompanion
          .insert(id: 'dep-1', projectId: 'proj', fromActivityId: 'a1', toActivityId: 'a2'));
      await db.programmeGanttDao.upsertDependency(TimelineDependenciesCompanion
          .insert(id: 'dep-x', projectId: 'proj', fromActivityId: 'other', toActivityId: 'other'));
      final gw = _FakeGateway();
      await CascadeService(db, gateway: gw).pushPlanDetailForWp('proj', 'wp-1');
      expect(gw.pushes.map((p) => p.id).toSet(), {'a1', 'a2', 'dep-1'});
    });
  });

  group('no self-cascade', () {
    test('a programme\'s native risk and WP never come back as copies of '
        'themselves', () async {
      await db.raidDao.upsertRisk(RisksCompanion.insert(
          id: 'prog-r1', projectId: 'prog', description: 'native'));
      await db.programmeGanttDao.upsertWorkPackage(TimelineWorkPackagesCompanion
          .insert(id: 'prog-wp', projectId: 'prog', name: 'native WP'));
      final gw = _FakeGateway();
      final svc = CascadeService(db, gateway: gw);
      await svc.pushRisk((await db.raidDao.getRiskById('prog-r1'))!);
      await svc.pushWorkPackage(
          (await db.programmeGanttDao.getWorkPackages('prog')).single);
      expect(gw.pushes, isEmpty);

      // Even if an older build left such a record on the channel, pull
      // ignores it and sweeps any copy it previously created.
      await db.raidDao.upsertRisk(RisksCompanion.insert(
          id: 'cascade:risk:prog:prog-r1',
          projectId: 'prog',
          description: 'stale self copy',
          sourceProjectId: const Value('prog')));
      gw.scriptPull(code, [
        const CascadeRecord(
            sourceEntityId: 'prog',
            itemKind: CascadeKinds.risk,
            itemId: 'prog-r1',
            payload: {'description': 'native'},
            deleted: false),
      ]);
      await svc.pullForProgramme('prog');
      final risks = await db.raidDao.getRisksForProject('prog');
      expect(risks.map((r) => r.id), ['prog-r1']);
    });
  });

  group('un-escalate', () {
    test('pushing an unflagged row keeps it on a full link and tombstones '
        'it on an escalated-only link', () async {
      await db.raidDao.upsertRisk(RisksCompanion.insert(
          id: 'r1', projectId: 'proj', description: 'was escalated'));
      final risk = (await db.raidDao.getRiskById('r1'))!;
      final gw = _FakeGateway();
      final svc = CascadeService(db, gateway: gw);
      await svc.pushRisk(risk);
      expect(gw.pushes.single.payload['escalated'], isFalse);
      expect(gw.deletes, isEmpty);

      await setLevel('escalated');
      await svc.pushRisk(risk);
      expect(gw.pushes, hasLength(1)); // no new push
      expect(gw.deletes.single.id, 'r1');
      expect(gw.deletes.single.kind, CascadeKinds.risk);
    });
  });

  group('apply on the programme', () {
    CascadeRecord wpRec(String id) => CascadeRecord(
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.workPackage,
        itemId: id,
        payload: {'name': 'WP $id'},
        deleted: false);
    CascadeRecord actRec(String id, Map<String, dynamic> extra,
            {bool deleted = false}) =>
        CascadeRecord(
            sourceEntityId: 'proj',
            itemKind: CascadeKinds.activity,
            itemId: id,
            payload: {'work_package_id': 'wp-1', 'name': 'Act $id', ...extra},
            deleted: deleted);

    test('re-keys WP, parent, owner and RAID links; arrows land too, '
        'whatever the channel order', () async {
      final gw = _FakeGateway()
        ..scriptPull(code, [
          // Arrow and task arrive BEFORE their WP and parent.
          const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.planDependency,
              itemId: 'dep-1',
              payload: {
                'from_activity_id': 'a1',
                'to_activity_id': 't1',
                'dependency_type': 'finish_to_start',
                'notes': 'raid-dependency:d7',
              },
              deleted: false),
          actRec('t1', {'parent_activity_id': 'a1', 'start_month': 2}),
          actRec('a1', {
            'start_month': 1,
            'end_month': 4,
            'owner_id': 'person-9',
            'contributor_ids': jsonEncode(['person-2']),
            'variance_raid_type': 'risk',
            'variance_raid_id': 'r3',
            'variance_raid_links': jsonEncode([
              {'type': 'risk', 'id': 'r3'},
              {'type': 'assumption', 'id': 'as1'},
            ]),
            'is_critical': true,
          }),
          wpRec('wp-1'),
        ]);
      final applied = await CascadeService(db, gateway: gw).pullForProgramme('prog');
      expect(applied, 4);

      final acts = await db.programmeGanttDao.getActivitiesForProject('prog');
      final a1 = acts.firstWhere((a) => a.id == 'cascade:activity:proj:a1');
      expect(a1.workPackageId, 'cascade:proj:wp-1');
      expect(a1.sourceProjectId, 'proj');
      expect(a1.startMonth, 1);
      expect(a1.endMonth, 4);
      expect(a1.ownerId, 'cascade:person:proj:person-9');
      expect(jsonDecode(a1.contributorIds!), ['cascade:person:proj:person-2']);
      expect(a1.varianceRaidId, 'cascade:risk:proj:r3');
      expect(jsonDecode(a1.varianceRaidLinksJson!)[1]['id'],
          'cascade:assumption:proj:as1');
      expect(a1.isCritical, isTrue);
      final t1 = acts.firstWhere((a) => a.id == 'cascade:activity:proj:t1');
      expect(t1.parentActivityId, 'cascade:activity:proj:a1');

      final deps = await db.programmeGanttDao.getDependencies('prog');
      expect(deps.single.fromActivityId, 'cascade:activity:proj:a1');
      expect(deps.single.toActivityId, 'cascade:activity:proj:t1');
      expect(deps.single.notes, 'raid-dependency:cascade:dependency:proj:d7');
      expect(deps.single.sourceProjectId, 'proj');
    });

    test('months re-key onto the programme anchor when both sides have one',
        () async {
      // Programme month 0 = Oct 2025; project activity at its M3 = Apr 2026.
      await db.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion.insert(
          id: 'h-prog', projectId: 'prog', month0Date: const Value('2025-10-01')));
      final gw = _FakeGateway()
        ..scriptPull(code, [
          wpRec('wp-1'),
          actRec('a1', {
            'start_month': 3,
            'end_month': 5,
            'likely_month': 6,
            'baseline_start': 3,
            'start_month_date': '2026-04-01T00:00:00.000',
          }),
        ]);
      await CascadeService(db, gateway: gw).pullForProgramme('prog');
      final a1 = (await db.programmeGanttDao
          .getActivityById('cascade:activity:proj:a1'))!;
      expect(a1.startMonth, 6);
      expect(a1.endMonth, 8);
      expect(a1.likelyMonth, 9);
      expect(a1.baselineStart, 6);
    });

    test('without a programme anchor the raw months are kept', () async {
      final gw = _FakeGateway()
        ..scriptPull(code, [
          wpRec('wp-1'),
          actRec('a1', {
            'start_month': 3,
            'end_month': 5,
            'start_month_date': '2026-04-01T00:00:00.000',
          }),
        ]);
      await CascadeService(db, gateway: gw).pullForProgramme('prog');
      final a1 = (await db.programmeGanttDao
          .getActivityById('cascade:activity:proj:a1'))!;
      expect(a1.startMonth, 3);
      expect(a1.endMonth, 5);
    });

    test('a WP tombstone takes its cascaded activities and arrows with it',
        () async {
      final gw = _FakeGateway()
        ..scriptPull(code, [
          wpRec('wp-1'),
          actRec('a1', {}),
          actRec('a2', {}),
          const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.planDependency,
              itemId: 'dep-1',
              payload: {'from_activity_id': 'a1', 'to_activity_id': 'a2'},
              deleted: false),
        ]);
      final svc = CascadeService(db, gateway: gw);
      await svc.pullForProgramme('prog');
      expect(await db.programmeGanttDao.getActivitiesForProject('prog'), hasLength(2));

      gw.scriptPull(code, [
        const CascadeRecord(
            sourceEntityId: 'proj',
            itemKind: CascadeKinds.workPackage,
            itemId: 'wp-1',
            payload: {},
            deleted: true),
      ]);
      await svc.pullForProgramme('prog');
      expect(await db.programmeGanttDao.getWorkPackages('prog'), isEmpty);
      expect(await db.programmeGanttDao.getActivitiesForProject('prog'), isEmpty);
      expect(await db.programmeGanttDao.getDependencies('prog'), isEmpty);
    });

    test('an activity tombstone removes the copy and its arrows', () async {
      final gw = _FakeGateway()
        ..scriptPull(code, [
          wpRec('wp-1'),
          actRec('a1', {}),
          actRec('a2', {}),
          const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.planDependency,
              itemId: 'dep-1',
              payload: {'from_activity_id': 'a1', 'to_activity_id': 'a2'},
              deleted: false),
        ]);
      final svc = CascadeService(db, gateway: gw);
      await svc.pullForProgramme('prog');
      gw.scriptPull(code, [actRec('a2', {}, deleted: true)]);
      await svc.pullForProgramme('prog');
      final acts = await db.programmeGanttDao.getActivitiesForProject('prog');
      expect(acts.map((a) => a.id), ['cascade:activity:proj:a1']);
      expect(await db.programmeGanttDao.getDependencies('prog'), isEmpty);
    });

    test('cascaded copies never re-cascade', () async {
      await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion.insert(
        id: 'cascade:activity:x:1',
        workPackageId: 'cascade:x:wp',
        projectId: 'prog',
        name: 'copy',
        sourceProjectId: const Value('x'),
      ));
      final copy = (await db.programmeGanttDao.getActivityById('cascade:activity:x:1'))!;
      final gw = _FakeGateway();
      await CascadeService(db, gateway: gw).pushActivity(copy);
      expect(gw.pushes, isEmpty);
    });
  });
}
