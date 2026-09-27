/// Programme finance roll-up over cascaded copies of linked projects'
/// finance rows. Pure: lists in, ints out. No Drift queries here so the
/// maths is unit-testable on its own.
library;

import '../database/database.dart';
import 'variance.dart';

/// Normalises a category name for grouping: trimmed, case-folded,
/// internal whitespace collapsed. "Software  Licences " == "software
/// licences".
String normaliseCategoryName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// One roll-up bucket: the display name, and every cascaded category id
/// that lands in it (across projects).
class CategoryBucket {
  final String name; // display (first-seen spelling, or the merge target)
  final List<String> categoryIds;
  const CategoryBucket({required this.name, required this.categoryIds});
}

/// Groups cascaded categories by normalised name, then applies merges:
/// a merged category leaves its own bucket and joins the target's. The
/// result is ordered by name. Every category lands somewhere, so
/// "unmapped" cannot exist.
List<CategoryBucket> rollupCategories(
    List<CostCategory> cascaded, List<CategoryMerge> merges) {
  final target = {for (final m in merges) m.sourceCategoryId: m.targetName};
  final display = <String, String>{}; // norm → display name
  final ids = <String, List<String>>{};
  for (final c in cascaded) {
    final name = target[c.id] ?? c.name;
    final key = normaliseCategoryName(name);
    display.putIfAbsent(key, () => name.trim());
    ids.putIfAbsent(key, () => []).add(c.id);
  }
  final keys = ids.keys.toList()
    ..sort((a, b) => display[a]!.toLowerCase().compareTo(display[b]!.toLowerCase()));
  return [
    for (final k in keys) CategoryBucket(name: display[k]!, categoryIds: ids[k]!),
  ];
}

/// One linked project's finance position as the programme sees it.
class ProjectFinanceRow {
  final String sourceId;
  final String? currency;
  final ProjectBudget? budget; // the cascaded approved budget
  final int budgetMinor;
  final ForecastSnapshot? latestSnapshot; // latest SUBMITTED
  final int? forecastMinor; // null when no snapshot
  final int actualsMinor;
  final int? varianceBp; // forecast vs budget, null when undefined
  final int toleranceBp;
  final bool breach;
  /// True when this project's currency differs from the portfolio's and
  /// it was left out of the totals.
  final bool currencyMismatch;

  const ProjectFinanceRow({
    required this.sourceId,
    required this.currency,
    required this.budget,
    required this.budgetMinor,
    required this.latestSnapshot,
    required this.forecastMinor,
    required this.actualsMinor,
    required this.varianceBp,
    required this.toleranceBp,
    required this.breach,
    required this.currencyMismatch,
  });

  int? get varianceMinor =>
      forecastMinor == null ? null : forecastMinor! - budgetMinor;
}

/// One roll-up bucket's totals across projects.
class CategoryFinanceRow {
  final String name;
  final int budgetMinor;
  final int forecastMinor;
  final int actualsMinor;
  final Map<String, int> budgetByFy;
  final Map<String, int> forecastByFy;
  const CategoryFinanceRow({
    required this.name,
    required this.budgetMinor,
    required this.forecastMinor,
    required this.actualsMinor,
    required this.budgetByFy,
    required this.forecastByFy,
  });
}

class ProgrammeFinance {
  final List<ProjectFinanceRow> projects; // one per source project
  final List<CategoryFinanceRow> categories;
  final String? currency; // the portfolio currency (most common)
  final int budgetMinor;
  final int forecastMinor; // sum of latest submitted FACs (budget where none)
  final int actualsMinor;
  final int? varianceBp;
  final List<String> financialYears; // sorted union
  const ProgrammeFinance({
    required this.projects,
    required this.categories,
    required this.currency,
    required this.budgetMinor,
    required this.forecastMinor,
    required this.actualsMinor,
    required this.varianceBp,
    required this.financialYears,
  });

  List<ProjectFinanceRow> get breaches =>
      projects.where((p) => p.breach).toList();

  bool get isEmpty => projects.isEmpty;
}

/// The whole roll-up. Inputs are the programme-side CASCADED rows (all
/// carry sourceProjectId) plus the programme's merges.
ProgrammeFinance computeProgrammeFinance({
  required List<CostCategory> categories,
  required List<ProjectBudget> budgets,
  required List<BudgetLine> budgetLines,
  required List<ForecastSnapshot> snapshots,
  required List<ForecastLine> forecastLines,
  required List<ActualLine> actuals,
  required List<CategoryMerge> merges,
}) {
  final sources = <String>{
    for (final b in budgets) if (b.sourceProjectId != null) b.sourceProjectId!,
    for (final s in snapshots) if (s.sourceProjectId != null) s.sourceProjectId!,
    for (final a in actuals) if (a.sourceProjectId != null) a.sourceProjectId!,
  }.toList()
    ..sort();

  // Portfolio currency: the most common among cascaded budgets.
  final currencyCounts = <String, int>{};
  for (final b in budgets) {
    currencyCounts[b.currency] = (currencyCounts[b.currency] ?? 0) + 1;
  }
  String? portfolioCurrency;
  var best = 0;
  for (final e in currencyCounts.entries) {
    if (e.value > best) {
      best = e.value;
      portfolioCurrency = e.key;
    }
  }

  final linesByBudget = <String, List<BudgetLine>>{};
  for (final l in budgetLines) {
    linesByBudget.putIfAbsent(l.budgetId, () => []).add(l);
  }
  final linesBySnapshot = <String, List<ForecastLine>>{};
  for (final l in forecastLines) {
    linesBySnapshot.putIfAbsent(l.snapshotId, () => []).add(l);
  }

  final rows = <ProjectFinanceRow>[];
  final latestSnapshotBySource = <String, ForecastSnapshot>{};
  for (final s in snapshots) {
    if (s.status != 'submitted' || s.sourceProjectId == null) continue;
    final cur = latestSnapshotBySource[s.sourceProjectId!];
    if (cur == null || s.period.compareTo(cur.period) > 0) {
      latestSnapshotBySource[s.sourceProjectId!] = s;
    }
  }

  var totalBudget = 0, totalForecast = 0, totalActuals = 0;
  for (final src in sources) {
    final budget = budgets
        .where((b) => b.sourceProjectId == src && b.status == 'approved')
        .firstOrNull;
    final budgetMinor = budget == null
        ? 0
        : BudgetTotals.fromLines(linesByBudget[budget.id] ?? const []).totalMinor;
    final snap = latestSnapshotBySource[src];
    final forecastMinor = snap == null
        ? null
        : BudgetTotals.fromForecastLines(linesBySnapshot[snap.id] ?? const [])
            .totalMinor;
    final actualsMinor = BudgetTotals.fromActualLines(
            actuals.where((a) => a.sourceProjectId == src).toList())
        .totalMinor;
    final bp = forecastMinor == null
        ? null
        : VarianceRow.bpOf(forecastMinor - budgetMinor, budgetMinor);
    final tol = budget?.varianceToleranceBp ?? 500;
    final currency = budget?.currency;
    final mismatch = currency != null &&
        portfolioCurrency != null &&
        currency != portfolioCurrency;
    rows.add(ProjectFinanceRow(
      sourceId: src,
      currency: currency,
      budget: budget,
      budgetMinor: budgetMinor,
      latestSnapshot: snap,
      forecastMinor: forecastMinor,
      actualsMinor: actualsMinor,
      varianceBp: bp,
      toleranceBp: tol,
      breach: bp != null && bp.abs() > tol,
      currencyMismatch: mismatch,
    ));
    if (!mismatch) {
      totalBudget += budgetMinor;
      totalForecast += forecastMinor ?? budgetMinor;
      totalActuals += actualsMinor;
    }
  }

  // By category, over the same non-mismatched projects.
  final included = {
    for (final r in rows)
      if (!r.currencyMismatch) r.sourceId,
  };
  final buckets = rollupCategories(categories, merges);
  final bucketOf = <String, int>{};
  for (var i = 0; i < buckets.length; i++) {
    for (final id in buckets[i].categoryIds) {
      bucketOf[id] = i;
    }
  }
  final catBudget = List<int>.filled(buckets.length, 0);
  final catForecast = List<int>.filled(buckets.length, 0);
  final catActuals = List<int>.filled(buckets.length, 0);
  final catBudgetFy = List.generate(buckets.length, (_) => <String, int>{});
  final catForecastFy = List.generate(buckets.length, (_) => <String, int>{});
  final fys = <String>{};
  final approvedIds = {
    for (final r in rows)
      if (r.budget != null && included.contains(r.sourceId)) r.budget!.id,
  };
  final latestIds = {
    for (final r in rows)
      if (r.latestSnapshot != null && included.contains(r.sourceId))
        r.latestSnapshot!.id,
  };
  for (final l in budgetLines) {
    if (!approvedIds.contains(l.budgetId)) continue;
    final i = bucketOf[l.costCategoryId];
    if (i == null) continue;
    catBudget[i] += l.amountMinor;
    catBudgetFy[i][l.financialYear] =
        (catBudgetFy[i][l.financialYear] ?? 0) + l.amountMinor;
    fys.add(l.financialYear);
  }
  for (final l in forecastLines) {
    if (!latestIds.contains(l.snapshotId)) continue;
    final i = bucketOf[l.costCategoryId];
    if (i == null) continue;
    catForecast[i] += l.amountMinor;
    catForecastFy[i][l.financialYear] =
        (catForecastFy[i][l.financialYear] ?? 0) + l.amountMinor;
    fys.add(l.financialYear);
  }
  for (final a in actuals) {
    if (a.sourceProjectId == null || !included.contains(a.sourceProjectId)) {
      continue;
    }
    final i = bucketOf[a.costCategoryId];
    if (i == null) continue;
    catActuals[i] += a.amountMinor;
  }

  return ProgrammeFinance(
    projects: rows,
    categories: [
      for (var i = 0; i < buckets.length; i++)
        CategoryFinanceRow(
          name: buckets[i].name,
          budgetMinor: catBudget[i],
          forecastMinor: catForecast[i],
          actualsMinor: catActuals[i],
          budgetByFy: catBudgetFy[i],
          forecastByFy: catForecastFy[i],
        ),
    ],
    currency: portfolioCurrency,
    budgetMinor: totalBudget,
    forecastMinor: totalForecast,
    actualsMinor: totalActuals,
    varianceBp: VarianceRow.bpOf(totalForecast - totalBudget, totalBudget),
    financialYears: fys.toList()..sort(),
  );
}
