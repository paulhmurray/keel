import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_service.dart';
import 'package:keel/core/cascade/cascade_sync.dart';
import 'package:keel/core/cascade/local_cascade_gateway.dart';
import 'package:keel/core/database/database.dart';

/// Portfolio tier over the cascade: a portfolio links programmes, each
/// programme pushes ONE computed pulse per week over its upward link, and
/// the portfolio applies it into PortfolioPulses. Runs over the real
/// same-machine transport (LocalCascadeGateway → CascadeItems).
void main() {
  late AppDatabase db;
  late CascadeService cascade;

  setUp(() async {
    db = AppDatabase.memory();
    cascade = CascadeService(db, gateway: LocalCascadeGateway(db));
    await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: 'port',
      name: 'PMO Portfolio',
      kind: const Value('portfolio'),
    ));
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

  Future<void> linkProjectToProgramme() async {
    final code = await db.programmeLinksDao.generateCodeForEntity(
        ownerEntityId: 'prog', ownerKind: 'programme');
    await db.programmeLinksDao.redeemCode(
        code: code, ownerEntityId: 'proj', ownerKind: 'project');
  }

  Future<void> linkProgrammeToPortfolio() async {
    final code = await db.programmeLinksDao.generateCodeForEntity(
        ownerEntityId: 'port', ownerKind: 'portfolio');
    final r = await db.programmeLinksDao.redeemCode(
        code: code, ownerEntityId: 'prog', ownerKind: 'programme');
    expect(r.outcome, RedeemOutcome.activatedLocally);
  }

  group('link model', () {
    test('a portfolio code is for a programme; the programme redeeming it '
        'records the partner as a portfolio', () async {
      await linkProgrammeToPortfolio();
      final portLinks = await db.programmeLinksDao.getLinksForEntity('port');
      expect(portLinks.single.partnerKind, 'programme');
      expect(portLinks.single.partnerLocalId, 'prog');
      expect(portLinks.single.status, 'active');
      final progLinks = await db.programmeLinksDao.getLinksForEntity('prog');
      expect(progLinks.single.ownerKind, 'programme');
      expect(progLinks.single.partnerKind, 'portfolio');
      expect(progLinks.single.partnerLocalId, 'port');
    });

    test('a programme redeeming a PROJECT code still pairs as before', () async {
      final code = await db.programmeLinksDao.generateCodeForEntity(
          ownerEntityId: 'proj', ownerKind: 'project');
      final r = await db.programmeLinksDao.redeemCode(
          code: code, ownerEntityId: 'prog', ownerKind: 'programme');
      expect(r.outcome, RedeemOutcome.activatedLocally);
      final progLinks = await db.programmeLinksDao.getLinksForEntity('prog');
      expect(progLinks.single.partnerKind, 'project');
    });

    test('getProjectLinksForProgramme excludes the upward portfolio link, '
        'so allocation targets and filter chips never list the portfolio',
        () async {
      await linkProjectToProgramme();
      await linkProgrammeToPortfolio();
      final all = await db.programmeLinksDao.getLinksForEntity('prog');
      expect(all, hasLength(2));
      final down = await db.programmeLinksDao.getProjectLinksForProgramme('prog');
      expect(down.single.partnerLocalId, 'proj');
      expect(down.single.partnerKind, 'project');
    });

    test('a project cannot redeem a portfolio code (tiers must be adjacent)',
        () async {
      final code = await db.programmeLinksDao.generateCodeForEntity(
          ownerEntityId: 'port', ownerKind: 'portfolio');
      final r = await db.programmeLinksDao.redeemCode(
          code: code, ownerEntityId: 'proj', ownerKind: 'project');
      // No same-machine partner of an acceptable kind → parked as pending.
      expect(r.outcome, RedeemOutcome.pendingRemote);
      final portLinks = await db.programmeLinksDao.getLinksForEntity('port');
      expect(portLinks.single.status, 'pending_remote');
    });
  });

  group('pulse', () {
    test('programme with no portfolio link pushes nothing and computes '
        'nothing', () async {
      await linkProjectToProgramme();
      final pulse = await cascade.pushPulse('prog');
      expect(pulse, isNull);
      expect(await db.portfolioPulsesDao.getForPortfolio('port'), isEmpty);
    });

    test('reconcile on the programme pushes a pulse; reconcile on the '
        'portfolio lands it in PortfolioPulses', () async {
      await linkProjectToProgramme();
      await linkProgrammeToPortfolio();
      // Something for the pulse to say: a red WP on the project, cascaded.
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion.insert(
          id: 'wp-1',
          projectId: 'proj',
          name: 'WP One',
          ragStatus: const Value('red'),
        ),
      );
      await db.reportsDao.upsertReport(StatusReportsCompanion.insert(
        id: 'rep-1',
        projectId: 'prog',
        title: 'Weekly',
        overallRag: const Value('green'),
        reportDate: Value(DateTime(2026, 10, 24)),
      ));

      // Project pushes its WP up; programme pulls it then pushes its pulse.
      await reconcileCascade(db: db, cascade: cascade, projectId: 'proj');
      await reconcileCascade(db: db, cascade: cascade, projectId: 'prog');
      // Portfolio pulls.
      final applied =
          await reconcileCascade(db: db, cascade: cascade, projectId: 'port');
      expect(applied, 1);

      final rows = await db.portfolioPulsesDao.getForPortfolio('port');
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.sourceProgrammeId, 'prog');
      expect(row.sourceProgrammeName, 'Big Programme');
      expect(row.computedRag, 'red', reason: 'cascaded WP is red');
      expect(row.reportedRag, 'green', reason: 'the programme said green');
      expect(row.id, startsWith('pulse:prog:'));
      expect(row.payload, contains('"computed_rag":"red"'));
    });

    test('a second push in the same week replaces the row; a new week adds '
        'one', () async {
      await linkProgrammeToPortfolio();
      await cascade.pushPulse('prog', now: DateTime(2026, 10, 27));
      await cascade.pushPulse('prog', now: DateTime(2026, 10, 29));
      await cascade.pullForPortfolio('port');
      expect(await db.portfolioPulsesDao.getForPortfolio('port'), hasLength(1));

      await cascade.pushPulse('prog', now: DateTime(2026, 11, 3));
      await cascade.pullForPortfolio('port');
      final rows = await db.portfolioPulsesDao.getForPortfolio('port');
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.weekOf).toSet(), {'2026-10-26', '2026-11-02'});
      expect(latestPerProgramme(rows).single.weekOf, '2026-11-02');
      final history = await db.portfolioPulsesDao.getHistory('port', 'prog');
      expect(history.map((r) => r.weekOf), ['2026-10-26', '2026-11-02']);
    });

    test('the portfolio channel never leaks allocations: a programme with '
        'an upward link pushes allocations only to its projects', () async {
      await linkProjectToProgramme();
      await linkProgrammeToPortfolio();
      await cascade.pushAllAllocations('prog');
      final items = await db.select(db.cascadeItems).get();
      final allocationCodes = items
          .where((i) => i.itemKind == CascadeKinds.allocation)
          .map((i) => i.code)
          .toSet();
      final portCode =
          (await db.programmeLinksDao.getLinksForEntity('port')).single.code;
      expect(allocationCodes, isNot(contains(portCode)));
      expect(allocationCodes, hasLength(1));
    });

    test('pullForProgramme ignores the upward channel and its own pulses',
        () async {
      await linkProgrammeToPortfolio();
      await cascade.pushPulse('prog');
      // Nothing to apply on the programme side: the only item on any of
      // its channels is its own pulse.
      expect(await cascade.pullForProgramme('prog'), 0);
    });

    test('pulses carry the link code, and revoking the link from EITHER side '
        'drops that programme from the portfolio', () async {
      await linkProgrammeToPortfolio();
      await cascade.pushPulse('prog');
      await cascade.pullForPortfolio('port');
      final portLink =
          (await db.programmeLinksDao.getLinksForEntity('port')).single;
      final row = (await db.portfolioPulsesDao.getForPortfolio('port')).single;
      expect(row.linkCode, portLink.code);

      // Revoke from the programme side (the twin row is the portfolio's).
      final progLink =
          (await db.programmeLinksDao.getLinksForEntity('prog')).single;
      await db.programmeLinksDao.revokeLink(progLink.id);
      expect(await db.portfolioPulsesDao.getForPortfolio('port'), isEmpty);
    });

    test('deleting a same-machine programme: link repair revokes the dangling '
        'row and drops its pulses', () async {
      await linkProgrammeToPortfolio();
      await cascade.pushPulse('prog');
      await cascade.pullForPortfolio('port');
      expect(await db.portfolioPulsesDao.getForPortfolio('port'), hasLength(1));
      await db.deleteProjectCascade('prog');
      await db.programmeLinksDao.repairSameMachineLinks();
      expect(await db.portfolioPulsesDao.getForPortfolio('port'), isEmpty);
      final portLink =
          (await db.programmeLinksDao.getLinksForEntity('port')).single;
      expect(portLink.status, 'revoked');
    });

    test('deleting the portfolio removes its pulses', () async {
      await linkProgrammeToPortfolio();
      await cascade.pushPulse('prog');
      await cascade.pullForPortfolio('port');
      expect(await db.portfolioPulsesDao.getForPortfolio('port'), hasLength(1));
      await db.deleteProjectCascade('port');
      expect(await db.select(db.portfolioPulses).get(), isEmpty);
    });
  });
}
