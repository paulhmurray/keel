/// Pure logic for Cal Newport-style revision columns.
///
/// A day plan holds one or more revision columns. Revision 0 governs from
/// the start of the day; each later revision r governs from its recorded
/// start minute until the next revision's start (or end of day). A block
/// is part of the EFFECTIVE schedule when its own revision is the one
/// governing its start minute — older-column blocks past a revision point
/// are the superseded (struck-through) record, and a block already in
/// progress when a revision starts stays governed by its old column.
library;

import 'dart:convert';

import '../database/database.dart';

/// Decodes [DayPlan.revisionStartsJson]. Index r-1 holds the minute at
/// which revision r takes over; revision 0 has no entry.
List<int> parseRevisionStarts(String json) {
  try {
    return (jsonDecode(json) as List).cast<int>();
  } catch (_) {
    return const [];
  }
}

/// The revision governing [minute]: the highest revision whose start is
/// at or before [minute].
int governingRevisionAt(int minute, List<int> revisionStarts) {
  var governing = 0;
  for (var r = 0; r < revisionStarts.length; r++) {
    if (revisionStarts[r] <= minute) governing = r + 1;
  }
  return governing;
}

/// True when [block] has been superseded by a later revision — it sits at
/// or after a revision point but belongs to an older column.
bool isBlockSuperseded(DayPlanBlock block, List<int> revisionStarts) {
  return block.revision <
      governingRevisionAt(block.startMinute, revisionStarts);
}

/// The effective schedule for the day: every block whose own revision
/// governs its start minute, sorted by start time.
List<DayPlanBlock> effectiveSchedule(
    List<DayPlanBlock> blocks, List<int> revisionStarts) {
  final active = blocks
      .where((b) => !isBlockSuperseded(b, revisionStarts))
      .toList()
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  return active;
}

/// The effective block covering [minute], or null when the time is free.
DayPlanBlock? blockAt(
    List<DayPlanBlock> blocks, List<int> revisionStarts, int minute) {
  for (final b in effectiveSchedule(blocks, revisionStarts)) {
    if (b.startMinute <= minute && minute < b.endMinute) return b;
  }
  return null;
}

/// Effective blocks starting after [minute], soonest first.
List<DayPlanBlock> blocksAfter(
    List<DayPlanBlock> blocks, List<int> revisionStarts, int minute) {
  return effectiveSchedule(blocks, revisionStarts)
      .where((b) => b.startMinute > minute)
      .toList();
}

/// The home block the user must not miss: one covering [minute] right
/// now, or the next one starting within [withinMinutes]. Done blocks are
/// skipped — the pickup already happened. Null when nothing is imminent.
DayPlanBlock? imminentHomeBlock(
  List<DayPlanBlock> blocks,
  List<int> revisionStarts,
  int minute, {
  int withinMinutes = 60,
}) {
  final current = blockAt(blocks, revisionStarts, minute);
  if (current != null && current.kind == 'home' && !current.done) {
    return current;
  }
  for (final b in blocksAfter(blocks, revisionStarts, minute)) {
    if (b.kind != 'home' || b.done) continue;
    return b.startMinute - minute <= withinMinutes ? b : null;
  }
  return null;
}

/// Formats minutes-from-midnight as HH:MM.
String formatMinute(int minute) {
  final h = minute ~/ 60;
  final m = minute % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

// ── Week helpers (weeks start Monday) ──────────────────────────────────

/// The Monday of [d]'s week, at midnight (date-only).
DateTime mondayOf(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

/// Decodes [WeekPlan.dayMissionsJson] into weekday-index → mission
/// (0 = Monday … 6 = Sunday).
Map<int, String> parseDayMissions(String json) {
  try {
    final raw = jsonDecode(json) as Map<String, dynamic>;
    return {
      for (final e in raw.entries)
        if (int.tryParse(e.key) != null) int.parse(e.key): '${e.value}',
    };
  } catch (_) {
    return const {};
  }
}

/// Done blocks carrying [objectiveId], counted over a week of blocks —
/// only blocks in each day's EFFECTIVE schedule count (a superseded copy
/// of a done block must not double-count).
int objectiveDoneBlocks(
  String objectiveId,
  List<DayPlanBlock> weekBlocks,
  Map<String, List<int>> revisionStartsByPlanId,
) {
  var count = 0;
  for (final b in weekBlocks) {
    if (b.objectiveId != objectiveId || !b.done) continue;
    final starts = revisionStartsByPlanId[b.dayPlanId] ?? const [];
    if (!isBlockSuperseded(b, starts)) count++;
  }
  return count;
}

// ── Quarter helpers (anchor-month aware) ───────────────────────────────

/// The first day of [d]'s quarter, given the configured [anchorMonth]
/// (1 = January → calendar quarters, 7 = July → Australian FY quarters).
DateTime quarterStartOf(DateTime d, int anchorMonth) {
  // Months since the anchor, normalised to [0, 11], snapped to a
  // quarter boundary.
  final monthsSinceAnchor = (d.month - anchorMonth + 12) % 12;
  final quarterOffset = monthsSinceAnchor - (monthsSinceAnchor % 3);
  var month = anchorMonth + quarterOffset;
  var year = d.year;
  if (d.month < anchorMonth) year -= 1;
  if (month > 12) {
    month -= 12;
    year += 1;
  }
  return DateTime(year, month, 1);
}

/// Human label for a quarter starting at [start] under [anchorMonth].
/// Calendar anchor: "Q3 2026". Any other anchor: FY style — a July
/// anchor makes Jul–Sep 2026 read "Q1 FY27 · Jul–Sep 2026".
String quarterLabel(DateTime start, int anchorMonth) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final end = DateTime(start.year, start.month + 2, 1);
  final range =
      '${months[start.month - 1]}–${months[end.month - 1]} ${end.year}';
  final monthsSinceAnchor = (start.month - anchorMonth + 12) % 12;
  final qNum = monthsSinceAnchor ~/ 3 + 1;
  if (anchorMonth == 1) {
    return 'Q$qNum ${start.year}';
  }
  // FY is named for the year it ENDS in (AU convention): FY27 spans
  // Jul 2026 – Jun 2027.
  final fyEndYear =
      (start.month >= anchorMonth ? start.year + 1 : start.year) % 100;
  return 'Q$qNum FY$fyEndYear · $range';
}

/// Whether a weekly objective counts as met: manually ticked, or its
/// block target reached.
bool objectiveMet(
  WeekPlanObjective o,
  List<DayPlanBlock> blocks,
  Map<String, List<int>> revisionStartsByPlanId,
) {
  if (o.done) return true;
  final target = o.targetBlocks;
  if (target == null) return false;
  return objectiveDoneBlocks(o.id, blocks, revisionStartsByPlanId) >=
      target;
}

/// Met weekly objectives carrying [goalId] — the quarter layer's
/// progress metric. [metByObjectiveId] carries each objective's met
/// state (computed with [objectiveMet] where block data is available,
/// or `o.done` alone as the cheap approximation).
int goalMetObjectives(
  String goalId,
  List<WeekPlanObjective> objectives,
  bool Function(WeekPlanObjective) isMet,
) {
  return objectives
      .where((o) => o.goalId == goalId && isMet(o))
      .length;
}
