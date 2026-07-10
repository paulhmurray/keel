import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_service.dart';
import 'package:keel/core/cascade/cascade_sync.dart';
import 'package:keel/core/cascade/composite_cascade_gateway.dart';
import 'package:keel/core/cascade/local_cascade_gateway.dart';
import 'package:keel/core/database/database.dart';

/// Same-machine cascade: a project and a programme in one install with a
/// locally-activated link must exchange escalated items without any sync
/// server in the loop. These tests pin the local transport + the
/// composite routing that makes it the default for same-machine links.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: 'prog',
      name: 'Big Programme',
      kind: const Value('programme'),
    ));
    await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: 'proj',
      name: 'Sub Project',
    ));
  });

  tearDown(() async => db.close());

  /// Generates a code on the programme and redeems it from the project,
  /// leaving both sides 'active' with partnerLocalId set. Returns the
  /// ROUTING code (`link.code`) — that's what CascadeService passes to the
  /// gateway in production, not the full `routing#secret` share string.
  Future<String> linkSameMachine() async {
    final share = await db.programmeLinksDao.generateCodeForEntity(
      ownerEntityId: 'prog',
      ownerKind: 'programme',
    );
    await db.programmeLinksDao.redeemCode(
      code: share,
      ownerEntityId: 'proj',
      ownerKind: 'project',
    );
    return share.split('#').first;
  }

  group('LocalCascadeGateway', () {
    test('push then pull round-trips the payload under the code', () async {
      final gw = LocalCascadeGateway(db);
      await gw.push(
        code: 'KL-1',
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: {'description': 'Server may fall over', 'impact': 'high'},
      );
      final snap = await gw.pull(code: 'KL-1');
      expect(snap.items, hasLength(1));
      final rec = snap.items.single;
      expect(rec.sourceEntityId, 'proj');
      expect(rec.itemKind, CascadeKinds.risk);
      expect(rec.itemId, 'r1');
      expect(rec.deleted, isFalse);
      expect(rec.payload['description'], 'Server may fall over');
      expect(rec.payload['impact'], 'high');
    });

    test('pull only returns items for the requested code', () async {
      final gw = LocalCascadeGateway(db);
      await gw.push(
        code: 'KL-A',
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: const {'description': 'A'},
      );
      await gw.push(
        code: 'KL-B',
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r2',
        payload: const {'description': 'B'},
      );
      expect((await gw.pull(code: 'KL-A')).items, hasLength(1));
      expect((await gw.pull(code: 'KL-B')).items, hasLength(1));
    });

    test('re-pushing the same item updates rather than duplicates',
        () async {
      final gw = LocalCascadeGateway(db);
      await gw.push(
        code: 'KL-1',
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: const {'description': 'first'},
      );
      await gw.push(
        code: 'KL-1',
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: const {'description': 'second'},
      );
      final snap = await gw.pull(code: 'KL-1');
      expect(snap.items, hasLength(1));
      expect(snap.items.single.payload['description'], 'second');
    });

    test('delete writes a tombstone that pull surfaces as deleted',
        () async {
      final gw = LocalCascadeGateway(db);
      await gw.push(
        code: 'KL-1',
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: const {'description': 'doomed'},
      );
      await gw.delete(
          code: 'KL-1', itemKind: CascadeKinds.risk, itemId: 'r1');
      final snap = await gw.pull(code: 'KL-1');
      expect(snap.items, hasLength(1));
      expect(snap.items.single.deleted, isTrue);
    });
  });

  group('CompositeCascadeGateway routing', () {
    test('routes same-machine links (partnerLocalId set) to the local '
        'channel', () async {
      final code = await linkSameMachine();
      final gw = CompositeCascadeGateway(db, remote: null);
      await gw.push(
        code: code,
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: const {'description': 'local'},
      );
      // It landed in the local table — pull reads it back even with a
      // null remote.
      final snap = await gw.pull(code: code);
      expect(snap.items, hasLength(1));
      expect(snap.items.single.payload['description'], 'local');
    });

    test('cross-machine link with no remote no-ops on push and returns '
        'an empty pull', () async {
      // A pending_remote link (partnerLocalId null) and no remote gateway.
      await db.programmeLinksDao.redeemCode(
        code: 'KL-REMOTE-ONLY',
        ownerEntityId: 'proj',
        ownerKind: 'project',
        partnerNameHint: 'Remote Programme',
      );
      final gw = CompositeCascadeGateway(db, remote: null);
      await gw.push(
        code: 'KL-REMOTE-ONLY',
        sourceEntityId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
        payload: const {'description': 'remote'},
      );
      final snap = await gw.pull(code: 'KL-REMOTE-ONLY');
      expect(snap.items, isEmpty);
    });
  });

  group('end-to-end same-machine escalation', () {
    test('escalating a risk on the project makes it appear read-only on '
        'the programme after pull', () async {
      await linkSameMachine();
      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );

      // PM escalates a risk: flag set on the source row, then push.
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'r1',
        projectId: 'proj',
        ref: const Value('R1'),
        description: 'Vendor may slip the integration date',
        impact: const Value('high'),
        escalatedAt: Value(DateTime.now()),
      ));
      final risk = await db.raidDao.getRiskById('r1');
      await cascade.pushRisk(risk!);

      // Programme pulls its links.
      final applied = await cascade.pullForProgramme('prog');
      expect(applied, 1);

      final progRisks = await db.raidDao.getRisksForProject('prog');
      expect(progRisks, hasLength(1));
      final cascaded = progRisks.single;
      expect(cascaded.description, 'Vendor may slip the integration date');
      expect(cascaded.ref, 'R1');
      expect(cascaded.impact, 'high');
      // Read-only marker: row came from a linked project.
      expect(cascaded.sourceProjectId, 'proj');
      expect(cascaded.source, 'cascade');
      // Source row on the project is untouched (not a cascade row).
      final source = await db.raidDao.getRiskById('r1');
      expect(source!.sourceProjectId, isNull);
    });

    test('unescalating tombstones the cascaded copy on the programme',
        () async {
      await linkSameMachine();
      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'r1',
        projectId: 'proj',
        description: 'Transient risk',
        escalatedAt: Value(DateTime.now()),
      ));
      await cascade.pushRisk((await db.raidDao.getRiskById('r1'))!);
      await cascade.pullForProgramme('prog');
      expect(await db.raidDao.getRisksForProject('prog'), hasLength(1));

      // PM stops escalating: tombstone, then pull again.
      await cascade.tombstoneRaidItem(
        projectId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r1',
      );
      await cascade.pullForProgramme('prog');
      expect(await db.raidDao.getRisksForProject('prog'), isEmpty);
    });

    test('a non-escalated risk does not cascade', () async {
      await linkSameMachine();
      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'r1',
        projectId: 'proj',
        description: 'Private risk, not escalated',
      ));
      await cascade.pushRisk((await db.raidDao.getRiskById('r1'))!);
      await cascade.pullForProgramme('prog');
      expect(await db.raidDao.getRisksForProject('prog'), isEmpty);
    });
  });

  group('person profile cascade', () {
    test('a person cascades with their embedded stakeholder + colleague '
        'profiles', () async {
      await linkSameMachine();
      // Native project person with both profiles.
      await db.peopleDao.upsertPerson(PersonsCompanion.insert(
        id: 'per1',
        projectId: 'proj',
        name: 'Jane Doe',
        email: const Value('jane@x.com'),
        organisation: const Value('Acme'),
        isStakeholder: const Value(true),
      ));
      await db.peopleDao.upsertStakeholder(StakeholderProfilesCompanion.insert(
        id: 'sp1',
        projectId: 'proj',
        personId: 'per1',
        influence: const Value('high'),
        interest: const Value('medium'),
        stance: const Value('supporter'),
      ));
      await db.peopleDao.upsertColleague(ColleagueProfilesCompanion.insert(
        id: 'cp1',
        projectId: 'proj',
        personId: 'per1',
        team: const Value('Delivery'),
        directReport: const Value(true),
      ));

      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );
      await cascade.pushPerson(
        (await db.peopleDao.getPersonById('per1'))!,
        sourceProjectName: 'Sub Project',
      );
      await cascade.pullForProgramme('prog');

      final progPeople = await db.peopleDao.getPersonsForProject('prog');
      expect(progPeople, hasLength(1));
      final cascaded = progPeople.single;
      expect(cascaded.name, 'Jane Doe');
      expect(cascaded.sourceProjectId, 'proj');
      expect(cascaded.sourceProjectName, 'Sub Project');

      // The embedded stakeholder profile came across, keyed to the
      // synthetic person id.
      final sp =
          await db.peopleDao.getStakeholderByPersonId(cascaded.id);
      expect(sp, isNotNull);
      expect(sp!.influence, 'high');
      expect(sp.interest, 'medium');
      expect(sp.stance, 'supporter');
      expect(sp.sourceProjectId, 'proj');

      final cp = await db.peopleDao.getColleagueByPersonId(cascaded.id);
      expect(cp, isNotNull);
      expect(cp!.team, 'Delivery');
      expect(cp.directReport, isTrue);
      expect(cp.sourceProjectId, 'proj');
    });

    test('stakeholder + team role matrices cascade, remapping the assigned '
        'personId to the cascaded person', () async {
      await linkSameMachine();
      // A person + a stakeholder role assigned to them + a team role.
      await db.peopleDao.upsertPerson(PersonsCompanion.insert(
        id: 'per1',
        projectId: 'proj',
        name: 'Sam Lead',
      ));
      await db.stakeholderRoleDao.upsert(StakeholderRolesCompanion.insert(
        id: 'sr1',
        projectId: 'proj',
        roleName: 'Sponsor',
        roleType: 'accountable',
        personId: const Value('per1'),
        engagementStatus: const Value('engaged'),
        priority: const Value('critical'),
      ));
      await db.teamRoleDao.upsert(TeamRolesCompanion.insert(
        id: 'tr1',
        projectId: 'proj',
        roleName: 'Programme Lead',
        teamGroup: 'programme_leadership',
        personId: const Value('per1'),
      ));

      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );
      await cascade.pushPerson(
        (await db.peopleDao.getPersonById('per1'))!,
        sourceProjectName: 'Sub Project',
      );
      await cascade.pushAllRoles('proj');
      await cascade.pullForProgramme('prog');

      final syntheticPersonId = 'cascade:person:proj:per1';
      final sRoles =
          await db.stakeholderRoleDao.getForProject('prog');
      expect(sRoles, hasLength(1));
      expect(sRoles.single.roleName, 'Sponsor');
      expect(sRoles.single.sourceProjectId, 'proj');
      expect(sRoles.single.engagementStatus, 'engaged');
      // The assignment resolves to the cascaded person on the programme.
      expect(sRoles.single.personId, syntheticPersonId);

      final tRoles = await db.teamRoleDao.getForProject('prog');
      expect(tRoles.single.personId, syntheticPersonId);

      // Sanity: that synthetic person exists on the programme.
      final progPeople = await db.peopleDao.getPersonsForProject('prog');
      expect(progPeople.map((p) => p.id), contains(syntheticPersonId));
    });

    test('deleting a cascaded person also removes its cascaded profiles',
        () async {
      await linkSameMachine();
      await db.peopleDao.upsertPerson(PersonsCompanion.insert(
        id: 'per1',
        projectId: 'proj',
        name: 'Temp',
        isStakeholder: const Value(true),
      ));
      await db.peopleDao.upsertStakeholder(StakeholderProfilesCompanion.insert(
        id: 'sp1',
        projectId: 'proj',
        personId: 'per1',
        influence: const Value('low'),
      ));
      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );
      await cascade.pushPerson(
        (await db.peopleDao.getPersonById('per1'))!,
        sourceProjectName: 'Sub Project',
      );
      await cascade.pullForProgramme('prog');
      final progPerson =
          (await db.peopleDao.getPersonsForProject('prog')).single;
      expect(await db.peopleDao.getStakeholderByPersonId(progPerson.id),
          isNotNull);

      // Delete on the source → tombstone → pull.
      await cascade.deletePerson(projectId: 'proj', personId: 'per1');
      await cascade.pullForProgramme('prog');
      expect(await db.peopleDao.getPersonsForProject('prog'), isEmpty);
      expect(await db.peopleDao.getStakeholderByPersonId(progPerson.id),
          isNull);
    });
  });

  group('work package swimlane span', () {
    /// Gives a project a month-0 anchor and one WP with two activities so
    /// the cascade can derive a span.
    Future<void> seedDatedWorkPackage({
      required String projectId,
      required String anchorIso,
      required int firstStart,
      required int lastEnd,
    }) async {
      await db.programmeGanttDao.upsertHeader(ProgrammeHeadersCompanion.insert(
        id: '$projectId-hdr',
        projectId: projectId,
        month0Date: Value(anchorIso),
      ));
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: 'wp1',
          projectId: projectId,
          name: 'Build',
        ),
      );
      await db.programmeGanttDao.upsertActivity(
        TimelineActivitiesCompanion.insert(
          id: 'a1',
          workPackageId: 'wp1',
          projectId: projectId,
          name: 'Early activity',
          startMonth: Value(firstStart),
          endMonth: Value(firstStart + 1),
        ),
      );
      await db.programmeGanttDao.upsertActivity(
        TimelineActivitiesCompanion.insert(
          id: 'a2',
          workPackageId: 'wp1',
          projectId: projectId,
          name: 'Late activity',
          startMonth: Value(lastEnd - 1),
          endMonth: Value(lastEnd),
        ),
      );
    }

    test('cascades the WP span as absolute dates spanning all activities',
        () async {
      await linkSameMachine();
      // Project anchored at Jan 2026; WP runs month 1..5.
      await seedDatedWorkPackage(
        projectId: 'proj',
        anchorIso: '2026-01-01',
        firstStart: 1,
        lastEnd: 5,
      );
      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );
      await cascade.pushWorkPackage(
        (await db.programmeGanttDao.getWorkPackages('proj')).single,
      );
      await cascade.pullForProgramme('prog');

      final progWps = await db.programmeGanttDao.getWorkPackages('prog');
      expect(progWps, hasLength(1));
      final cascaded = progWps.single;
      expect(cascaded.sourceProjectId, 'proj');
      // month 1 from Jan 2026 = Feb 2026; month 5 = Jun 2026.
      expect(DateTime.parse(cascaded.cascadeStartDate!).month, 2);
      expect(DateTime.parse(cascaded.cascadeStartDate!).year, 2026);
      expect(DateTime.parse(cascaded.cascadeEndDate!).month, 6);
      // Raw indices ride along too (fallback placement).
      expect(cascaded.cascadeStartMonth, 1);
      expect(cascaded.cascadeEndMonth, 5);
    });

    test('connecting an already-running project replays its back-catalogue '
        'without re-saving each WP (reconcileCascade)', () async {
      // A project that has been running BEFORE any link exists: two WPs,
      // never individually pushed.
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
            id: 'wp1', projectId: 'proj', name: 'Discovery'),
      );
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
            id: 'wp2', projectId: 'proj', name: 'Build'),
      );
      // Now connect.
      await linkSameMachine();
      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );

      // Nothing has been pushed yet — the programme is empty.
      expect(await db.programmeGanttDao.getWorkPackages('prog'), isEmpty);

      // The activation replay: push everything up from the project, then
      // pull it down on the programme.
      await reconcileCascade(db: db, cascade: cascade, projectId: 'proj');
      await reconcileCascade(db: db, cascade: cascade, projectId: 'prog');

      final progWps = await db.programmeGanttDao.getWorkPackages('prog');
      expect(progWps.map((w) => w.name).toSet(),
          {'Discovery', 'Build'});
      expect(progWps.every((w) => w.sourceProjectId == 'proj'), isTrue);
    });

    test('carries a month-index span (no dates) when the project has NO '
        'calendar anchor — the relative-axis case where bars vanished',
        () async {
      await linkSameMachine();
      // WP + dated activities but NO header/month0Date anchor.
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: 'wp1',
          projectId: 'proj',
          name: 'Build',
        ),
      );
      await db.programmeGanttDao.upsertActivity(
        TimelineActivitiesCompanion.insert(
          id: 'a1',
          workPackageId: 'wp1',
          projectId: 'proj',
          name: 'Activity',
          startMonth: const Value(2),
          endMonth: const Value(4),
        ),
      );
      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );
      await cascade.pushWorkPackage(
        (await db.programmeGanttDao.getWorkPackages('proj')).single,
      );
      await cascade.pullForProgramme('prog');

      final cascaded =
          (await db.programmeGanttDao.getWorkPackages('prog')).single;
      expect(cascaded.sourceProjectId, 'proj');
      // No anchor → no absolute dates, but the index span IS present so
      // the programme can still draw the bar.
      expect(cascaded.cascadeStartDate, isNull);
      expect(cascaded.cascadeEndDate, isNull);
      expect(cascaded.cascadeStartMonth, 2);
      expect(cascaded.cascadeEndMonth, 4);
    });

    test('omits span only when the WP has no dated activities', () async {
      await linkSameMachine();
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: 'wp1',
          projectId: 'proj',
          name: 'Undated',
        ),
      );
      await db.programmeGanttDao.upsertActivity(
        TimelineActivitiesCompanion.insert(
          id: 'a1',
          workPackageId: 'wp1',
          projectId: 'proj',
          name: 'No dates',
        ),
      );
      final cascade = CascadeService(
        db,
        gateway: CompositeCascadeGateway(db, remote: null),
      );
      await cascade.pushWorkPackage(
        (await db.programmeGanttDao.getWorkPackages('proj')).single,
      );
      await cascade.pullForProgramme('prog');

      final cascaded =
          (await db.programmeGanttDao.getWorkPackages('prog')).single;
      expect(cascaded.sourceProjectId, 'proj');
      expect(cascaded.cascadeStartMonth, isNull);
      expect(cascaded.cascadeEndMonth, isNull);
    });
  });
}
