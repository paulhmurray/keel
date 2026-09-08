/// Date-precision helpers for the Gantt. Activities plan month-by-month;
/// when an activity also carries real [startDate]/[endDate] ISO strings,
/// its bar renders day-accurate inside the month grid. These are pure
/// functions so the maths stays testable away from the widgets.
library;

/// Month index of [date] relative to [month0] (the header's month-0
/// anchor). August is index 2 when month0 is June, regardless of day.
int monthIndexOf(DateTime date, DateTime month0) =>
    (date.year - month0.year) * 12 + date.month - month0.month;

/// Fractional month position of [date] relative to [month0]:
/// whole month index plus day-progress within the month. 15 June (30-day
/// month, month0 June) → ≈0.467.
double monthFractionOf(DateTime date, DateTime month0) {
  final idx = monthIndexOf(date, month0);
  final daysInMonth = DateTime(date.year, date.month + 1, 0).day;
  return idx + (date.day - 1) / daysInMonth;
}

/// Derives the month span for a dated activity — what keeps the month
/// pickers and every month-based consumer in sync with the dates.
/// Resolves the month span to persist from the PM's month dropdowns and
/// the optional real dates. Dates are the source of truth ONLY for the
/// ends they actually cover: a start date pins the start month, but the
/// end month follows dates only when an end date exists — a start-only
/// date must never pin the end (that silently snapped every span edit
/// back to one month).
({int? startMonth, int? endMonth}) resolveMonthSpan({
  required bool isSinglePoint,
  required int? pickedStartMonth,
  required int? pickedEndMonth,
  required String? startDate,
  required String? endDate,
  required String? month0Date,
}) {
  final derived = monthSpanForDates(
    startDate: startDate,
    endDate: isSinglePoint ? startDate : endDate,
    month0Date: month0Date,
  );
  final start = derived?.startMonth ?? pickedStartMonth;
  if (isSinglePoint) return (startMonth: start, endMonth: start);
  if (derived != null && endDate != null) {
    return (startMonth: start, endMonth: derived.endMonth);
  }
  // Keep the span valid if a dated start moved past the picked end.
  if (pickedEndMonth != null && start != null && pickedEndMonth < start) {
    return (startMonth: start, endMonth: start);
  }
  return (startMonth: start, endMonth: pickedEndMonth);
}

({int startMonth, int endMonth})? monthSpanForDates({
  required String? startDate,
  required String? endDate,
  required String? month0Date,
}) {
  if (startDate == null || month0Date == null) return null;
  final m0 = DateTime.tryParse(month0Date);
  final s = DateTime.tryParse(startDate);
  if (m0 == null || s == null) return null;
  final e = endDate != null ? DateTime.tryParse(endDate) ?? s : s;
  return (
    startMonth: monthIndexOf(s, m0),
    endMonth: monthIndexOf(e, m0),
  );
}

/// Pixel insets for one Gantt column so a dated bar starts/ends at the
/// right day within it. [colStart]/[colEnd] are the column's inclusive
/// month range (quarter mode spans several months), [colWidth] its
/// rendered width. Returns zero insets for undated activities.
({double left, double right}) dateInsetsForCell({
  required String? startDate,
  required String? endDate,
  required String? month0Date,
  required int colStart,
  required int colEnd,
  required double colWidth,
}) {
  const none = (left: 0.0, right: 0.0);
  if (startDate == null || month0Date == null) return none;
  final m0 = DateTime.tryParse(month0Date);
  final s = DateTime.tryParse(startDate);
  if (m0 == null || s == null) return none;
  final e = endDate != null ? DateTime.tryParse(endDate) ?? s : s;

  final colStartF = colStart.toDouble();
  final colEndF = colEnd + 1.0; // exclusive right edge
  final span = colEndF - colStartF;

  final startF = monthFractionOf(s, m0);
  // End is inclusive: a task ending 15 Sep occupies through the 15th.
  final endDay = DateTime(e.year, e.month + 1, 0).day;
  final endF = monthIndexOf(e, m0) + e.day / endDay;

  var left = ((startF - colStartF) / span).clamp(0.0, 1.0) * colWidth;
  var right = ((colEndF - endF) / span).clamp(0.0, 1.0) * colWidth;
  // Degenerate guard: keep at least a sliver visible.
  if (colWidth - left - right < 2) {
    if (left > colWidth - 2) left = colWidth - 2;
    right = (colWidth - left - 2).clamp(0.0, colWidth);
  }
  return (left: left, right: right);
}
