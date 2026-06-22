/// Pure date math for the calendar drag interactions. Lifted into its
/// own file so it can be unit-tested without spinning up the widget tree.
///
/// All dates are pure-day [DateTime] values (no time-of-day). Pixel
/// deltas are snapped to whole days by rounding `delta / dayWidth`.

import 'dart:math' show max, min;

class CalendarDragMath {
  /// Snap a pixel delta to a whole number of days at [dayWidth] px each.
  static int snapToDays(double pixelDelta, double dayWidth) {
    if (dayWidth <= 0) return 0;
    return (pixelDelta / dayWidth).round();
  }

  /// Shift both endpoints by [days]. Length is preserved exactly.
  static ({DateTime start, DateTime end}) shift(
    DateTime start,
    DateTime end,
    int days,
  ) {
    return (
      start: start.add(Duration(days: days)),
      end: end.add(Duration(days: days)),
    );
  }

  /// Move the start by [days]. Clamped so it never crosses the end —
  /// in that case the new start equals the end (single-day span).
  static DateTime resizeStart(DateTime start, DateTime end, int days) {
    final candidate = start.add(Duration(days: days));
    return _earlier(candidate, end);
  }

  /// Move the end by [days]. Clamped so it never crosses the start —
  /// in that case the new end equals the start (single-day span).
  static DateTime resizeEnd(DateTime start, DateTime end, int days) {
    final candidate = end.add(Duration(days: days));
    return _later(candidate, start);
  }

  static DateTime _earlier(DateTime a, DateTime b) =>
      a.isAfter(b) ? b : a;
  static DateTime _later(DateTime a, DateTime b) =>
      a.isBefore(b) ? b : a;

  /// Convenience: convert a DateTime to its ISO YYYY-MM-DD prefix.
  static String iso(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  /// Minimum span between two dates (always non-negative).
  static int spanDays(DateTime a, DateTime b) =>
      (max(a.millisecondsSinceEpoch, b.millisecondsSinceEpoch) -
              min(a.millisecondsSinceEpoch, b.millisecondsSinceEpoch)) ~/
          Duration.millisecondsPerDay +
      1;

  /// Default effort when an undated card is dropped on the calendar
  /// without an estimate of its own — one week.
  static const int defaultEffortDays = 7;

  /// Build the start/end pair for a sidebar-drop, given the day the user
  /// dropped on and the card's [effortDays] estimate. A null or
  /// non-positive estimate falls back to [defaultEffortDays].
  /// The range is inclusive: effort N → end = start + (N − 1) days.
  static ({DateTime start, DateTime end}) spanFromDrop(
    DateTime dropDay,
    int? effortDays,
  ) {
    final n =
        (effortDays != null && effortDays > 0) ? effortDays : defaultEffortDays;
    return (start: dropDay, end: dropDay.add(Duration(days: n - 1)));
  }

  /// Pixel offset → day-index from the grid's left edge, snapped to the
  /// nearest whole day. Used to find the drop day for a sidebar→grid
  /// drag at [localXFromGridLeft] pixels into the grid.
  static int dayIndexFromOffset(double localXFromGridLeft, double dayWidth) {
    if (dayWidth <= 0) return 0;
    final i = (localXFromGridLeft / dayWidth).floor();
    return i < 0 ? 0 : i;
  }
}
