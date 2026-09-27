import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/finance/programme_rollup.dart';

void main() {
  final t0 = DateTime(2026, 1, 1);
  CostCategory cat(String id, String src, String name) => CostCategory(
      id: id, projectId: 'prog', name: name, sortOrder: 0,
      sourceProjectId: src, createdAt: t0, updatedAt: t0);
  CategoryMerge merge(String srcCat, String target) => CategoryMerge(
      id: 'm-$srcCat', projectId: 'prog', sourceCategoryId: srcCat,
      targetName: target, createdAt: t0);
  ProjectBudget budget(String id, String src,
          {String currency = 'AUD', int tol = 500}) =>
      ProjectBudget(
          id: id, projectId: 'prog', name: 'B $src', status: 'approved',
          currency: currency, varianceToleranceBp: tol, sourceProjectId: src,
          createdAt: t0, updatedAt: t0);
  BudgetLine bl(String budgetId, String catId, String fy, int minor,
          {String src = 'a'}) =>
      BudgetLine(
          id: '$budgetId-$catId-$fy', projectId: 'prog', budgetId: budgetId,
          costCategoryId: catId, financialYear: fy, amountMinor: minor,
          sourceProjectId: src, createdAt: t0, updatedAt: t0);
  ForecastSnapshot snap(String id, String src, String period,
          {String status = 'submitted'}) =>
      ForecastSnapshot(
          id: id, projectId: 'prog', period: period, status: status,
          sourceProjectId: src, createdAt: t0, updatedAt: t0);
  ForecastLine fl(String snapId, String catId, String fy, int minor,
          {String src = 'a'}) =>
      ForecastLine(
          id: '$snapId-$catId-$fy', projectId: 'prog', snapshotId: snapId,
          costCategoryId: catId, financialYear: fy, amountMinor: minor,
          sourceProjectId: src, createdAt: t0, updatedAt: t0);
  ActualLine al(String id, String src, String catId, String period, int minor) =>
      ActualLine(
          id: id, projectId: 'prog', period: period, costCategoryId: catId,
          amountMinor: minor, source: 'manual', sourceProjectId: src,
          createdAt: t0, updatedAt: t0);

  group('rollupCategories', () {
    test('groups by normalised name and keeps the first spelling', () {
      final buckets = rollupCategories([
        cat('a-people', 'a', 'People'),
        cat('b-people', 'b', ' people '),
        cat('a-lic', 'a', 'Licences'),
        cat('b-lic', 'b', 'Software licences'),
      ], const []);
      expect(buckets.map((b) => b.name), ['Licences', 'People', 'Software licences']);
      expect(buckets[1].categoryIds, ['a-people', 'b-people']);
    });
    test('a merge moves the category under the target name', () {
      final buckets = rollupCategories([
        cat('a-lic', 'a', 'Licences'),
        cat('b-lic', 'b', 'Software licences'),
      ], [
        merge('a-lic', 'Software licences'),
      ]);
      expect(buckets, hasLength(1));
      expect(buckets.single.name, 'Software licences');
      expect(buckets.single.categoryIds.toSet(), {'a-lic', 'b-lic'});
    });
    test('normaliseCategoryName collapses case and whitespace', () {
      expect(normaliseCategoryName('  Software   Licences '), 'software licences');
    });
  });

  group('computeProgrammeFinance', () {
    test('per-project rows: budget, latest SUBMITTED forecast, actuals, '
        'variance against that project\'s tolerance', () {
      final f = computeProgrammeFinance(
        categories: [cat('a-p', 'a', 'People'), cat('b-p', 'b', 'People')],
        budgets: [budget('ba', 'a'), budget('bb', 'b', tol: 1000)],
        budgetLines: [
          bl('ba', 'a-p', 'FY26', 100000),
          bl('ba', 'a-p', 'FY27', 100000),
          bl('bb', 'b-p', 'FY26', 50000, src: 'b'),
        ],
        snapshots: [
          snap('sa1', 'a', '2026-07'),
          snap('sa2', 'a', '2026-08'), // latest submitted wins
          snap('sa3', 'a', '2026-09', status: 'working'), // ignored
          snap('sb1', 'b', '2026-08'),
        ],
        forecastLines: [
          fl('sa1', 'a-p', 'FY26', 999999),
          fl('sa2', 'a-p', 'FY26', 110000),
          fl('sa2', 'a-p', 'FY27', 110000), // 220k vs 200k → +10%
          fl('sa3', 'a-p', 'FY26', 1),
          fl('sb1', 'b-p', 'FY26', 54000, src: 'b'), // +8% within 10%
        ],
        actuals: [al('x1', 'a', 'a-p', '2026-07', 30000)],
        merges: const [],
      );
      final a = f.projects.firstWhere((r) => r.sourceId == 'a');
      expect(a.budgetMinor, 200000);
      expect(a.latestSnapshot!.period, '2026-08');
      expect(a.forecastMinor, 220000);
      expect(a.varianceBp, 1000);
      expect(a.breach, isTrue); // 10% > 5%
      expect(a.actualsMinor, 30000);
      final b = f.projects.firstWhere((r) => r.sourceId == 'b');
      expect(b.varianceBp, 800);
      expect(b.breach, isFalse); // 8% within 10%
      expect(f.budgetMinor, 250000);
      expect(f.forecastMinor, 274000);
      expect(f.actualsMinor, 30000);
      expect(f.breaches.map((r) => r.sourceId), ['a']);
      expect(f.financialYears, ['FY26', 'FY27']);
      // By category: both "People" roll up together.
      expect(f.categories.single.name, 'People');
      expect(f.categories.single.budgetMinor, 250000);
      expect(f.categories.single.forecastMinor, 274000);
      expect(f.categories.single.budgetByFy['FY26'], 150000);
    });

    test('no submitted forecast → forecast null, budget stands in for totals',
        () {
      final f = computeProgrammeFinance(
        categories: [cat('a-p', 'a', 'People')],
        budgets: [budget('ba', 'a')],
        budgetLines: [bl('ba', 'a-p', 'FY26', 100000)],
        snapshots: [snap('w', 'a', '2026-09', status: 'working')],
        forecastLines: [fl('w', 'a-p', 'FY26', 5)],
        actuals: const [],
        merges: const [],
      );
      expect(f.projects.single.forecastMinor, isNull);
      expect(f.projects.single.varianceBp, isNull);
      expect(f.projects.single.breach, isFalse);
      expect(f.forecastMinor, 100000);
    });

    test('a project in another currency is flagged and left out of totals',
        () {
      final f = computeProgrammeFinance(
        categories: [cat('a-p', 'a', 'People'), cat('c-p', 'c', 'People')],
        budgets: [budget('ba', 'a'), budget('bb', 'b'), budget('bc', 'c', currency: 'GBP')],
        budgetLines: [
          bl('ba', 'a-p', 'FY26', 100),
          bl('bb', 'a-p', 'FY26', 100, src: 'b'),
          bl('bc', 'c-p', 'FY26', 999, src: 'c'),
        ],
        snapshots: const [],
        forecastLines: const [],
        actuals: const [],
        merges: const [],
      );
      expect(f.currency, 'AUD');
      final c = f.projects.firstWhere((r) => r.sourceId == 'c');
      expect(c.currencyMismatch, isTrue);
      expect(f.budgetMinor, 200);
      expect(f.categories.single.budgetMinor, 200);
    });

    test('empty when nothing has cascaded', () {
      final f = computeProgrammeFinance(
          categories: const [], budgets: const [], budgetLines: const [],
          snapshots: const [], forecastLines: const [], actuals: const [],
          merges: const []);
      expect(f.isEmpty, isTrue);
      expect(f.varianceBp, isNull);
    });
  });
}
