import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_service.dart';
import 'package:keel/core/database/database.dart';

/// In-memory CascadeGateway double — records pushes/deletes and
/// returns scripted pulls. Mirrors the [_FakeGateway] pattern used
/// for programme links so test setup reads consistently.
class _FakeCascadeGateway implements CascadeGateway {
  final List<_PushCall> pushes = [];
  final List<_DeleteCall> deletes = [];
  final Map<String, CascadePullSnapshot> _byCode = {};
  bool throwOnPush = false;

  void scriptPull(String code, CascadePullSnapshot snap) {
    _byCode[code] = snap;
  }

  @override
  Future<void> push({
    required String code,
    required String sourceEntityId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  }) async {
    if (throwOnPush) throw Exception('offline');
    pushes.add(_PushCall(
      code: code,
      sourceEntityId: sourceEntityId,
      itemKind: itemKind,
      itemId: itemId,
      payload: payload,
    ));
  }

  @override
  Future<CascadePullSnapshot> pull({
    required String code,
    String? since,
  }) async =>
      _byCode[code] ?? const CascadePullSnapshot(items: [], cursor: '');

  @override
  Future<void> delete({
    required String code,
    required String itemKind,
    required String itemId,
  }) async {
    deletes.add(_DeleteCall(
      code: code,
      itemKind: itemKind,
      itemId: itemId,
    ));
  }
}

class _PushCall {
  final String code;
  final String sourceEntityId;
  final String itemKind;
  final String itemId;
  final Map<String, dynamic> payload;
  const _PushCall({
    required this.code,
    required this.sourceEntityId,
    required this.itemKind,
    required this.itemId,
    required this.payload,
  });
}

class _DeleteCall {
  final String code;
  final String itemKind;
  final String itemId;
  const _DeleteCall({
    required this.code,
    required this.itemKind,
    required this.itemId,
  });
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: 'proj',
      name: 'Sub Project',
    ));
    await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: 'prog',
      name: 'Big Programme',
      kind: const Value('programme'),
    ));
    // Seed an active link between proj and prog by faking both
    // sides — the cascade service only cares about status='active'
    // rows so we bypass the redeem flow.
    final code = await db.programmeLinksDao.generateCodeForEntity(
        ownerEntityId: 'prog', ownerKind: 'programme');
    await db.programmeLinksDao.redeemCode(
      code: code,
      ownerEntityId: 'proj',
      ownerKind: 'project',
    );
  });

  tearDown(() async => db.close());

  Future<void> insertWp(String id, {String name = 'WP'}) async {
    await db.programmeGanttDao.upsertWorkPackage(
      TimelineWorkPackagesCompanion.insert(
        id: id,
        projectId: 'proj',
        name: name,
      ),
    );
  }

  group('CascadeService.pushWorkPackage', () {
    test(
        'pushes the WP payload to every active link on the source '
        'project', () async {
      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);

      await insertWp('wp-1', name: 'WP One');
      final wp = (await db.programmeGanttDao.getWorkPackages('proj'))
          .single;
      await svc.pushWorkPackage(wp);

      expect(gw.pushes, hasLength(1));
      final p = gw.pushes.single;
      expect(p.itemKind, CascadeKinds.workPackage);
      expect(p.itemId, 'wp-1');
      expect(p.sourceEntityId, 'proj');
      expect(p.payload['name'], 'WP One');
    });

    test(
        'never re-cascades a row that itself arrived via cascade '
        '(prevents fan-out loops)', () async {
      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);

      // Insert a cascaded-style row (sourceProjectId populated).
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: 'cascade:proj:wp-1',
          projectId: 'proj',
          name: 'Mirror',
          sourceProjectId: const Value('proj'),
        ),
      );
      final wp = (await db.programmeGanttDao.getWorkPackages('proj'))
          .single;
      await svc.pushWorkPackage(wp);
      expect(gw.pushes, isEmpty);
    });

    test('no-op when there are no active links', () async {
      // Wipe the seed link.
      final links =
          await db.programmeLinksDao.getLinksForEntity('proj');
      for (final l in links) {
        await db.programmeLinksDao.revokeLink(l.id);
      }
      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);
      await insertWp('wp-1');
      final wp = (await db.programmeGanttDao.getWorkPackages('proj'))
          .single;
      await svc.pushWorkPackage(wp);
      expect(gw.pushes, isEmpty);
    });

    test('no-op when the gateway is null (offline)', () async {
      final svc = CascadeService(db, gateway: null);
      await insertWp('wp-1');
      final wp = (await db.programmeGanttDao.getWorkPackages('proj'))
          .single;
      // Must not throw.
      await svc.pushWorkPackage(wp);
    });

    test('swallows gateway throws — best-effort cascade', () async {
      final gw = _FakeCascadeGateway()..throwOnPush = true;
      final svc = CascadeService(db, gateway: gw);
      await insertWp('wp-1');
      final wp = (await db.programmeGanttDao.getWorkPackages('proj'))
          .single;
      await svc.pushWorkPackage(wp); // must not throw
    });
  });

  group('CascadeService.deleteWorkPackage', () {
    test('tombstones the item on every active link', () async {
      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);
      await svc.deleteWorkPackage(
        projectId: 'proj',
        workPackageId: 'wp-1',
      );
      expect(gw.deletes, hasLength(1));
      expect(gw.deletes.single.itemId, 'wp-1');
      expect(gw.deletes.single.itemKind, CascadeKinds.workPackage);
    });
  });

  group('CascadeService.pullForProgramme', () {
    test(
        'creates a cascade row on the programme side with the source '
        'project id stamped', () async {
      final gw = _FakeCascadeGateway();
      // Programme has one active link — find its code from the seed.
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      gw.scriptPull(
        code,
        CascadePullSnapshot(items: [
          CascadeRecord(
            sourceEntityId: 'proj',
            itemKind: CascadeKinds.workPackage,
            itemId: 'wp-1',
            payload: const {
              'name': 'Cascaded WP',
              'rag_status': 'green',
              'colour_theme': 'wp2',
              'sort_order': 3,
            },
            deleted: false,
          ),
        ], cursor: ''),
      );

      final svc = CascadeService(db, gateway: gw);
      final applied = await svc.pullForProgramme('prog');
      expect(applied, 1);

      final wps = await db.programmeGanttDao.getWorkPackages('prog');
      expect(wps, hasLength(1));
      expect(wps.single.id, 'cascade:proj:wp-1');
      expect(wps.single.sourceProjectId, 'proj');
      expect(wps.single.name, 'Cascaded WP');
      expect(wps.single.ragStatus, 'green');
      expect(wps.single.colourTheme, 'wp2');
      expect(wps.single.sortOrder, 3);
    });

    test('deletes the cascaded row when the source side tombstoned it',
        () async {
      // Seed an existing cascade row.
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: 'cascade:proj:wp-1',
          projectId: 'prog',
          name: 'Doomed',
          sourceProjectId: const Value('proj'),
        ),
      );
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.workPackage,
              itemId: 'wp-1',
              payload: const {},
              deleted: true,
            ),
          ], cursor: ''),
        );
      final svc = CascadeService(db, gateway: gw);
      await svc.pullForProgramme('prog');
      final wps = await db.programmeGanttDao.getWorkPackages('prog');
      expect(wps, isEmpty);
    });

    test('returns 0 when the gateway is null', () async {
      final svc = CascadeService(db, gateway: null);
      expect(await svc.pullForProgramme('prog'), 0);
    });

    test(
        'unknown item kinds are silently skipped (forward compatible '
        'with future cascade kinds)', () async {
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              // A genuinely-unknown kind a future server version
              // might emit. Today the client should ignore it without
              // crashing — forwards compatibility on the wire format.
              itemKind: 'something_brand_new',
              itemId: 'x-1',
              payload: {'whatever': 'goes here'},
              deleted: false,
            ),
          ], cursor: ''),
        );
      final svc = CascadeService(db, gateway: gw);
      final applied = await svc.pullForProgramme('prog');
      expect(applied, 0);
    });
  });

  group('RAID escalation cascade', () {
    Future<Risk> insertRisk({
      String id = 'r-1',
      String description = 'A risk',
      DateTime? escalatedAt,
    }) async {
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: id,
        projectId: 'proj',
        ref: const Value('R1'),
        description: description,
        likelihood: const Value('medium'),
        impact: const Value('high'),
        status: const Value('open'),
        owner: const Value('Paul'),
        escalatedAt: Value(escalatedAt),
      ));
      return (await db.raidDao.getRiskById(id))!;
    }

    test('pushRisk fires only when escalatedAt is set', () async {
      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);

      final notEscalated = await insertRisk();
      await svc.pushRisk(notEscalated);
      expect(gw.pushes, isEmpty);

      final escalated = await insertRisk(
          id: 'r-2', escalatedAt: DateTime.now());
      await svc.pushRisk(escalated);
      expect(gw.pushes, hasLength(1));
      expect(gw.pushes.single.itemKind, CascadeKinds.risk);
      expect(gw.pushes.single.payload['description'], 'A risk');
      expect(gw.pushes.single.payload['likelihood'], 'medium');
      expect(gw.pushes.single.payload['impact'], 'high');
    });

    test(
        'pushRisk skips rows that themselves arrived via cascade '
        '(prevents re-cascade loops)', () async {
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'cascade:foreign:r-1',
        projectId: 'proj',
        description: 'Inherited',
        escalatedAt: Value(DateTime.now()),
        sourceProjectId: const Value('foreign'),
      ));
      final cascaded = (await db.raidDao.getRiskById('cascade:foreign:r-1'))!;

      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);
      await svc.pushRisk(cascaded);
      expect(gw.pushes, isEmpty);
    });

    test('tombstoneRaidItem fires delete on every active link',
        () async {
      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);
      await svc.tombstoneRaidItem(
        projectId: 'proj',
        itemKind: CascadeKinds.risk,
        itemId: 'r-1',
      );
      expect(gw.deletes, hasLength(1));
      expect(gw.deletes.single.itemKind, CascadeKinds.risk);
      expect(gw.deletes.single.itemId, 'r-1');
    });

    test(
        'pullForProgramme applies a cascaded risk into the programme\'s '
        'risks table with sourceProjectId stamped', () async {
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.risk,
              itemId: 'r-9',
              payload: {
                'ref': 'R9',
                'description': 'Programme-visible risk',
                'likelihood': 'high',
                'impact': 'high',
                'status': 'open',
                'owner': 'Anna',
              },
              deleted: false,
            ),
          ], cursor: ''),
        );

      final svc = CascadeService(db, gateway: gw);
      final applied = await svc.pullForProgramme('prog');
      expect(applied, 1);

      final risks = await db.raidDao.getRisksForProject('prog');
      expect(risks, hasLength(1));
      final r = risks.single;
      expect(r.id, 'cascade:risk:proj:r-9');
      expect(r.sourceProjectId, 'proj');
      expect(r.description, 'Programme-visible risk');
      expect(r.likelihood, 'high');
      expect(r.owner, 'Anna');
      // Cascaded items always land with source='cascade' so PMs in
      // the RAID view can tell where they came from quickly.
      expect(r.source, 'cascade');
    });

    test('pullForProgramme tombstones a cascaded risk on delete',
        () async {
      // Seed an existing cascaded row.
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'cascade:risk:proj:r-9',
        projectId: 'prog',
        description: 'Doomed',
        sourceProjectId: const Value('proj'),
      ));
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.risk,
              itemId: 'r-9',
              payload: {},
              deleted: true,
            ),
          ], cursor: ''),
        );
      await CascadeService(db, gateway: gw).pullForProgramme('prog');
      final risks = await db.raidDao.getRisksForProject('prog');
      expect(risks, isEmpty);
    });

    test(
        'pushStatusReport fires every save — saving IS the publish '
        'moment (no per-report opt-in)', () async {
      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);

      // Note the source field stays plain — status reports use the
      // existing source enum, no special "cascade" marker here.
      await db.reportsDao.upsertReport(StatusReportsCompanion.insert(
        id: 'sr-1',
        projectId: 'proj',
        title: 'Weekly update',
        period: const Value('Wk 23'),
        overallRag: const Value('amber'),
        summary: const Value('All on track'),
      ));
      final saved = (await db.reportsDao.getReportsForProject('proj'))
          .firstWhere((r) => r.id == 'sr-1');
      await svc.pushStatusReport(saved);

      expect(gw.pushes, hasLength(1));
      final p = gw.pushes.single;
      expect(p.itemKind, CascadeKinds.statusReport);
      expect(p.itemId, 'sr-1');
      expect(p.payload['title'], 'Weekly update');
      expect(p.payload['overall_rag'], 'amber');
      expect(p.payload['period'], 'Wk 23');
      expect(p.payload['summary'], 'All on track');
    });

    test(
        'pushStatusReport skips rows that themselves arrived via '
        'cascade (prevents re-cascade)', () async {
      await db.reportsDao.upsertReport(StatusReportsCompanion.insert(
        id: 'cascade:status_report:other:sr-9',
        projectId: 'proj',
        title: 'Inherited',
        sourceProjectId: const Value('other'),
      ));
      final cascaded = (await db.reportsDao
              .getReportsForProject('proj'))
          .firstWhere((r) => r.id.startsWith('cascade:'));

      final gw = _FakeCascadeGateway();
      await CascadeService(db, gateway: gw)
          .pushStatusReport(cascaded);
      expect(gw.pushes, isEmpty);
    });

    test(
        'pullForProgramme applies a cascaded status report into the '
        'programme\'s reports list', () async {
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.statusReport,
              itemId: 'sr-7',
              payload: {
                'title': 'Q2 update',
                'overall_rag': 'green',
                'summary': 'Strong quarter',
                'period': 'Q2 2026',
              },
              deleted: false,
            ),
          ], cursor: ''),
        );

      final svc = CascadeService(db, gateway: gw);
      final applied = await svc.pullForProgramme('prog');
      expect(applied, 1);

      final reports =
          await db.reportsDao.getReportsForProject('prog');
      expect(reports, hasLength(1));
      final r = reports.single;
      expect(r.id, 'cascade:status_report:proj:sr-7');
      expect(r.sourceProjectId, 'proj');
      expect(r.title, 'Q2 update');
      expect(r.overallRag, 'green');
      expect(r.summary, 'Strong quarter');
    });

    test(
        'pullForProgramme tombstones the cascaded report when the '
        'source side deletes it', () async {
      await db.reportsDao.upsertReport(StatusReportsCompanion.insert(
        id: 'cascade:status_report:proj:sr-7',
        projectId: 'prog',
        title: 'Doomed',
        sourceProjectId: const Value('proj'),
      ));
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.statusReport,
              itemId: 'sr-7',
              payload: {},
              deleted: true,
            ),
          ], cursor: ''),
        );
      await CascadeService(db, gateway: gw).pullForProgramme('prog');
      final reports =
          await db.reportsDao.getReportsForProject('prog');
      expect(reports, isEmpty);
    });

    test('pushAllStatusReports replays every report on demand',
        () async {
      await db.reportsDao.upsertReport(StatusReportsCompanion.insert(
        id: 'sr-1', projectId: 'proj', title: 'One'));
      await db.reportsDao.upsertReport(StatusReportsCompanion.insert(
        id: 'sr-2', projectId: 'proj', title: 'Two'));

      final gw = _FakeCascadeGateway();
      await CascadeService(db, gateway: gw)
          .pushAllStatusReports('proj');
      expect(gw.pushes.where((p) =>
          p.itemKind == CascadeKinds.statusReport), hasLength(2));
    });

    test(
        'pushCharter fires on save with the source project name in '
        'the payload (so the programme can label attribution)',
        () async {
      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);

      await db.projectCharterDao.upsert(ProjectChartersCompanion.insert(
        id: 'ch-1',
        projectId: 'proj',
        vision: const Value('To do great things'),
        objectives: const Value('Ship by Q4'),
      ));
      final charter =
          (await db.projectCharterDao.getForProject('proj'))!;
      await svc.pushCharter(charter, sourceProjectName: 'Sub Project');

      expect(gw.pushes, hasLength(1));
      final p = gw.pushes.single;
      expect(p.itemKind, CascadeKinds.charter);
      expect(p.itemId, 'ch-1');
      expect(p.payload['source_project_name'], 'Sub Project');
      expect(p.payload['vision'], 'To do great things');
      expect(p.payload['objectives'], 'Ship by Q4');
    });

    test('pushCharter skips cascaded rows (no re-cascade)',
        () async {
      await db.projectCharterDao.upsert(ProjectChartersCompanion.insert(
        id: 'cascade:charter:other:ch-1',
        projectId: 'proj',
        vision: const Value('inherited'),
        sourceProjectId: const Value('other'),
      ));
      final allForProj = await (db.select(db.projectCharters)
            ..where((t) => t.projectId.equals('proj')))
          .get();
      final cascaded = allForProj
          .firstWhere((c) => c.sourceProjectId != null);

      final gw = _FakeCascadeGateway();
      await CascadeService(db, gateway: gw).pushCharter(
        cascaded,
        sourceProjectName: 'whatever',
      );
      expect(gw.pushes, isEmpty);
    });

    test(
        'pullForProgramme creates a cascaded charter row alongside '
        'any native programme charter', () async {
      // Programme has its own charter (sourceProjectId NULL).
      await db.projectCharterDao.upsert(ProjectChartersCompanion.insert(
        id: 'prog-charter',
        projectId: 'prog',
        vision: const Value('Programme vision'),
      ));

      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.charter,
              itemId: 'ch-7',
              payload: {
                'source_project_name': 'Sub Project',
                'vision': 'Project vision',
                'objectives': 'Project objectives',
              },
              deleted: false,
            ),
          ], cursor: ''),
        );

      final svc = CascadeService(db, gateway: gw);
      final applied = await svc.pullForProgramme('prog');
      expect(applied, 1);

      // Native charter still loads cleanly via watchForProject.
      final native =
          await db.projectCharterDao.getForProject('prog');
      expect(native, isNotNull);
      expect(native!.id, 'prog-charter');
      expect(native.vision, 'Programme vision');

      // Cascaded charter is visible via the dedicated stream.
      final cascaded = await db.projectCharterDao
          .watchCascadedForProgramme('prog')
          .first;
      expect(cascaded, hasLength(1));
      expect(cascaded.single.sourceProjectId, 'proj');
      expect(cascaded.single.sourceProjectName, 'Sub Project');
      expect(cascaded.single.vision, 'Project vision');
    });

    test('pullForProgramme tombstones cascaded charter on delete',
        () async {
      await db.projectCharterDao.upsert(ProjectChartersCompanion.insert(
        id: 'cascade:charter:proj:ch-7',
        projectId: 'prog',
        sourceProjectId: const Value('proj'),
      ));
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.charter,
              itemId: 'ch-7',
              payload: {},
              deleted: true,
            ),
          ], cursor: ''),
        );
      await CascadeService(db, gateway: gw).pullForProgramme('prog');
      final cascaded = await db.projectCharterDao
          .watchCascadedForProgramme('prog')
          .first;
      expect(cascaded, isEmpty);
    });

    test(
        'watchForProject returns the native charter and ignores '
        'cascaded rows even when both share a projectId', () async {
      // Seed programme charter + a cascaded charter, both at
      // projectId='prog'.
      await db.projectCharterDao.upsert(ProjectChartersCompanion.insert(
        id: 'native',
        projectId: 'prog',
        vision: const Value('Native'),
      ));
      await db.projectCharterDao.upsert(ProjectChartersCompanion.insert(
        id: 'cascade:charter:proj:ch-9',
        projectId: 'prog',
        vision: const Value('Cascaded'),
        sourceProjectId: const Value('proj'),
      ));

      final native =
          await db.projectCharterDao.getForProject('prog');
      expect(native, isNotNull);
      expect(native!.id, 'native');
      expect(native.vision, 'Native');
    });

    test(
        'pushPerson fires on save with the source project name + '
        'every editable field in the payload', () async {
      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);

      await db.peopleDao.insertPerson(PersonsCompanion.insert(
        id: 'person-1',
        projectId: 'proj',
        name: 'Anna',
        email: const Value('anna@example.com'),
        role: const Value('Sponsor'),
        organisation: const Value('Acme'),
        personType: const Value('exec'),
        isStakeholder: const Value(true),
      ));
      final fresh = await db.peopleDao.getPersonById('person-1');
      await svc.pushPerson(fresh!,
          sourceProjectName: 'Sub Project');

      expect(gw.pushes, hasLength(1));
      final p = gw.pushes.single;
      expect(p.itemKind, CascadeKinds.person);
      expect(p.itemId, 'person-1');
      expect(p.payload['source_project_name'], 'Sub Project');
      expect(p.payload['name'], 'Anna');
      expect(p.payload['email'], 'anna@example.com');
      expect(p.payload['role'], 'Sponsor');
      expect(p.payload['organisation'], 'Acme');
      expect(p.payload['person_type'], 'exec');
      expect(p.payload['is_stakeholder'], true);
    });

    test('pushPerson skips cascaded rows (no re-cascade loops)',
        () async {
      await db.peopleDao.insertPerson(PersonsCompanion.insert(
        id: 'cascade:person:other:p-1',
        projectId: 'proj',
        name: 'Inherited',
        sourceProjectId: const Value('other'),
      ));
      final cascaded =
          await db.peopleDao.getPersonById('cascade:person:other:p-1');
      final gw = _FakeCascadeGateway();
      await CascadeService(db, gateway: gw).pushPerson(
        cascaded!,
        sourceProjectName: 'X',
      );
      expect(gw.pushes, isEmpty);
    });

    test(
        'pullForProgramme creates a cascaded person on the programme '
        'with the source project id + name stamped', () async {
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.person,
              itemId: 'person-7',
              payload: {
                'source_project_name': 'Sub Project',
                'name': 'Bart',
                'role': 'Eng lead',
                'person_type': 'colleague',
                'is_stakeholder': true,
              },
              deleted: false,
            ),
          ], cursor: ''),
        );

      final applied =
          await CascadeService(db, gateway: gw).pullForProgramme('prog');
      expect(applied, 1);

      final people = await db.peopleDao.getPersonsForProject('prog');
      expect(people, hasLength(1));
      final p = people.single;
      expect(p.id, 'cascade:person:proj:person-7');
      expect(p.sourceProjectId, 'proj');
      expect(p.sourceProjectName, 'Sub Project');
      expect(p.name, 'Bart');
      expect(p.role, 'Eng lead');
      expect(p.personType, 'colleague');
      expect(p.isStakeholder, isTrue);
    });

    test('pullForProgramme tombstones the cascaded person on delete',
        () async {
      await db.peopleDao.insertPerson(PersonsCompanion.insert(
        id: 'cascade:person:proj:person-7',
        projectId: 'prog',
        name: 'Doomed',
        sourceProjectId: const Value('proj'),
      ));
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.person,
              itemId: 'person-7',
              payload: {},
              deleted: true,
            ),
          ], cursor: ''),
        );
      await CascadeService(db, gateway: gw).pullForProgramme('prog');
      expect(await db.peopleDao.getPersonsForProject('prog'), isEmpty);
    });

    test(
        'pushAllPeople replays every native person but skips '
        'cascaded rows on the source project', () async {
      // Two native people + one cascaded one already on the project.
      await db.peopleDao.insertPerson(PersonsCompanion.insert(
        id: 'p-1', projectId: 'proj', name: 'Native 1'));
      await db.peopleDao.insertPerson(PersonsCompanion.insert(
        id: 'p-2', projectId: 'proj', name: 'Native 2'));
      await db.peopleDao.insertPerson(PersonsCompanion.insert(
        id: 'cascade:person:foreign:p-9',
        projectId: 'proj',
        name: 'Inherited',
        sourceProjectId: const Value('foreign'),
      ));

      final gw = _FakeCascadeGateway();
      await CascadeService(db, gateway: gw).pushAllPeople(
        projectId: 'proj',
        projectName: 'P',
      );
      final personPushes = gw.pushes
          .where((p) => p.itemKind == CascadeKinds.person)
          .toList();
      expect(personPushes, hasLength(2));
      expect(
        personPushes.map((p) => p.itemId).toSet(),
        {'p-1', 'p-2'},
      );
    });

    test(
        'pushAction fires when escalatedAt is set; tombstones on '
        'unescalate via tombstoneRaidItem', () async {
      // Create + escalate an action.
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-1',
        projectId: 'proj',
        ref: const Value('A1'),
        description: 'Do the thing',
        owner: const Value('Paul'),
        dueDate: const Value('2026-09-01'),
        status: const Value('open'),
        priority: const Value('high'),
        escalatedAt: Value(DateTime.now()),
      ));
      final action = await db.actionsDao.getActionById('a-1');

      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);
      await svc.pushAction(action!);
      expect(gw.pushes, hasLength(1));
      final p = gw.pushes.single;
      expect(p.itemKind, CascadeKinds.action);
      expect(p.itemId, 'a-1');
      expect(p.payload['description'], 'Do the thing');
      expect(p.payload['owner'], 'Paul');
      expect(p.payload['due_date'], '2026-09-01');
      expect(p.payload['priority'], 'high');

      // Tombstone via the generic RAID-family helper.
      await svc.tombstoneRaidItem(
        projectId: 'proj',
        itemKind: CascadeKinds.action,
        itemId: 'a-1',
      );
      expect(gw.deletes.where((d) =>
          d.itemKind == CascadeKinds.action), hasLength(1));
    });

    test('pushAction skips cascaded rows (no re-cascade)',
        () async {
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'cascade:action:other:a-1',
        projectId: 'proj',
        description: 'Inherited',
        escalatedAt: Value(DateTime.now()),
        sourceProjectId: const Value('other'),
      ));
      final action = await db.actionsDao
          .getActionById('cascade:action:other:a-1');
      final gw = _FakeCascadeGateway();
      await CascadeService(db, gateway: gw).pushAction(action!);
      expect(gw.pushes, isEmpty);
    });

    test(
        'pushDecision fires when escalatedAt is set, payload carries '
        'decision-specific fields', () async {
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-1',
        projectId: 'proj',
        ref: const Value('DC1'),
        description: 'Vendor selection',
        status: const Value('pending'),
        decisionMaker: const Value('Anna'),
        rationale: const Value('Lowest cost'),
        escalatedAt: Value(DateTime.now()),
      ));
      final decision = await db.decisionsDao.getDecisionById('d-1');

      final gw = _FakeCascadeGateway();
      await CascadeService(db, gateway: gw).pushDecision(decision!);
      expect(gw.pushes, hasLength(1));
      final p = gw.pushes.single;
      expect(p.itemKind, CascadeKinds.decision);
      expect(p.payload['decision_maker'], 'Anna');
      expect(p.payload['rationale'], 'Lowest cost');
      expect(p.payload['status'], 'pending');
    });

    test(
        'pullForProgramme applies cascaded action + decision rows '
        'with sourceProjectId stamped', () async {
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.action,
              itemId: 'a-7',
              payload: {
                'ref': 'A7',
                'description': 'Escalated action',
                'owner': 'Bart',
                'status': 'open',
                'priority': 'high',
              },
              deleted: false,
            ),
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.decision,
              itemId: 'd-7',
              payload: {
                'ref': 'DC7',
                'description': 'Escalated decision',
                'status': 'pending',
                'decision_maker': 'Anna',
              },
              deleted: false,
            ),
          ], cursor: ''),
        );

      final applied =
          await CascadeService(db, gateway: gw).pullForProgramme('prog');
      expect(applied, 2);

      final actions =
          await db.actionsDao.getActionsForProject('prog');
      expect(actions, hasLength(1));
      expect(actions.single.id, 'cascade:action:proj:a-7');
      expect(actions.single.sourceProjectId, 'proj');
      expect(actions.single.description, 'Escalated action');
      expect(actions.single.priority, 'high');
      expect(actions.single.source, 'cascade');

      final decisions =
          await db.decisionsDao.getDecisionsForProject('prog');
      expect(decisions, hasLength(1));
      expect(decisions.single.id, 'cascade:decision:proj:d-7');
      expect(decisions.single.sourceProjectId, 'proj');
      expect(decisions.single.description, 'Escalated decision');
      expect(decisions.single.decisionMaker, 'Anna');
    });

    test(
        'pullForProgramme tombstones cascaded action + decision rows '
        'on delete', () async {
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'cascade:action:proj:a-7',
        projectId: 'prog',
        description: 'Doomed action',
        sourceProjectId: const Value('proj'),
      ));
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'cascade:decision:proj:d-7',
        projectId: 'prog',
        description: 'Doomed decision',
        sourceProjectId: const Value('proj'),
      ));
      final code = (await db.programmeLinksDao
              .getLinksForEntity('prog'))
          .single
          .code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.action,
              itemId: 'a-7',
              payload: {},
              deleted: true,
            ),
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.decision,
              itemId: 'd-7',
              payload: {},
              deleted: true,
            ),
          ], cursor: ''),
        );
      await CascadeService(db, gateway: gw).pullForProgramme('prog');
      expect(await db.actionsDao.getActionsForProject('prog'), isEmpty);
      expect(
          await db.decisionsDao.getDecisionsForProject('prog'), isEmpty);
    });

    test(
        'pushAllEscalatedDelivery replays escalated actions + '
        'decisions for link activation', () async {
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-1',
        projectId: 'proj',
        description: 'A1',
        escalatedAt: Value(DateTime.now()),
      ));
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-1',
        projectId: 'proj',
        description: 'D1',
        escalatedAt: Value(DateTime.now()),
      ));
      // Plus a non-escalated row that should be skipped.
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-2',
        projectId: 'proj',
        description: 'A2 — not escalated',
      ));

      final gw = _FakeCascadeGateway();
      await CascadeService(db, gateway: gw)
          .pushAllEscalatedDelivery('proj');
      final ids = gw.pushes.map((p) => p.itemId).toSet();
      expect(ids, {'a-1', 'd-1'});
    });

    test('pushAllEscalatedRaid replays every escalated kind on demand',
        () async {
      // Seed one escalated item of each kind.
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'r-1',
        projectId: 'proj',
        description: 'R',
        escalatedAt: Value(DateTime.now()),
      ));
      await db.raidDao.upsertAssumption(AssumptionsCompanion.insert(
        id: 'a-1',
        projectId: 'proj',
        description: 'A',
        escalatedAt: Value(DateTime.now()),
      ));
      await db.raidDao.upsertIssue(IssuesCompanion.insert(
        id: 'i-1',
        projectId: 'proj',
        description: 'I',
        escalatedAt: Value(DateTime.now()),
      ));
      await db.raidDao
          .upsertDependency(ProgramDependenciesCompanion.insert(
        id: 'd-1',
        projectId: 'proj',
        description: 'D',
        escalatedAt: Value(DateTime.now()),
      ));

      final gw = _FakeCascadeGateway();
      final svc = CascadeService(db, gateway: gw);
      await svc.pushAllEscalatedRaid('proj');

      final kinds = gw.pushes.map((p) => p.itemKind).toSet();
      expect(kinds, {
        CascadeKinds.risk,
        CascadeKinds.assumption,
        CascadeKinds.issue,
        CascadeKinds.dependency,
      });
    });
  });
}
