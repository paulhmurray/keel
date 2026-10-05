/// Schedule scenarios: A — Anchor, B — Likely, C — Safe.
///
/// A milestone or gate is a point in time, so its anchor is its month
/// and B/C are alternative months for the same event. An activity or a
/// dependency marker runs over a window, so its anchor is its END month
/// and B/C are alternative finishes: the Gantt draws them as ghosts
/// beyond the bar. A hard deadline is precisely a date with no
/// variants, so it never carries scenarios. One rule for the form, the
/// painter and the workbook export.
library;

import '../database/database.dart';

const Set<String> kScenarioTypes = {
  'milestone',
  'gate',
  'dependency_marker',
  'activity',
};

bool scenariosApplyTo(String activityType) =>
    kScenarioTypes.contains(activityType);

/// Milestones and gates anchor on their month. Activities and dependency
/// markers can span months, so they anchor on their end: B and C are
/// alternative finishes (for a marker, alternative landing dates).
bool scenarioAnchorsOnEnd(String activityType) =>
    activityType == 'activity' || activityType == 'dependency_marker';

/// The month the B/C spread is measured from, or null when unscheduled.
int? scenarioAnchorMonth(TimelineActivity a) {
  if (!scenariosApplyTo(a.activityType)) return null;
  if (scenarioAnchorsOnEnd(a.activityType)) return a.endMonth ?? a.startMonth;
  return a.startMonth;
}

/// Labels for the two optional pickers.
({String likely, String safe}) scenarioLabels(String activityType) =>
    scenarioAnchorsOnEnd(activityType)
        ? (likely: 'B — Likely end (optional)', safe: 'C — Safe end (optional)')
        : (likely: 'B — Likely (optional)', safe: 'C — Safe (optional)');

/// The whole spread, anchor included, as an inclusive month range; null
/// when there is no anchor or no scenario set.
({int lo, int hi})? scenarioRange(TimelineActivity a) {
  final anchor = scenarioAnchorMonth(a);
  if (anchor == null || (a.likelyMonth == null && a.safeMonth == null)) {
    return null;
  }
  var lo = anchor, hi = anchor;
  for (final m in [a.likelyMonth, a.safeMonth]) {
    if (m == null) continue;
    if (m < lo) lo = m;
    if (m > hi) hi = m;
  }
  return (lo: lo, hi: hi);
}

/// For an activity a scenario finish before the planned finish would be
/// hidden under the bar, so the pickers only offer months from the end
/// onward. Points may vary either way.
bool scenarioMonthAllowed(String activityType, int month, int? anchor) {
  if (!scenarioAnchorsOnEnd(activityType) || anchor == null) return true;
  return month >= anchor;
}
