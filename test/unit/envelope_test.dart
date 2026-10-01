import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_service.dart';
import 'package:keel/core/cascade/cascade_sync.dart';
import 'package:keel/core/cascade/local_cascade_gateway.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/import/json_importer.dart';

/// Envelope DAO rules and the downward allocation cascade end to end.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'proj', name: 'TAC'));
    await db.projectDao.insertProject(ProjectsCompanion.insert(
        id: 'prog', name: 'Digital Toolkit', kind: const Value('programme')));
    final share = await db.programmeLinksDao
        .generateCodeForEntity(ownerEntityId: 'prog', ownerKind: 'programme');
    await db.programmeLinksDao
        .redeemCode(code: share, ownerEntityId: 'proj', ownerKind: 'project');
    await db.decisionsDao.upsertDecision(const DecisionsCompanion(
      id: Value('dc1'),
      projectId: Value('prog'),
      ref: Value('DC1'),
      description: Value('Release contingency for the licence dispute'),
      status: Value('decided'),
    ));
  });
  tearDown(() => db.close());

  group('DAO rules', () {
    test('a draw or return needs its decision; an allocation does not', () async {
      await db.financeDao.upsertFunding(
          id: 'f1', programmeId: 'prog', name: 'BC', amountMinor: 1000000, changedBy: 't');
      await db.financeDao.recordMovement(
          id: 'a1', programmeId: 'prog', kind: 'allocate', amountMinor: 600000,
          linkedProjectId: 'proj', movedOn: '2026-07-01', changedBy: 't');
      expect(
          () => db.financeDao.recordMovement(
              id: 'd0', programmeId: 'prog', kind: 'draw', amountMinor: 1,
              linkedProjectId: 'proj', movedOn: '2026-08-01'),
          throwsStateError);
      expect(
          () => db.financeDao.recordMovement(
              id: 'z', programmeId: 'prog', kind: 'draw', amountMinor: 0,
              linkedProjectId: 'proj', decisionId: 'dc1', movedOn: '2026-08-01'),
          throwsArgumentError);
      await db.financeDao.recordMovement(
          id: 'd1', programmeId: 'prog', kind: 'draw', amountMinor: 100000,
          linkedProjectId: 'proj', decisionId: 'dc1', reason: 'Licence dispute',
          movedOn: '2026-08-01', changedBy: 't');
      expect((await db.financeDao.getMovementsForDecision('dc1')).single.id, 'd1');
      // Every write audited.
      final audit = await db.financeDao.getAuditLog('prog');
      expect(audit.map((a) => a.entityType).toSet(),
          containsAll(['FundingApproval', 'ContingencyMovement']));
      await db.financeDao.setContingencyWarnBp('prog', 2500, changedBy: 't');
      expect((await db.financeDao.getFinanceSettings('prog'))!.contingencyWarnBp, 2500);
    });
  });

  group('allocation cascades DOWN to the project', () {
    test('reconcile sends the allocation with its history; project reads it '
        'read-only', () async {
      await db.financeDao.upsertFunding(
          id: 'f1', programmeId: 'prog', name: 'BC', amountMinor: 1000000, changedBy: 't');
      await db.financeDao.recordMovement(
          id: 'a1', programmeId: 'prog', kind: 'allocate', amountMinor: 600000,
          linkedProjectId: 'proj', movedOn: '2026-07-01', changedBy: 't');
      await db.financeDao.recordMovement(
          id: 'd1', programmeId: 'prog', kind: 'draw', amountMinor: 100000,
          linkedProjectId: 'proj', decisionId: 'dc1', reason: 'Licence dispute',
          movedOn: '2026-08-01', changedBy: 't');

      final svc = CascadeService(db, gateway: LocalCascadeGateway(db));
      await reconcileCascade(db: db, cascade: svc, projectId: 'prog'); // pushes allocation
      await reconcileCascade(db: db, cascade: svc, projectId: 'proj'); // pulls it

      final got = (await db.financeDao.getReceivedAllocations('proj')).single;
      expect(got.id, 'cascade:allocation:prog:proj');
      expect(got.programmeId, 'prog');
      expect(got.programmeName, 'Digital Toolkit');
      expect(got.amountMinor, 700000);
      expect(got.currency, 'AUD');
      expect(got.historyJson, contains('"decision_ref":"DC1"'));
      expect(got.historyJson, contains('Licence dispute'));

      // The programme never applies its own allocation record to itself.
      expect(await db.financeDao.getReceivedAllocations('prog'), isEmpty);

      // A return updates the amount on the next reconcile.
      await db.financeDao.recordMovement(
          id: 'r1', programmeId: 'prog', kind: 'return', amountMinor: 50000,
          linkedProjectId: 'proj', decisionId: 'dc1', movedOn: '2026-09-01');
      await svc.pushAllocation('prog', 'proj');
      await svc.pullForProject('proj');
      expect((await db.financeDao.getReceivedAllocations('proj')).single.amountMinor, 650000);
    });
  });

  test('envelope rows ride in the sync blob', () async {
    await db.financeDao.upsertFunding(
        id: 'f1', programmeId: 'prog', name: 'BC', amountMinor: 1000000,
        approvedOn: '2026-07-01', decisionId: 'dc1', changedBy: 't');
    await db.financeDao.recordMovement(
        id: 'a1', programmeId: 'prog', kind: 'allocate', amountMinor: 600000,
        linkedProjectId: 'proj', movedOn: '2026-07-01', changedBy: 't');
    await db.financeDao.setContingencyWarnBp('prog', 1500);
    await db.financeDao.upsertReceivedAllocationRaw(const ReceivedAllocationsCompanion(
      id: Value('cascade:allocation:other:proj'),
      projectId: Value('proj'),
      programmeId: Value('other'),
      amountMinor: Value(42),
    ));

    final other = AppDatabase.memory();
    addTearDown(other.close);
    for (final pid in ['prog', 'proj']) {
      final blob = await JsonExporter.exportProjectToString(projectId: pid, db: db);
      await JsonImporter.importFromString(blob, other);
    }
    expect((await other.financeDao.getFunding('prog')).single.decisionId, 'dc1');
    expect((await other.financeDao.getMovements('prog')).single.amountMinor, 600000);
    expect((await other.financeDao.getFinanceSettings('prog'))!.contingencyWarnBp, 1500);
    expect((await other.financeDao.getReceivedAllocations('proj')).single.amountMinor, 42);
  });
}
