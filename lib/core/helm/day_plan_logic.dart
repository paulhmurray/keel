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
