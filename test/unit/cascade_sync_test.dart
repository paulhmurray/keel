import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_service.dart';
import 'package:keel/core/cascade/cascade_sync.dart';
import 'package:keel/core/database/database.dart';

/// In-memory [CascadeGateway] double — records pushes/deletes and
/// returns scripted pulls. Same shape as the one in
/// cascade_service_test.dart; duplicated here so this file reads on its
/// own.
class _FakeCascadeGateway implements CascadeGateway {
  final List<_PushCall> pushes = [];
  final Map<String, CascadePullSnapshot> _byCode = {};

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
    pushes.add(_PushCall(itemKind: itemKind, itemId: itemId));
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
  }) async {}
}

class _PushCall {
  final String itemKind;
  final String itemId;
  const _PushCall({required this.itemKind, required this.itemId});
}

/// Minimal [RemoteLinksGateway] double for the link-activation path.
/// Reports a single code as fully-paired-and-active so
/// refreshPendingLinks flips it during the reconcile.
class _FakeLinksGateway implements RemoteLinksGateway {
  final Map<String, RemoteLinkSnapshot> _byCode = {};

  void preloadActiveCode({required String code, required String myUserId}) {
    _byCode[code] = RemoteLinkSnapshot(
      code: code,
      sideA: const RemoteLinkParty(
        userId: 'remote-pm',
        entityId: 'remote-prog',
        kind: 'programme',
        name: 'Remote Programme',
      ),
      sideB: RemoteLinkParty(
        userId: myUserId,
        entityId: 'proj',
        kind: 'project',
        name: 'Sub Project',
      ),
      isActive: true,
    );
  }

  @override
  Future<RemoteLinkSnapshot> claim({
    required String code,
    required String entityId,
    required String kind,
    required String name,
  }) async =>
      _byCode[code]!;

  @override
  Future<RemoteLinkSnapshot?> fetch(String code) async => _byCode[code];

  @override
  Future<void> revoke(String code) async {}
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
  });

  tearDown(() async => db.close());

  /// Pairs proj↔prog as an active link via the same-machine redeem flow.
  Future<void> seedActiveLink() async {
    final code = await db.programmeLinksDao.generateCodeForEntity(
        ownerEntityId: 'prog', ownerKind: 'programme');
    await db.programmeLinksDao.redeemCode(
      code: code,
      ownerEntityId: 'proj',
      ownerKind: 'project',
    );
  }

  group('reconcileCascade — project side', () {
    test(
        'replays an escalated risk up to the active link (the path the '
        'Sync button previously never triggered)', () async {
      await seedActiveLink();
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'r-1',
        projectId: 'proj',
        description: 'Escalated risk',
        escalatedAt: Value(DateTime.now()),
      ));

      final gw = _FakeCascadeGateway();
      await reconcileCascade(
        db: db,
        cascade: CascadeService(db, gateway: gw),
        projectId: 'proj',
      );

      expect(
        gw.pushes.where((p) => p.itemKind == CascadeKinds.risk).map((p) => p.itemId),
        ['r-1'],
      );
    });

    test('replays escalated actions + decisions and work packages too',
        () async {
      await seedActiveLink();
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-1',
        projectId: 'proj',
        description: 'Escalated action',
        escalatedAt: Value(DateTime.now()),
      ));
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-1',
        projectId: 'proj',
        description: 'Escalated decision',
        escalatedAt: Value(DateTime.now()),
      ));
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: 'wp-1',
          projectId: 'proj',
          name: 'WP One',
        ),
      );

      final gw = _FakeCascadeGateway();
      await reconcileCascade(
        db: db,
        cascade: CascadeService(db, gateway: gw),
        projectId: 'proj',
      );

      expect(gw.pushes.map((p) => p.itemKind).toSet(), {
        CascadeKinds.action,
        CascadeKinds.decision,
        CascadeKinds.workPackage,
      });
    });

    test('pushes nothing when the project has no active links', () async {
      // No seedActiveLink() — project is unlinked.
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'r-1',
        projectId: 'proj',
        description: 'Escalated risk',
        escalatedAt: Value(DateTime.now()),
      ));
      final gw = _FakeCascadeGateway();
      await reconcileCascade(
        db: db,
        cascade: CascadeService(db, gateway: gw),
        projectId: 'proj',
      );
      expect(gw.pushes, isEmpty);
    });
  });

  group('reconcileCascade — programme side', () {
    test('pulls cascaded items down into the programme on sync', () async {
      await seedActiveLink();
      final code =
          (await db.programmeLinksDao.getLinksForEntity('prog')).single.code;
      final gw = _FakeCascadeGateway()
        ..scriptPull(
          code,
          CascadePullSnapshot(items: [
            const CascadeRecord(
              sourceEntityId: 'proj',
              itemKind: CascadeKinds.risk,
              itemId: 'r-9',
              payload: {
                'description': 'Programme-visible risk',
                'likelihood': 'high',
                'impact': 'high',
                'status': 'open',
              },
              deleted: false,
            ),
          ], cursor: ''),
        );

      final applied = await reconcileCascade(
        db: db,
        cascade: CascadeService(db, gateway: gw),
        projectId: 'prog',
      );

      expect(applied, 1);
      final risks = await db.raidDao.getRisksForProject('prog');
      expect(risks, hasLength(1));
      expect(risks.single.id, 'cascade:risk:proj:r-9');
      expect(risks.single.sourceProjectId, 'proj');
      // No outgoing pushes — a programme only consumes on reconcile.
      expect(gw.pushes, isEmpty);
    });
  });

  group('reconcileCascade — link activation', () {
    test(
        'activates a pending_remote link mid-reconcile, then immediately '
        'pushes escalated items through it (no relaunch needed)', () async {
      // Generating a code on the project leaves it with a pending_remote
      // link — the partner programme lives on another machine and hasn't
      // been confirmed yet, so nothing cascades through it.
      await db.programmeLinksDao.generateCodeForEntity(
          ownerEntityId: 'proj', ownerKind: 'project');
      final pending =
          (await db.programmeLinksDao.getLinksForEntity('proj')).single;
      expect(pending.status, 'pending_remote');

      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'r-1',
        projectId: 'proj',
        description: 'Escalated before activation',
        escalatedAt: Value(DateTime.now()),
      ));

      final links = _FakeLinksGateway()
        ..preloadActiveCode(code: pending.code, myUserId: 'me');
      final gw = _FakeCascadeGateway();

      await reconcileCascade(
        db: db,
        cascade: CascadeService(db, gateway: gw),
        projectId: 'proj',
        linksGateway: links,
        remoteUserId: 'me',
      );

      // The link flipped to active...
      final refreshed =
          (await db.programmeLinksDao.getLinksForEntity('proj')).single;
      expect(refreshed.status, 'active');
      // ...and the previously-stranded escalated risk got pushed.
      expect(
        gw.pushes.where((p) => p.itemKind == CascadeKinds.risk).map((p) => p.itemId),
        ['r-1'],
      );
    });
  });
}
