/// Pure helpers relating a RAID dependency to the plan activity it gates.
///
/// A dependency becomes a *timeline* dependency once it points at a plan
/// activity: inbound ("we need X from them") must land before that
/// activity starts; outbound ("they need Y from us") must be produced
/// by the time the activity ends. The slack between the two dates is
/// what tells the PM whether the dependency is a paperwork item or a
/// schedule threat. Kept free of Flutter so it's unit-testable.
library;

enum SlackSeverity { ok, tight, late }

/// Which end of the activity the dependency is measured against.
enum SlackAnchor { activityStart, activityEnd }

class DependencySlack {
  /// The dependency's needed-by date.
  final DateTime neededBy;

  /// The activity date the dependency is measured against.
  final DateTime activityDate;

  final SlackAnchor anchor;

  /// Days between the two. Positive = the dependency lands with room to
  /// spare; negative = it lands after the activity needs it.
  final int days;

  /// True when the activity date was derived from a month index rather
  /// than a real date — the comparison is month-accurate, not day-accurate.
  final bool activityDateIsEstimate;

  const DependencySlack({
    required this.neededBy,
    required this.activityDate,
    required this.anchor,
    required this.days,
    required this.activityDateIsEstimate,
  });

  SlackSeverity get severity {
    if (days < 0) return SlackSeverity.late;
    if (days <= kTightSlackDays) return SlackSeverity.tight;
    return SlackSeverity.ok;
  }

  /// Human summary for chips and dialogs.
  String get label {
    final anchorWord =
        anchor == SlackAnchor.activityStart ? 'starts' : 'ends';
    final approx = activityDateIsEstimate ? '≈' : '';
    if (days == 0) return 'Due the day the activity $anchorWord';
    if (days > 0) {
      return '$approx$days day${days == 1 ? '' : 's'} slack before the '
          'activity $anchorWord';
    }
    final late = -days;
    return '$approx$late day${late == 1 ? '' : 's'} AFTER the activity '
        '$anchorWord';
  }
}

/// Slack under this many days is flagged as tight.
const int kTightSlackDays = 14;

/// Resolves the plan date a dependency is measured against.
///
/// Returns null when the activity carries neither a real date nor a
/// month index resolvable against [month0Date].
({DateTime date, bool isEstimate})? resolveActivityAnchorDate({
  required SlackAnchor anchor,
  required String? startDate,
  required String? endDate,
  required int? startMonth,
  required int? endMonth,
  required String? month0Date,
}) {
  final iso = anchor == SlackAnchor.activityStart ? startDate : endDate;
  final parsed = iso != null ? DateTime.tryParse(iso) : null;
  if (parsed != null) return (date: _utcDay(parsed), isEstimate: false);

  final month = anchor == SlackAnchor.activityStart ? startMonth : endMonth;
  final m0 = month0Date != null ? DateTime.tryParse(month0Date) : null;
  if (month == null || m0 == null) return null;
  // Month-only precision: treat "starts in M3" as the 1st of that month
  // and "ends in M5" as the last day of that month.
  if (anchor == SlackAnchor.activityStart) {
    return (
      date: DateTime.utc(m0.year, m0.month + month, 1),
      isEstimate: true
    );
  }
  return (
    date: DateTime.utc(m0.year, m0.month + month + 1, 0),
    isEstimate: true
  );
}

/// Calendar day as a UTC midnight — all slack maths runs in UTC so a
/// DST-shortened local day can't shave a day off the difference.
DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Which end of the activity a dependency of [dependencyType] gates.
/// Inbound and bilateral must land before the activity can start;
/// outbound is something we hand over when the activity finishes.
SlackAnchor anchorForDependencyType(String dependencyType) =>
    dependencyType == 'outbound'
        ? SlackAnchor.activityEnd
        : SlackAnchor.activityStart;

/// Computes the slack between a dependency's [dueDate] and the plan
/// activity it points at. Null when either side is undated.
DependencySlack? dependencySlack({
  required String? dueDate,
  required String dependencyType,
  required String? activityStartDate,
  required String? activityEndDate,
  required int? activityStartMonth,
  required int? activityEndMonth,
  required String? month0Date,
}) {
  final needed = dueDate != null ? DateTime.tryParse(dueDate) : null;
  if (needed == null) return null;
  final anchor = anchorForDependencyType(dependencyType);
  final resolved = resolveActivityAnchorDate(
    anchor: anchor,
    startDate: activityStartDate,
    endDate: activityEndDate,
    startMonth: activityStartMonth,
    endMonth: activityEndMonth,
    month0Date: month0Date,
  );
  if (resolved == null) return null;

  final neededDay = _utcDay(needed);
  final actDay = resolved.date;
  // Inbound: room = activity start − needed-by (dependency lands first).
  // Outbound: room = needed-by − activity end (we finish first).
  final days = anchor == SlackAnchor.activityStart
      ? actDay.difference(neededDay).inDays
      : neededDay.difference(actDay).inDays;

  return DependencySlack(
    neededBy: neededDay,
    activityDate: actDay,
    anchor: anchor,
    days: days,
    activityDateIsEstimate: resolved.isEstimate,
  );
}
