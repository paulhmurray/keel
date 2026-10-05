/// Re-plan: slide not-started work whose start has passed forward to
/// today, push the consequences through the dependency graph, and say
/// why each row moved. Pure Dart — the arithmetic half of the Plan's
/// re-plan feature. The AI half (duration judgement, sub-tasks,
/// narrative) sits on top of this proposal and never does date maths.
///
/// Rules:
/// - Only `not_started`, non-cascaded rows ever move. Started (green,
///   amber, red) and complete rows are commitments; a violated
///   constraint on one becomes a warning naming both rows.
/// - A row is *slipped* when its start is before today: by date when it
///   carries one, else by month against the header's month-0 anchor.
///   The current month is not slipped.
/// - Slipped rows move to today (date or month), then forward again as
///   far as their predecessors demand. Duration is preserved in the unit
///   the row carries; a dated row keeps its months in step via
///   [monthSpanForDates].
/// - Constraints follow the Gantt's own vocabulary. finish_to_start:
///   start at or after the predecessor's end (same month allowed at
///   month precision, one day later at day precision). start_to_start:
///   start at or after the predecessor's start. finish_to_finish: end at
///   or after the predecessor's end, start follows to keep duration.
///   External rows have no plan predecessor, so no constraint, but the
///   label is surfaced in the reasons.
/// - Parent spans are commitments: a parent that qualifies moves; its
///   tasks are judged on their own merits. A task left outside a moved
///   parent is already highlighted by the Gantt.
/// - No month-0 anchor means no month arithmetic: zero changes and one
///   warning, never a guess.
library;

import '../database/database.dart';
import 'date_precision.dart'
    show monthIndexOf, monthSpanForDates;

/// One row's proposed move.
class ReplanChange {
  final TimelineActivity activity;
  final int? fromStartMonth;
  final int? fromEndMonth;
  final String? fromStartDate;
  final String? fromEndDate;
  final int? toStartMonth;
  final int? toEndMonth;
  final String? toStartDate;
  final String? toEndDate;

  /// True when the row's own start had passed; false when it only moved
  /// because a predecessor did.
  final bool slipped;

  /// Ids of predecessors whose move forced this one.
  final List<String> pushedBy;

  /// Plain-language reasons, in order: "Start was Jul 2026, before
  /// today", "Pushed by Build adapter (finish → start), which now ends
  /// Nov 2026".
  final List<String> reasons;

  /// Milestone, gate or hard deadline — a moved one is the headline.
  final bool isSinglePoint;
  final bool isCritical;

  /// The PM set this span by hand; the engine left it alone.
  final bool pinned;

  const ReplanChange({
    required this.activity,
    required this.fromStartMonth,
    required this.fromEndMonth,
    required this.fromStartDate,
    required this.fromEndDate,
    required this.toStartMonth,
    required this.toEndMonth,
    required this.toStartDate,
    required this.toEndDate,
    required this.slipped,
    required this.pushedBy,
    required this.reasons,
    required this.isSinglePoint,
    required this.isCritical,
    this.pinned = false,
  });

  String get id => activity.id;
  String get name => activity.name;

  /// Months moved, from the start.
  int get deltaMonths => (toStartMonth ?? 0) - (fromStartMonth ?? 0);
}

class ReplanWarning {
  final String activityId;
  final String message;
  const ReplanWarning(this.activityId, this.message);

  @override
  String toString() => message;
}

class ReplanProposal {
  final List<ReplanChange> changes;
  final List<ReplanWarning> warnings;
  const ReplanProposal({required this.changes, required this.warnings});

  bool get isEmpty => changes.isEmpty;
  int get slippedCount => changes.where((c) => c.slipped).length;
  int get pushedCount => changes.where((c) => !c.slipped).length;
  ReplanChange? changeFor(String id) {
    for (final c in changes) {
      if (c.id == id) return c;
    }
    return null;
  }
}

const _kSinglePointTypes = {'milestone', 'hard_deadline', 'gate'};

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Nov 2026" for a month index, given the anchor.
String replanMonthLabel(int month, DateTime month0) {
  final d = DateTime(month0.year, month0.month + month, 1);
  return '${_kMonths[d.month - 1]} ${d.year}';
}

/// "Jul–Sep 2026", "Nov 2026", or "12 Nov 2026 – 3 Dec 2026".
String replanSpanLabel({
  required int? startMonth,
  required int? endMonth,
  required String? startDate,
  required String? endDate,
  required DateTime month0,
}) {
  final sd = startDate != null ? DateTime.tryParse(startDate) : null;
  if (sd != null) {
    final ed = endDate != null ? DateTime.tryParse(endDate) : null;
    String fmt(DateTime d) => '${d.day} ${_kMonths[d.month - 1]} ${d.year}';
    if (ed == null || _iso(ed) == _iso(sd)) return fmt(sd);
    return '${fmt(sd)} – ${fmt(ed)}';
  }
  if (startMonth == null) return 'unscheduled';
  final e = endMonth ?? startMonth;
  if (e == startMonth) return replanMonthLabel(startMonth, month0);
  final s = replanMonthLabel(startMonth, month0);
  final en = replanMonthLabel(e, month0);
  // Same year: "Jul–Sep 2026".
  if (s.substring(4) == en.substring(4)) {
    return '${s.substring(0, 3)}–$en';
  }
  return '$s – $en';
}

String _typeLabel(String t) => switch (t) {
      'finish_to_start' => 'finish → start',
      'start_to_start' => 'start → start',
      'finish_to_finish' => 'finish → finish',
      _ => t.replaceAll('_', ' '),
    };

/// Working copy of a row's span while the forward pass runs.
class _Span {
  int? startMonth;
  int? endMonth;
  String? startDate;
  String? endDate;
  bool moved = false;
  bool slipped = false;
  bool pinned = false;
  final List<String> pushedBy = [];
  final List<String> reasons = [];

  _Span(TimelineActivity a)
      : startMonth = a.startMonth,
        endMonth = a.endMonth ?? a.startMonth,
        startDate = a.startDate,
        endDate = a.endDate;

  /// A real start date. A start-only date pins the start; the end stays
  /// month-level (see date_precision: a start-only date must never pin
  /// the end).
  bool get dated => startDate != null && DateTime.tryParse(startDate!) != null;

  /// A real end date too — only then do finish anchors work at day level.
  bool get endDated => dated && endDate != null && DateTime.tryParse(endDate!) != null;

  DateTime? get start => dated ? _day(DateTime.parse(startDate!)) : null;
  DateTime? get end => endDated ? _day(DateTime.parse(endDate!)) : null;

  /// Shift so that the start lands on [newStart] (date) or [newStartMonth]
  /// (month), preserving duration and keeping months in step with dates.
  void moveStartTo({DateTime? newStart, int? newStartMonth,
      required DateTime month0}) {
    if (dated && newStart != null) {
      final s = start!;
      final delta = newStart.difference(s).inDays;
      if (delta <= 0) return;
      final ns = s.add(Duration(days: delta));
      startDate = _iso(ns);
      if (endDated) {
        endDate = _iso(end!.add(Duration(days: delta)));
        final span = monthSpanForDates(
            startDate: startDate, endDate: endDate, month0Date: _iso(month0));
        startMonth = span?.startMonth;
        endMonth = span?.endMonth;
      } else {
        // Start-only: the start month follows the date, the end keeps
        // its month-level duration.
        final months = (endMonth ?? startMonth ?? 0) - (startMonth ?? 0);
        startMonth = monthIndexOf(ns, month0);
        endMonth = startMonth! + (months < 0 ? 0 : months);
      }
      moved = true;
      return;
    }
    if (newStartMonth != null && startMonth != null) {
      final delta = newStartMonth - startMonth!;
      if (delta <= 0) return;
      if (dated) {
        // A dated row moved by whole months keeps its day of month.
        final s = start!;
        final target = DateTime.utc(s.year, s.month + delta, 1);
        final lastDay = DateTime.utc(target.year, target.month + 1, 0).day;
        moveStartTo(
            newStart: DateTime.utc(target.year, target.month,
                s.day > lastDay ? lastDay : s.day),
            month0: month0);
        return;
      }
      startMonth = startMonth! + delta;
      endMonth = (endMonth ?? startMonth!) + delta;
      moved = true;
    }
  }

  /// Shift so that the end lands at or after [newEnd]/[newEndMonth].
  void moveEndTo({DateTime? newEnd, int? newEndMonth,
      required DateTime month0}) {
    if (endDated && newEnd != null) {
      final delta = newEnd.difference(end!).inDays;
      if (delta <= 0) return;
      moveStartTo(newStart: start!.add(Duration(days: delta)), month0: month0);
      return;
    }
    if (newEndMonth != null && endMonth != null) {
      final delta = newEndMonth - endMonth!;
      if (delta <= 0) return;
      moveStartTo(newStartMonth: startMonth! + delta, month0: month0);
    }
  }
}

/// A duration extension the PM accepted for one row (from the AI
/// overlay or by hand): the end moves out by this much, the start stays
/// with the engine. Months for month-level rows, days for dated ones.
class ReplanExtension {
  final int months;
  final int days;
  const ReplanExtension({this.months = 0, this.days = 0});
  bool get isZero => months == 0 && days == 0;
}

/// A span the PM set by hand on review. The row is pinned there: it is
/// never pushed again, but a predecessor it now contradicts is reported.
/// Months for month-level rows; dates (with months derived) for dated.
class ReplanOverride {
  final int? startMonth;
  final int? endMonth;
  final String? startDate;
  final String? endDate;
  const ReplanOverride({this.startMonth, this.endMonth, this.startDate, this.endDate});
}

/// Builds the proposal. [today] defaults to now; pass it in tests.
/// [extensions] lengthen the named rows before the forward pass, so
/// their successors are pushed by the longer span. Changes come back in
/// dependency order (predecessors first) so a review can walk them
/// front to back and nothing accepted later moves something accepted
/// earlier.
ReplanProposal buildReplanProposal({
  required List<TimelineActivity> activities,
  required List<TimelineDependency> dependencies,
  required String? month0Date,
  String? hardDeadlineDate,
  DateTime? today,
  Map<String, ReplanExtension> extensions = const {},
  Map<String, ReplanOverride> overrides = const {},
}) {
  final month0 = month0Date != null ? DateTime.tryParse(month0Date) : null;
  if (month0 == null) {
    return const ReplanProposal(changes: [], warnings: [
      ReplanWarning('',
          'The plan has no month-0 anchor (Plan → header settings), so '
          'dates cannot be re-planned.'),
    ]);
  }
  final now = _day(today ?? DateTime.now());
  final thisMonth = monthIndexOf(now, month0);

  final byId = {for (final a in activities) a.id: a};
  final spans = {for (final a in activities) a.id: _Span(a)};
  final warnings = <ReplanWarning>[];

  bool movable(TimelineActivity a) =>
      a.sourceProjectId == null &&
      a.status == 'not_started' &&
      (spans[a.id]!.startMonth != null || spans[a.id]!.dated);

  // ── 1. Slipped rows go to today ─────────────────────────────────────
  for (final a in activities) {
    if (!movable(a)) continue;
    final sp = spans[a.id]!;
    if (sp.dated) {
      if (sp.start!.isBefore(now)) {
        final was = replanSpanLabel(
            startMonth: sp.startMonth, endMonth: sp.endMonth,
            startDate: sp.startDate, endDate: sp.endDate, month0: month0);
        sp.moveStartTo(newStart: now, month0: month0);
        sp.slipped = true;
        sp.reasons.add('Start was $was, before today, and work has not started.');
      }
    } else if (sp.startMonth! < thisMonth) {
      final was = replanMonthLabel(sp.startMonth!, month0);
      sp.moveStartTo(newStartMonth: thisMonth, month0: month0);
      sp.slipped = true;
      sp.reasons.add('Start was $was, before this month, and work has not started.');
    }
  }

  // ── 1b. Accepted extensions lengthen the row before pushes ─────────
  for (final e in extensions.entries) {
    final sp = spans[e.key];
    final a = byId[e.key];
    if (sp == null || a == null || !movable(a) || e.value.isZero) continue;
    final before = _endLabel(sp, month0);
    if (sp.endDated && e.value.days > 0) {
      sp.endDate = _iso(sp.end!.add(Duration(days: e.value.days)));
      final span = monthSpanForDates(
          startDate: sp.startDate, endDate: sp.endDate, month0Date: _iso(month0));
      sp.endMonth = span?.endMonth ?? sp.endMonth;
      sp.moved = true;
    } else if (e.value.months > 0 && sp.endMonth != null) {
      sp.endMonth = sp.endMonth! + e.value.months;
      sp.moved = true;
    } else {
      continue;
    }
    sp.reasons.add('Extended from $before to ${_endLabel(sp, month0)} on review.');
  }

  // ── 1c. Hand-set spans win and pin the row ─────────────────────────
  for (final o in overrides.entries) {
    final sp = spans[o.key];
    final a = byId[o.key];
    if (sp == null || a == null || !movable(a)) continue;
    final v = o.value;
    if (v.startDate != null) {
      sp.startDate = v.startDate;
      sp.endDate = v.endDate;
      final span = monthSpanForDates(
          startDate: v.startDate, endDate: v.endDate, month0Date: _iso(month0));
      sp.startMonth = span?.startMonth ?? v.startMonth ?? sp.startMonth;
      sp.endMonth = v.endDate != null
          ? (span?.endMonth ?? sp.endMonth)
          : (v.endMonth ?? sp.endMonth);
    } else if (v.startMonth != null) {
      sp.startMonth = v.startMonth;
      sp.endMonth = v.endMonth ?? v.startMonth;
      sp.startDate = null;
      sp.endDate = null;
    } else {
      continue;
    }
    sp.moved = true;
    sp.pinned = true;
    sp.reasons.add('Set by you on review: ${replanSpanLabel(
        startMonth: sp.startMonth, endMonth: sp.endMonth,
        startDate: sp.startDate, endDate: sp.endDate, month0: month0)}.');
  }

  // ── 2. Forward pass through the dependency graph ───────────────────
  final bySuccessor = <String, List<TimelineDependency>>{};
  for (final d in dependencies) {
    if (d.dependencyType == 'external' || d.fromActivityId.isEmpty) continue;
    if (!byId.containsKey(d.fromActivityId) || !byId.containsKey(d.toActivityId)) {
      continue;
    }
    bySuccessor.putIfAbsent(d.toActivityId, () => []).add(d);
  }

  // Bounded passes: each pass propagates one more hop; the graph depth is
  // at most the row count, and a cycle can't move a row twice for the
  // same reason because moves are monotonic and recorded per edge.
  final recorded = <String>{};
  for (var pass = 0; pass < activities.length + 1; pass++) {
    var changed = false;
    for (final a in activities) {
      final deps = bySuccessor[a.id];
      if (deps == null) continue;
      final succ = spans[a.id]!;
      for (final d in deps) {
        final pred = spans[d.fromActivityId]!;
        final predAct = byId[d.fromActivityId]!;
        // A pre-existing inconsistency between two untouched rows is not
        // this re-plan's business; a slipped successor behind a late,
        // still-running predecessor very much is.
        if (!pred.moved && !succ.moved) continue;
        final violated = _violation(d.dependencyType, pred, succ, month0);
        if (violated == null) continue;
        final edgeKey = '${d.id}:${pred.startMonth}:${pred.endMonth}:${pred.startDate}:${pred.endDate}';
        if (!movable(a)) {
          if (recorded.add(edgeKey)) {
            warnings.add(ReplanWarning(a.id,
                '${a.name} has already started, but ${predAct.name} '
                '(${_typeLabel(d.dependencyType)}) now ends '
                '${_endLabel(pred, month0)} — the dependency is inconsistent.'));
          }
          continue;
        }
        if (succ.pinned) {
          if (recorded.add(edgeKey)) {
            warnings.add(ReplanWarning(a.id,
                'The span you set for ${a.name} starts before '
                '${predAct.name} (${_typeLabel(d.dependencyType)}) '
                '${d.dependencyType == 'start_to_start' ? 'starts' : 'ends'} '
                '${d.dependencyType == 'start_to_start' ? _startLabel(pred, month0) : _endLabel(pred, month0)}.'));
          }
          continue;
        }
        violated();
        changed = true;
        if (!succ.pushedBy.contains(predAct.id)) succ.pushedBy.add(predAct.id);
        if (recorded.add(edgeKey)) {
          final verb = d.dependencyType == 'start_to_start' ? 'starts' : 'ends';
          final when = d.dependencyType == 'start_to_start'
              ? _startLabel(pred, month0)
              : _endLabel(pred, month0);
          succ.reasons.add(pred.moved
              ? 'Pushed by ${predAct.name} (${_typeLabel(d.dependencyType)}), '
                  'which now $verb $when.'
              : 'Held by ${predAct.name} (${_typeLabel(d.dependencyType)}), '
                  'which is ${predAct.status == 'complete' ? 'complete and' : 'still running and'} $verb $when.');
        }
      }
    }
    if (!changed) break;
  }

  // External dependencies on moved rows: surface the label.
  for (final d in dependencies) {
    if (d.dependencyType != 'external' && d.fromActivityId.isNotEmpty) continue;
    final sp = spans[d.toActivityId];
    if (sp == null || !sp.moved) continue;
    final label = (d.externalLabel ?? '').trim();
    if (label.isNotEmpty) {
      sp.reasons.add('Depends on $label (external) — not moved by this re-plan; check it still lands in time.');
    }
  }

  // ── 3. Collect changes and deadline collisions ─────────────────────
  final deadline = hardDeadlineDate != null ? DateTime.tryParse(hardDeadlineDate) : null;
  final deadlineMonth = deadline != null ? monthIndexOf(deadline, month0) : null;
  final changes = <ReplanChange>[];
  for (final a in _dependencyOrder(activities, bySuccessor)) {
    final sp = spans[a.id]!;
    if (!sp.moved) continue;
    changes.add(ReplanChange(
      activity: a,
      fromStartMonth: a.startMonth,
      fromEndMonth: a.endMonth ?? a.startMonth,
      fromStartDate: a.startDate,
      fromEndDate: a.endDate ?? a.startDate,
      toStartMonth: sp.startMonth,
      toEndMonth: sp.endMonth,
      toStartDate: sp.startDate,
      toEndDate: sp.endDate,
      slipped: sp.slipped,
      pushedBy: List.unmodifiable(sp.pushedBy),
      reasons: List.unmodifiable(sp.reasons),
      isSinglePoint: _kSinglePointTypes.contains(a.activityType),
      isCritical: a.isCritical,
      pinned: sp.pinned,
    ));
    if (deadline != null) {
      final past = sp.endDated
          ? sp.end!.isAfter(_day(deadline))
          : (sp.endMonth ?? 0) > deadlineMonth!;
      if (past) {
        warnings.add(ReplanWarning(a.id,
            '${a.name} would now end ${_endLabel(sp, month0)}, past the '
            'hard deadline of ${replanSpanLabel(startMonth: null, endMonth: null, startDate: hardDeadlineDate, endDate: null, month0: month0)}.'));
      }
    }
    if (_kSinglePointTypes.contains(a.activityType)) {
      warnings.add(ReplanWarning(a.id,
          '${a.name} is a ${a.activityType.replaceAll('_', ' ')} and would move to ${_startLabel(sp, month0)}.'));
    }
  }
  return ReplanProposal(changes: changes, warnings: warnings);
}

/// Kahn's ordering over the internal edges, ties by the plan's own
/// order; rows caught in a cycle are appended in plan order at the end.
List<TimelineActivity> _dependencyOrder(List<TimelineActivity> activities,
    Map<String, List<TimelineDependency>> bySuccessor) {
  final indegree = <String, int>{for (final a in activities) a.id: 0};
  final successors = <String, List<String>>{};
  for (final entry in bySuccessor.entries) {
    for (final d in entry.value) {
      indegree[entry.key] = (indegree[entry.key] ?? 0) + 1;
      successors.putIfAbsent(d.fromActivityId, () => []).add(entry.key);
    }
  }
  final byId = {for (final a in activities) a.id: a};
  final ready = [for (final a in activities) if (indegree[a.id] == 0) a.id];
  final out = <TimelineActivity>[];
  final seen = <String>{};
  while (ready.isNotEmpty) {
    final id = ready.removeAt(0);
    if (!seen.add(id)) continue;
    out.add(byId[id]!);
    for (final s in successors[id] ?? const <String>[]) {
      indegree[s] = indegree[s]! - 1;
      if (indegree[s] == 0) ready.add(s);
    }
    // Keep plan order among the ready set.
    ready.sort((x, y) => activities.indexWhere((a) => a.id == x)
        .compareTo(activities.indexWhere((a) => a.id == y)));
  }
  for (final a in activities) {
    if (!seen.contains(a.id)) out.add(a);
  }
  return out;
}

String _startLabel(_Span sp, DateTime month0) => replanSpanLabel(
    startMonth: sp.startMonth, endMonth: sp.startMonth,
    startDate: sp.startDate, endDate: sp.startDate, month0: month0);

String _endLabel(_Span sp, DateTime month0) => replanSpanLabel(
    startMonth: sp.endMonth, endMonth: sp.endMonth,
    startDate: sp.endDate, endDate: sp.endDate, month0: month0);

/// Null when [succ] already satisfies the constraint from [pred];
/// otherwise a closure that moves [succ] the minimum to satisfy it.
void Function()? _violation(
    String type, _Span pred, _Span succ, DateTime month0) {
  switch (type) {
    case 'start_to_start':
      if (pred.dated && succ.dated) {
        if (!succ.start!.isBefore(pred.start!)) return null;
        return () => succ.moveStartTo(newStart: pred.start!, month0: month0);
      }
      if (pred.startMonth == null || succ.startMonth == null) return null;
      if (succ.startMonth! >= pred.startMonth!) return null;
      return () => succ.moveStartTo(newStartMonth: pred.startMonth!, month0: month0);
    case 'finish_to_finish':
      if (pred.endDated && succ.endDated) {
        if (!succ.end!.isBefore(pred.end!)) return null;
        return () => succ.moveEndTo(newEnd: pred.end!, month0: month0);
      }
      if (pred.endMonth == null || succ.endMonth == null) return null;
      if (succ.endMonth! >= pred.endMonth!) return null;
      return () => succ.moveEndTo(newEndMonth: pred.endMonth!, month0: month0);
    default: // finish_to_start
      if (pred.endDated && succ.dated) {
        final earliest = pred.end!.add(const Duration(days: 1));
        if (!succ.start!.isBefore(earliest)) return null;
        return () => succ.moveStartTo(newStart: earliest, month0: month0);
      }
      if (pred.endMonth == null || succ.startMonth == null) return null;
      if (succ.startMonth! >= pred.endMonth!) return null;
      return () => succ.moveStartTo(newStartMonth: pred.endMonth!, month0: month0);
  }
}

/// The note appended to a row when a change is applied. [aiView] is the
/// model's sentence (with its confidence), kept so the plan carries its
/// own reasoning history, not just the arithmetic.
String replanNote(ReplanChange c, DateTime month0,
    {DateTime? today, String? aiView}) {
  final d = _iso(today ?? DateTime.now());
  final was = replanSpanLabel(
      startMonth: c.fromStartMonth, endMonth: c.fromEndMonth,
      startDate: c.fromStartDate, endDate: c.fromEndDate, month0: month0);
  final now = replanSpanLabel(
      startMonth: c.toStartMonth, endMonth: c.toEndMonth,
      startDate: c.toStartDate, endDate: c.toEndDate, month0: month0);
  final why = c.reasons.isEmpty ? '' : ' ${c.reasons.join(' ')}';
  final ai = (aiView ?? '').trim().isEmpty ? '' : ' ${aiView!.trim()}';
  return 'Re-planned $d: was $was, now $now.$why$ai';
}
