import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/finance/variance.dart';

void main() {
  late AppDatabase db;
  const pid = 'p1';
  late List<CostCategory> cats;
  late String budgetId;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .upsertProject(ProjectsCompanion.insert(id: pid, name: 'V2 Test'));
    await db.financeDao.seedDefaultCategories(pid);
    cats = await db.financeDao.getCategories(pid);
    budgetId = await db.financeDao
        .createBudget(projectId: pid, name: 'v1', currency: 'GBP');
    await db.financeDao.upsertLine(
      id: 'b1',
      projectId: pid,
      budgetId: budgetId,
      costCategoryId: cats[0].id,
      financialYear: 'FY26',
      amountMinor: 100000,
    );
    await db.financeDao.upsertLine(
      id: 'b2',
      projectId: pid,
      budgetId: budgetId,
      costCategoryId: cats[1].id,
      financialYear: 'FY27',
      amountMinor: 200000,
    );
    await db.financeDao.approveBudget(budgetId);
  });
  tearDown(() async => db.close());

  group('Forecast snapshots', () {
    test('createSnapshot copies the approved budget', () async {
      final id = await db.financeDao.createSnapshot(
          projectId: pid, period: '2026-07', copyFromBudget: true);
      final lines = await db.financeDao.getForecastLines(id);
      expect(lines.length, 2);
      final totals = await db.financeDao.getForecastTotals(id);
      expect(totals.totalMinor, 300000);
      expect(totals.byFinancialYear['FY26'], 100000);
    });

    test('one snapshot per period', () async {
      await db.financeDao.createSnapshot(projectId: pid, period: '2026-07');
      expect(
          () =>
              db.financeDao.createSnapshot(projectId: pid, period: '2026-07'),
          throwsStateError);
    });

    test('copy from previous snapshot carries edits forward', () async {
      final s1 = await db.financeDao.createSnapshot(
          projectId: pid, period: '2026-06', copyFromBudget: true);
      final l = (await db.financeDao.getForecastLines(s1)).first;
      await db.financeDao.upsertForecastLine(
        id: l.id,
        projectId: pid,
        snapshotId: s1,
        costCategoryId: l.costCategoryId,
        financialYear: l.financialYear,
        amountMinor: 150000,
      );
      await db.financeDao.submitSnapshot(s1);
      final s2 = await db.financeDao.createSnapshot(
          projectId: pid, period: '2026-07', copyFromSnapshotId: s1);
      final totals = await db.financeDao.getForecastTotals(s2);
      expect(totals.totalMinor, 350000);
    });

    test('submitted snapshots reject line edits and reopen restores',
        () async {
      final s1 = await db.financeDao.createSnapshot(
          projectId: pid, period: '2026-07', copyFromBudget: true);
      final l = (await db.financeDao.getForecastLines(s1)).first;
      await db.financeDao.submitSnapshot(s1);
      expect(
          () => db.financeDao.upsertForecastLine(
                id: l.id,
                projectId: pid,
                snapshotId: s1,
                costCategoryId: l.costCategoryId,
                financialYear: l.financialYear,
                amountMinor: 1,
              ),
          throwsStateError);
      expect(() => db.financeDao.deleteForecastLine(l.id), throwsStateError);
      expect(() => db.financeDao.deleteWorkingSnapshot(s1), throwsStateError);

      await db.financeDao.reopenSnapshot(s1);
      await db.financeDao.deleteForecastLine(l.id);
      expect((await db.financeDao.getForecastLines(s1)).length, 1);
    });

    test('trend returns oldest-first totals with status', () async {
      final s1 = await db.financeDao.createSnapshot(
          projectId: pid, period: '2026-06', copyFromBudget: true);
      await db.financeDao.submitSnapshot(s1);
      await db.financeDao.createSnapshot(
          projectId: pid, period: '2026-07', copyFromSnapshotId: s1);
      final trend = await db.financeDao.getForecastTrend(pid);
      expect(trend.map((t) => t.period).toList(), ['2026-06', '2026-07']);
      expect(trend.first.submitted, isTrue);
      expect(trend.last.submitted, isFalse);
      expect(trend.every((t) => t.totalMinor == 300000), isTrue);
    });

    test('snapshot lifecycle is audited; copied lines are not', () async {
      final before = (await db.financeDao.getAuditLog(pid)).length;
      final s1 = await db.financeDao.createSnapshot(
          projectId: pid, period: '2026-07', copyFromBudget: true);
      await db.financeDao.submitSnapshot(s1, changedBy: 'Paul');
      final log = await db.financeDao.getAuditLog(pid);
      // Exactly 2 new entries: snapshot created + submitted. The two
      // copied lines are covered by the created entry.
      expect(log.length, before + 2);
      final submit = log.firstWhere((e) =>
          e.entityType == 'ForecastSnapshot' && e.newValue == 'submitted');
      expect(submit.changedBy, 'Paul');
    });
  });

  group('Actuals', () {
    test('upsert, totals keyed by period, delete', () async {
      await db.financeDao.upsertActualLine(
        id: 'a1',
        projectId: pid,
        period: '2026-06',
        costCategoryId: cats[0].id,
        amountMinor: 40000,
        changedBy: 'Paul',
      );
      await db.financeDao.upsertActualLine(
        id: 'a2',
        projectId: pid,
        period: '2026-07',
        costCategoryId: cats[0].id,
        amountMinor: 45000,
      );
      final totals = await db.financeDao.getActualsTotals(pid);
      expect(totals.totalMinor, 85000);
      expect(totals.byFinancialYear['2026-06'], 40000);
      expect(totals.byFinancialYear['2026-07'], 45000);

      final line =
          (await db.financeDao.getActuals(pid)).firstWhere((l) => l.id == 'a1');
      expect(line.enteredBy, 'Paul');
      expect(line.source, 'manual');

      await db.financeDao.deleteActualLine('a1');
      expect((await db.financeDao.getActuals(pid)).length, 1);
      final log = await db.financeDao.getAuditLog(pid);
      expect(
          log.where((e) => e.entityType == 'ActualLine').length, 3);
    });
  });

  group('Variance tolerance', () {
    test('defaults to 500bp and audits changes', () async {
      final budget = (await db.financeDao.getBudgetById(budgetId))!;
      expect(budget.varianceToleranceBp, 500);
      await db.financeDao
          .setVarianceTolerance(budgetId, 750, changedBy: 'Paul');
      expect((await db.financeDao.getBudgetById(budgetId))!
          .varianceToleranceBp, 750);
      final log = await db.financeDao.getAuditLog(pid);
      final entry =
          log.firstWhere((e) => e.field == 'varianceToleranceBp');
      expect(entry.oldValue, '500');
      expect(entry.newValue, '750');
    });
  });

  group('Variance maths', () {
    test('bpOf rounds half away from zero', () {
      expect(VarianceRow.bpOf(8, 100), 800);
      expect(VarianceRow.bpOf(-8, 100), -800);
      // 12345/100000 = 1234.5 bp → 1235 (half away)
      expect(VarianceRow.bpOf(12345, 100000), 1235);
      expect(VarianceRow.bpOf(-12345, 100000), -1235);
      // 12344/100000 = 1234.4 → 1234
      expect(VarianceRow.bpOf(12344, 100000), 1234);
      expect(VarianceRow.bpOf(0, 100), 0);
      expect(VarianceRow.bpOf(5, 0), isNull);
      expect(VarianceRow.bpOf(5, -100), isNull);
    });

    test('computeVariance unions categories and appends total', () {
      final budget = BudgetTotals.fromLines([]);
      final b = BudgetTotals.fromForecastLines([]);
      expect(budget.totalMinor, 0);
      expect(b.totalMinor, 0);
      final rows = computeVariance(budget, b, ['c1']);
      expect(rows.single.key, VarianceRow.totalKey);
    });

    test('variance rows match hand-computed Excel values', () async {
      final s1 = await db.financeDao.createSnapshot(
          projectId: pid, period: '2026-07', copyFromBudget: true);
      final l = (await db.financeDao.getForecastLines(s1))
          .firstWhere((l) => l.costCategoryId == cats[0].id);
      await db.financeDao.upsertForecastLine(
        id: l.id,
        projectId: pid,
        snapshotId: s1,
        costCategoryId: l.costCategoryId,
        financialYear: l.financialYear,
        amountMinor: 108300, // +8.3% on 100000
      );
      final budgetTotals = await db.financeDao.getTotals(budgetId);
      final forecastTotals = await db.financeDao.getForecastTotals(s1);
      final rows = computeVariance(
          budgetTotals, forecastTotals, cats.map((c) => c.id).toList());

      final catRow = rows.firstWhere((r) => r.key == cats[0].id);
      expect(catRow.varianceMinor, 8300);
      expect(catRow.varianceBp, 830);
      final unchanged = rows.firstWhere((r) => r.key == cats[1].id);
      expect(unchanged.varianceBp, 0);
      final total = rows.firstWhere((r) => r.key == VarianceRow.totalKey);
      expect(total.budgetMinor, 300000);
      expect(total.forecastMinor, 308300);
      // 8300/300000 = 2.7666..% = 276.66 bp → 277 (half away)
      expect(total.varianceBp, 277);
    });
  });
}
