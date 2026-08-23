import '../database/database.dart';

/// Budget-vs-forecast variance, computed entirely in integer maths.
///
/// Rounding rule (documented per the finance design principles):
/// variance percentage is expressed in basis points (1 bp = 0.01%),
/// computed as round-half-away-from-zero of `variance × 10000 / budget`.
/// This matches Excel's ROUND() on the same expression. Undefined
/// (null) when the budget side is zero or negative.
class VarianceRow {
  /// Cost category id, or [totalKey] for the grand-total row.
  final String key;
  final int budgetMinor;
  final int forecastMinor;

  static const totalKey = '__total__';

  const VarianceRow({
    required this.key,
    required this.budgetMinor,
    required this.forecastMinor,
  });

  int get varianceMinor => forecastMinor - budgetMinor;

  int? get varianceBp => bpOf(varianceMinor, budgetMinor);

  /// Basis points of [part] relative to [whole], rounded half away from
  /// zero. Null when [whole] <= 0 (percentage undefined).
  static int? bpOf(int part, int whole) {
    if (whole <= 0) return null;
    final n = part.abs() * 10000;
    final rounded = (2 * n + whole) ~/ (2 * whole);
    return part < 0 ? -rounded : rounded;
  }
}

/// Per-category budget vs forecast rows (union of both sides' category
/// keys), ordered by [categoryOrder], followed by the grand-total row.
List<VarianceRow> computeVariance(
  BudgetTotals budget,
  BudgetTotals forecast,
  List<String> categoryOrder,
) {
  final keys = <String>[
    for (final id in categoryOrder)
      if (budget.byCategoryId.containsKey(id) ||
          forecast.byCategoryId.containsKey(id))
        id,
  ];
  // Categories present in the data but missing from the order list
  // (defensive — e.g. deleted-then-reimported) go at the end.
  for (final id in {...budget.byCategoryId.keys, ...forecast.byCategoryId.keys}) {
    if (!keys.contains(id)) keys.add(id);
  }
  return [
    for (final id in keys)
      VarianceRow(
        key: id,
        budgetMinor: budget.byCategoryId[id] ?? 0,
        forecastMinor: forecast.byCategoryId[id] ?? 0,
      ),
    VarianceRow(
      key: VarianceRow.totalKey,
      budgetMinor: budget.totalMinor,
      forecastMinor: forecast.totalMinor,
    ),
  ];
}
