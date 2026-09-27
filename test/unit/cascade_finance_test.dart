import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/cascade/cascade_service.dart';
import 'package:keel/core/cascade/cascade_sync.dart';
import 'package:keel/core/cascade/local_cascade_gateway.dart';
import 'package:keel/core/database/database.dart';

/// Finance cascade: approved budgets, submitted forecasts, actuals and
/// categories flowing project → programme over a full-detail link.
class _FakeGateway implements CascadeGateway {
  final pushes = <({String kind, String id, Map<String, dynamic> payload})>[];
  final deletes = <({String kind, String id})>[];
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
      pushes.add((kind: itemKind, id: itemId, payload: payload));

  @override
  Future<CascadePullSnapshot> pull({required String code, String? since}) async =>
      _byCode[code] ?? const CascadePullSnapshot(items: [], cursor: '');

  @override
  Future<void> delete({
    required String code,
    required String itemKind,
    required String itemId,
  }) async =>
      deletes.add((kind: itemKind, id: itemId));
}

/// Same-machine gateway: pushes land in cascade_items and the programme
/// pulls them back — the real end-to-end path.
void main() {
  late AppDatabase db;

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
    await db.financeDao.seedDefaultCategories('proj', changedBy: 't');
  });
  tearDown(() => db.close());

  Future<void> setLevel(String level) async {
    for (final l in await db.programmeLinksDao.getLinksForEntity('proj')) {
      await db.programmeLinksDao.setShareLevel(l.id, level);
    }
  }

  Future<(String budgetId, List<CostCategory> cats)> approvedBudget(
      {int people = 120000, String name = 'BC v1'}) async {
    final cats = await db.financeDao.getCategories('proj');
    final id = await db.financeDao.createBudget(
        projectId: 'proj', name: name, currency: 'AUD', changedBy: 't');
    await db.financeDao.upsertLine(
        id: 'l-$name-1', projectId: 'proj', budgetId: id,
        costCategoryId: cats[0].id, workstreamId: 'wp-1',
        financialYear: 'FY26', amountMinor: people, changedBy: 't');
    await db.financeDao.upsertLine(
        id: 'l-$name-2', projectId: 'proj', budgetId: id,
        costCategoryId: cats[1].id, financialYear: 'FY27',
        amountMinor: 4550, changedBy: 't');
    await db.financeDao.approveBudget(id, approvedBy: 'Sponsor', changedBy: 't');
    return (id, cats);
  }

  group('push side', () {
    test('an approved budget pushes header + lines; a draft pushes nothing',
        () async {
      final gw = _FakeGateway();
      final svc = CascadeService(db, gateway: gw);
      final cats = await db.financeDao.getCategories('proj');
      final draft = await db.financeDao.createBudget(
          projectId: 'proj', name: 'Draft', currency: 'AUD', changedBy: 't');
      await svc.pushBudget(draft);
      expect(gw.pushes, isEmpty);

      final (approved, _) = await approvedBudget();
      await svc.pushBudget(approved);
      final p = gw.pushes.single;
      expect(p.kind, CascadeKinds.budget);
      expect(p.payload['status'], 'approved');
      expect(p.payload['currency'], 'AUD');
      final lines = (p.payload['lines'] as List).cast<Map>();
      expect(lines, hasLength(2));
      expect(lines.first['cost_category_id'], cats[0].id);
      expect(lines.first['workstream_id'], 'wp-1');
      expect(lines.first['amount_minor'], 120000);
    });

    test('approving a second budget tombstones the superseded one on the '
        'channel', () async {
      final (v1, _) = await approvedBudget(name: 'v1');
      final (v2, _) = await approvedBudget(name: 'v2');
      final gw = _FakeGateway();
      await CascadeService(db, gateway: gw).pushBudget(v2);
      expect(gw.pushes.single.id, v2);
      expect(gw.deletes.single.kind, CascadeKinds.budget);
      expect(gw.deletes.single.id, v1);
    });

    test('submitting a snapshot pushes it with lines; working ones stay home',
        () async {
      await approvedBudget();
      final gw = _FakeGateway();
      final svc = CascadeService(db, gateway: gw);
      final snap = await db.financeDao.createSnapshot(
          projectId: 'proj', period: '2026-09', copyFromBudget: true, changedBy: 't');
      await svc.pushForecastSnapshot(snap);
      expect(gw.pushes, isEmpty);
      await db.financeDao.submitSnapshot(snap, changedBy: 't');
      await svc.pushForecastSnapshot(snap);
      expect(gw.pushes.single.kind, CascadeKinds.forecastSnapshot);
      expect(gw.pushes.single.payload['period'], '2026-09');
      expect((gw.pushes.single.payload['lines'] as List), hasLength(2));
    });

    test('pushAllFinance replays categories, the approved budget, submitted '
        'snapshots and actuals — and nothing over an escalated-only link',
        () async {
      final (_, cats) = await approvedBudget();
      final snap = await db.financeDao.createSnapshot(
          projectId: 'proj', period: '2026-09', copyFromBudget: true, changedBy: 't');
      await db.financeDao.submitSnapshot(snap, changedBy: 't');
      await db.financeDao.createSnapshot(
          projectId: 'proj', period: '2026-10', changedBy: 't'); // working
      await db.financeDao.upsertActualLine(
          id: 'act-1', projectId: 'proj', period: '2026-07',
          costCategoryId: cats[0].id, amountMinor: 30000, changedBy: 't');

      final gw = _FakeGateway();
      await CascadeService(db, gateway: gw).pushAllFinance('proj');
      final kinds = gw.pushes.map((p) => p.kind).toList();
      expect(kinds.where((k) => k == CascadeKinds.costCategory), hasLength(5));
      expect(kinds.where((k) => k == CascadeKinds.budget), hasLength(1));
      expect(kinds.where((k) => k == CascadeKinds.forecastSnapshot), hasLength(1));
      expect(kinds.where((k) => k == CascadeKinds.actual), hasLength(1));

      gw.pushes.clear();
      await setLevel('escalated');
      await CascadeService(db, gateway: gw).pushAllFinance('proj');
      expect(gw.pushes, isEmpty);
    });

    test('retractUnescalated withdraws finance from an escalated-only link',
        () async {
      final (budgetId, _) = await approvedBudget();
      await setLevel('escalated');
      final gw = _FakeGateway();
      await CascadeService(db, gateway: gw).retractUnescalated('proj');
      expect(gw.deletes.any((d) => d.kind == CascadeKinds.budget && d.id == budgetId),
          isTrue);
      expect(gw.deletes.where((d) => d.kind == CascadeKinds.costCategory), hasLength(5));
    });
  });

  group('end to end on the same machine', () {
    Future<CascadeService> local() async =>
        CascadeService(db, gateway: LocalCascadeGateway(db));

    test('the programme holds read-only copies, re-keyed, and its own '
        'finance getters never see them', () async {
      final (budgetId, cats) = await approvedBudget();
      final snap = await db.financeDao.createSnapshot(
          projectId: 'proj', period: '2026-09', copyFromBudget: true, changedBy: 't');
      await db.financeDao.submitSnapshot(snap, changedBy: 't');
      await db.financeDao.upsertActualLine(
          id: 'act-1', projectId: 'proj', period: '2026-07',
          costCategoryId: cats[0].id, workstreamId: 'wp-1',
          amountMinor: 30000, changedBy: 't');

      final svc = await local();
      await reconcileCascade(db: db, cascade: svc, projectId: 'proj');
      await reconcileCascade(db: db, cascade: svc, projectId: 'prog');

      // Copies exist, re-keyed.
      final cBudgets = await db.financeDao.getCascadedBudgets('prog');
      expect(cBudgets.single.id, 'cascade:budget:proj:$budgetId');
      expect(cBudgets.single.sourceProjectId, 'proj');
      final cLines = await db.financeDao.getCascadedBudgetLines('prog');
      expect(cLines, hasLength(2));
      final l1 = cLines.firstWhere((l) => l.id.endsWith('l-BC v1-1'));
      expect(l1.costCategoryId, 'cascade:cost_category:proj:${cats[0].id}');
      expect(l1.workstreamId, 'cascade:proj:wp-1');
      expect(l1.amountMinor, 120000);
      final cSnaps = await db.financeDao.getCascadedSnapshots('prog');
      expect(cSnaps.single.period, '2026-09');
      expect(await db.financeDao.getCascadedForecastLines('prog'), hasLength(2));
      final cActs = await db.financeDao.getCascadedActuals('prog');
      expect(cActs.single.costCategoryId,
          'cascade:cost_category:proj:${cats[0].id}');
      expect(await db.financeDao.getCascadedCategories('prog'), hasLength(5));

      // The programme's own finance is untouched by the copies.
      expect(await db.financeDao.getApprovedBudget('prog'), isNull);
      expect(await db.financeDao.getBudgets('prog'), isEmpty);
      expect(await db.financeDao.getCategories('prog'), isEmpty);
      expect(await db.financeDao.getSnapshots('prog'), isEmpty);
      expect(await db.financeDao.getActuals('prog'), isEmpty);
      // It can still seed its own categories and create its own snapshot
      // for a period a linked project already submitted.
      await db.financeDao.seedDefaultCategories('prog', changedBy: 't');
      expect(await db.financeDao.getCategories('prog'), hasLength(5));
      await db.financeDao.createSnapshot(
          projectId: 'prog', period: '2026-09', changedBy: 't');
    });

    test('approving a new budget replaces the cascaded copy of the old one',
        () async {
      final (v1, _) = await approvedBudget(name: 'v1');
      final svc = await local();
      await reconcileCascade(db: db, cascade: svc, projectId: 'proj');
      await reconcileCascade(db: db, cascade: svc, projectId: 'prog');
      expect(await db.financeDao.getCascadedBudgets('prog'), hasLength(1));

      final (v2, _) = await approvedBudget(name: 'v2', people: 150000);
      await reconcileCascade(db: db, cascade: svc, projectId: 'proj');
      await reconcileCascade(db: db, cascade: svc, projectId: 'prog');
      final copies = await db.financeDao.getCascadedBudgets('prog');
      expect(copies.single.id, 'cascade:budget:proj:$v2');
      expect(copies.single.id, isNot('cascade:budget:proj:$v1'));
      final lines = await db.financeDao.getCascadedBudgetLines('prog');
      expect(lines.map((l) => l.budgetId).toSet(), {'cascade:budget:proj:$v2'});
      expect(lines.fold<int>(0, (s, l) => s + l.amountMinor), 154550);
    });

    test('reopening a snapshot tombstones its copy and lines', () async {
      await approvedBudget();
      final snap = await db.financeDao.createSnapshot(
          projectId: 'proj', period: '2026-09', copyFromBudget: true, changedBy: 't');
      await db.financeDao.submitSnapshot(snap, changedBy: 't');
      final svc = await local();
      await reconcileCascade(db: db, cascade: svc, projectId: 'proj');
      await reconcileCascade(db: db, cascade: svc, projectId: 'prog');
      expect(await db.financeDao.getCascadedSnapshots('prog'), hasLength(1));

      await db.financeDao.reopenSnapshot(snap, changedBy: 't');
      await svc.deleteForecastSnapshot(projectId: 'proj', snapshotId: snap);
      await reconcileCascade(db: db, cascade: svc, projectId: 'prog');
      expect(await db.financeDao.getCascadedSnapshots('prog'), isEmpty);
      expect(await db.financeDao.getCascadedForecastLines('prog'), isEmpty);
    });

    test('the programme\'s own approved budget never round-trips as a copy',
        () async {
      await db.financeDao.seedDefaultCategories('prog', changedBy: 't');
      final cats = await db.financeDao.getCategories('prog');
      final own = await db.financeDao.createBudget(
          projectId: 'prog', name: 'Programme budget', currency: 'AUD', changedBy: 't');
      await db.financeDao.upsertLine(
          id: 'own-1', projectId: 'prog', budgetId: own,
          costCategoryId: cats[0].id, financialYear: 'FY26',
          amountMinor: 1, changedBy: 't');
      await db.financeDao.approveBudget(own, changedBy: 't');
      final svc = await local();
      await svc.pushBudget(own);
      await reconcileCascade(db: db, cascade: svc, projectId: 'prog');
      expect(await db.financeDao.getCascadedBudgets('prog'), isEmpty);
      expect((await db.financeDao.getApprovedBudget('prog'))!.id, own);
    });
  });
}
