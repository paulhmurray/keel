/// Pure helpers for cascading plan detail (activities, tasks, arrows)
/// from a project onto a programme's timeline. Kept free of Drift so
/// the re-keying rules are unit-testable on their own.
library;

/// How many months to add to every month column of a cascaded activity
/// so it lands in the right place on the programme's axis.
///
/// When the source sent the absolute date of its start month AND the
/// programme has a calendar anchor, the offset is the gap between where
/// the source put the activity and where that date falls for the
/// programme. Without both, the axes are assumed aligned (offset 0),
/// which is the relative M0..Mn case and matches the WP swimlane rule.
int cascadeMonthOffset({
  required int? rawStartMonth,
  required DateTime? startMonthDate,
  required DateTime? programmeAnchor,
}) {
  if (rawStartMonth == null || startMonthDate == null || programmeAnchor == null) {
    return 0;
  }
  final programmeIndex = (startMonthDate.year - programmeAnchor.year) * 12 +
      (startMonthDate.month - programmeAnchor.month);
  return programmeIndex - rawStartMonth;
}

const _kPlanLinkPrefixes = {
  'raid-dependency:': 'dependency',
  'raid-decision:': 'decision',
};

/// Re-keys a plan-link marker (`raid-dependency:<id>` / `raid-decision:<id>`)
/// onto the cascaded register row's synthetic id, so the programme's Gantt
/// can still resolve the arrow to its RAID item. Other notes pass through.
String? remapPlanLinkNote(String sourceEntityId, String? note) {
  if (note == null) return null;
  for (final e in _kPlanLinkPrefixes.entries) {
    if (note.startsWith(e.key)) {
      final id = note.substring(e.key.length);
      return '${e.key}cascade:${e.value}:$sourceEntityId:$id';
    }
  }
  return note;
}
