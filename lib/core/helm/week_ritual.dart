/// The weekly planning ritual's arithmetic: which days a rock is
/// allocated to, how much focus a day can take once its meetings are
/// in, what last week's objectives actually got, what the morning
/// ritual should pre-place, and when the day view should nudge. Pure
/// Dart so the rules are unit-tested once and shared by the ritual
/// dialog, the week readout and the day view.
///
/// Units: everything is in 30-minute SLOTS ([kPlanSlotMinutes]), the
/// same unit as objective targets and done blocks, so an allocation and
/// its progress compare directly.
library;

import 'dart:convert';

import '../database/database.dart';
import 'day_plan_logic.dart';

// ─── Allocations ─────────────────────────────────────────────────────────

/// Decodes [WeekPlanObjective.dayAllocationsJson] into weekday index
/// (0 = Monday … 6 = Sunday) → slots. Zero and malformed entries drop.
Map<int, int> parseDayAllocations(String? json) {
  if (json == null || json.isEmpty) return const {};
  try {
    final raw = jsonDecode(json) as Map<String, dynamic>;
    final out = <int, int>{};
    for (final e in raw.entries) {
      final day = int.tryParse(e.key);
      final v = e.value;
      final slots = v is num ? v.toInt() : int.tryParse('$v');
      if (day == null || day < 0 || day > 6) continue;
      if (slots == null || slots <= 0) continue;
      out[day] = slots;
    }
    return out;
  } catch (_) {
    return const {};
  }
}

String encodeDayAllocations(Map<int, int> allocations) => jsonEncode({
      for (final e in allocations.entries)
        if (e.value > 0 && e.key >= 0 && e.key <= 6) '${e.key}': e.value,
    });

/// Total slots an objective is allocated across the week.
int allocatedSlots(Map<int, int> allocations) =>
    allocations.values.fold(0, (a, b) => a + b);

/// Slots allocated to [weekday] across all objectives.
int dayLoad(Iterable<Map<int, int>> allocations, int weekday) =>
    allocations.fold(0, (sum, a) => sum + (a[weekday] ?? 0));

// ─── Capacity ────────────────────────────────────────────────────────────

/// Meeting time already on a day's EFFECTIVE schedule, in slots.
int meetingSlots(List<DayPlanBlock> blocks, List<int> revisionStarts) {
  var minutes = 0;
  for (final b in effectiveSchedule(blocks, revisionStarts)) {
    if (b.kind == 'meeting') minutes += b.endMinute - b.startMinute;
  }
  return (minutes + kPlanSlotMinutes - 1) ~/ kPlanSlotMinutes;
}

/// Focus slots a day can still take: the configured capacity less its
/// meetings, never below zero.
int dayCapacity({required int focusSlotsPerDay, required int meetingSlots}) {
  final c = focusSlotsPerDay - meetingSlots;
  return c < 0 ? 0 : c;
}

bool overcommitted({required int load, required int capacity}) =>
    load > capacity;

// ─── Missions ────────────────────────────────────────────────────────────

/// A mission line drafted from the day's allocations, biggest first:
/// "Build adapter · Status pack". Null when nothing is allocated. Never
/// used to overwrite a mission the user typed.
String? draftDayMission(
    List<({String label, Map<int, int> allocations})> rocks, int weekday) {
  final on = rocks
      .where((r) => (r.allocations[weekday] ?? 0) > 0)
      .toList()
    ..sort((a, b) =>
        (b.allocations[weekday] ?? 0).compareTo(a.allocations[weekday] ?? 0));
  if (on.isEmpty) return null;
  return on.map((r) => r.label.trim()).join(' · ');
}

// ─── Last week ───────────────────────────────────────────────────────────

class ReviewRow {
  final WeekPlanObjective objective;
  final int doneSlots;
  final int? target;
  final bool met;
  const ReviewRow({
    required this.objective,
    required this.doneSlots,
    required this.target,
    required this.met,
  });
}

/// Last week's objectives with what they actually got.
List<ReviewRow> reviewRows(
  List<WeekPlanObjective> objectives,
  List<DayPlanBlock> weekBlocks,
  Map<String, List<int>> revisionStartsByPlanId,
) =>
    [
      for (final o in objectives)
        ReviewRow(
          objective: o,
          doneSlots: objectiveDoneBlocks(o.id, weekBlocks, revisionStartsByPlanId),
          target: o.targetBlocks,
          met: objectiveMet(o, weekBlocks, revisionStartsByPlanId),
        ),
    ];

// ─── Morning prefill ─────────────────────────────────────────────────────

class PrefillBlock {
  final int startMinute;
  final int endMinute;
  final String label;
  final String? objectiveId;
  final String? projectId;
  final String? linkedActionId;
  const PrefillBlock({
    required this.startMinute,
    required this.endMinute,
    required this.label,
    this.objectiveId,
    this.projectId,
    this.linkedActionId,
  });
}

/// One focus block per objective allocated to [weekday], each slots × 30
/// minutes, placed in order from [dayStart] into the first free gap
/// that holds it, never overlapping [existing]. Anything that can't fit
/// before [dayEnd] is appended after the last block so nothing is lost.
List<PrefillBlock> prefillBlocks({
  required List<WeekPlanObjective> objectives,
  required int weekday,
  required int dayStart,
  required int dayEnd,
  List<({int startMinute, int endMinute})> existing = const [],
}) {
  final busy = [...existing]
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  final out = <PrefillBlock>[];
  var cursor = dayStart;
  final rocks = [
    for (final o in objectives)
      if (!o.done && (parseDayAllocations(o.dayAllocationsJson)[weekday] ?? 0) > 0)
        (o: o, slots: parseDayAllocations(o.dayAllocationsJson)[weekday]!),
  ]..sort((a, b) => b.slots.compareTo(a.slots));

  for (final r in rocks) {
    final length = r.slots * kPlanSlotMinutes;
    var start = cursor;
    // Walk forward past anything already occupying the slot.
    var placed = false;
    while (start + length <= dayEnd) {
      final clash = busy.where((b) => b.startMinute < start + length && b.endMinute > start).toList();
      if (clash.isEmpty) {
        placed = true;
        break;
      }
      start = clash.map((b) => b.endMinute).reduce((a, b) => a > b ? a : b);
    }
    if (!placed) {
      // Append after whatever is last on the day.
      final lastEnd = [
        dayStart,
        for (final b in busy) b.endMinute,
        for (final p in out) p.endMinute,
      ].reduce((a, b) => a > b ? a : b);
      start = lastEnd;
    }
    final end = start + length;
    out.add(PrefillBlock(
      startMinute: start,
      endMinute: end,
      label: r.o.label,
      objectiveId: r.o.id,
      projectId: r.o.projectId,
      linkedActionId: r.o.linkedActionId,
    ));
    busy.add((startMinute: start, endMinute: end));
    busy.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    cursor = end;
  }
  return out;
}

// ─── Nudges ──────────────────────────────────────────────────────────────

/// The current week has no charted plan: no plan row, or one that was
/// never charted and holds no rocks.
bool weekNeedsCharting(WeekPlan? plan, List<WeekPlanObjective> objectives) =>
    plan == null || (plan.chartedAt == null && objectives.isEmpty);

/// It is Friday or later, the week had rocks, and no review was done.
bool weekNeedsReview(
    WeekPlan? plan, List<WeekPlanObjective> objectives, DateTime today) =>
    plan != null &&
    today.weekday >= DateTime.friday &&
    objectives.isNotEmpty &&
    plan.reviewedAt == null;

/// Soft ceiling on big rocks; above it the ritual nudges, never blocks.
const int kBigRockSoftCap = 5;
