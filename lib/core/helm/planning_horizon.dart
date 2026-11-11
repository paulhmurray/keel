/// The planning horizon behind Helm's "Suggested" rail.
///
/// The old rail offered only what was already behind: overdue and
/// due-today actions. Planning a day from that means always reacting.
/// This gathers everything with a date across every project — actions,
/// decisions, dependencies, risk treatment and review dates, issues and
/// dated plan activities — and buckets it into overdue, today, the rest
/// of this week (by day) and next week, so the day and the week can be
/// planned from what is coming, not just what slipped. Pure Dart.
library;

import '../database/database.dart';
import '../raid/raid_conversion_service.dart' show RaidKind;
import '../raid/raid_lifecycle.dart';
import '../raid/risk_rating.dart';
import 'day_plan_logic.dart' show mondayOf;

enum PlanningKind {
  action,
  decision,
  dependency,
  riskTreatment,
  riskReview,
  /// Overdue risk reviews for one project, rolled into a single row: a
  /// review is a ritual, not forty separate rocks. See
  /// [kReviewRollUpThreshold].
  riskReviewSession,
  issue,
  activityStart,
  activityEnd,
  milestone,
}

class PlanningItem {
  final PlanningKind kind;
  final String id;
  final String projectId;
  final String projectName;
  final String label;

  /// What kind of date this is, in words: "Decision needed", "Review
  /// due", "Starts", "Ends" — the rail shows it beside the project name.
  final String dateKind;
  final String dueIso;

  /// Set for actions so a dropped block links back to the action.
  final String? linkedActionId;

  /// Extra weight within a day: escalated risks and critical items first.
  final int priority;

  /// For a [PlanningKind.riskReviewSession] row, how many reviews it
  /// stands for. Zero for every other kind.
  final int count;

  const PlanningItem({
    required this.kind,
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.label,
    required this.dateKind,
    required this.dueIso,
    this.linkedActionId,
    this.priority = 0,
    this.count = 0,
  });
}

/// Overdue risk reviews in one project roll up into a single "review
/// session" row once there are at least this many. One overdue review is
/// a row of its own; two or more are a sitting.
const int kReviewRollUpThreshold = 2;

/// Replaces runs of overdue [PlanningKind.riskReview] rows with one
/// [PlanningKind.riskReviewSession] row per project (see
/// [kReviewRollUpThreshold]). Dated as the oldest review it stands for,
/// so it sorts where the first missed review would have.
List<PlanningItem> rollUpOverdueReviews(List<PlanningItem> overdue) {
  final byProject = <String, List<PlanningItem>>{};
  for (final it in overdue) {
    if (it.kind == PlanningKind.riskReview) {
      byProject.putIfAbsent(it.projectId, () => []).add(it);
    }
  }
  final rolled = <String>{
    for (final e in byProject.entries)
      if (e.value.length >= kReviewRollUpThreshold) e.key,
  };
  if (rolled.isEmpty) return overdue;
  final out = <PlanningItem>[
    for (final it in overdue)
      if (!(it.kind == PlanningKind.riskReview && rolled.contains(it.projectId)))
        it,
  ];
  for (final pid in rolled) {
    final members = byProject[pid]!..sort((a, b) => a.dueIso.compareTo(b.dueIso));
    out.add(PlanningItem(
      kind: PlanningKind.riskReviewSession,
      id: 'review:$pid',
      projectId: pid,
      projectName: members.first.projectName,
      label: '${members.length} risk reviews overdue',
      dateKind: 'Review session',
      dueIso: members.first.dueIso,
      priority: 2,
      count: members.length,
    ));
  }
  return out;
}

/// A day of the week ahead with what falls due on it.
class PlanningDay {
  final String iso;
  final DateTime date;
  final List<PlanningItem> items;
  const PlanningDay({required this.iso, required this.date, required this.items});
}

class PlanningHorizon {
  final List<PlanningItem> overdue;
  final List<PlanningItem> today;

  /// Days after today up to Sunday of this week, in order; only days
  /// with something due are included.
  final List<PlanningDay> restOfWeek;

  /// Monday to Sunday of next week, flattened and sorted by date.
  final List<PlanningItem> nextWeek;

  const PlanningHorizon({
    required this.overdue,
    required this.today,
    required this.restOfWeek,
    required this.nextWeek,
  });

  bool get isEmpty =>
      overdue.isEmpty && today.isEmpty && restOfWeek.isEmpty && nextWeek.isEmpty;
}

String isoOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// True when a risk's next review falls after the week that holds
/// [today]: the risk is parked until then and should not be offered as
/// something to take on this week. A review this week, overdue, or
/// unset is not parked. Only risks carry a review date.
bool parkedUntilReview(String? nextReviewAt, DateTime today) {
  if (nextReviewAt == null || nextReviewAt.length < 10) return false;
  final day0 = DateTime(today.year, today.month, today.day);
  final sundayIso = isoOf(mondayOf(day0).add(const Duration(days: 6)));
  return nextReviewAt.substring(0, 10).compareTo(sundayIso) > 0;
}

/// Builds the horizon for [today] from cross-project material. Items
/// without a usable date are ignored — they belong in the browse lists.
PlanningHorizon buildPlanningHorizon({
  required DateTime today,
  required Iterable<({ProjectAction action, String projectName})> actions,
  required Iterable<({Decision decision, String projectName})> decisions,
  required Iterable<({ProgramDependency dependency, String projectName})>
      dependencies,
  required Iterable<({Risk risk, String projectName})> risks,
  required Iterable<({Issue issue, String projectName})> issues,
  required Iterable<
          ({TimelineActivity activity, String projectName, String? wpCode})>
      activities,
}) {
  final day0 = DateTime(today.year, today.month, today.day);
  final todayIso = isoOf(day0);
  final monday = mondayOf(day0);
  final sunday = monday.add(const Duration(days: 6));
  final nextMonday = monday.add(const Duration(days: 7));
  final nextSunday = nextMonday.add(const Duration(days: 6));
  final sundayIso = isoOf(sunday);
  final nextMondayIso = isoOf(nextMonday);
  final nextSundayIso = isoOf(nextSunday);

  final items = <PlanningItem>[];

  bool dated(String? iso) => iso != null && iso.length >= 10;

  for (final a in actions) {
    final x = a.action;
    if (x.status == 'closed' || !dated(x.dueDate)) continue;
    items.add(PlanningItem(
      kind: PlanningKind.action,
      id: x.id,
      projectId: x.projectId,
      projectName: a.projectName,
      label: '${x.ref != null ? '${x.ref} ' : ''}${x.description}',
      dateKind: 'Action due',
      dueIso: x.dueDate!.substring(0, 10),
      linkedActionId: x.id,
      priority: switch (x.priority) { 'critical' => 3, 'high' => 2, _ => 0 },
    ));
  }

  for (final d in decisions) {
    final x = d.decision;
    if (x.status != 'pending' || !dated(x.dueDate)) continue;
    items.add(PlanningItem(
      kind: PlanningKind.decision,
      id: x.id,
      projectId: x.projectId,
      projectName: d.projectName,
      label: '${x.ref != null ? '${x.ref} ' : ''}${x.description}',
      dateKind: 'Decision needed',
      dueIso: x.dueDate!.substring(0, 10),
      priority: 2,
    ));
  }

  for (final d in dependencies) {
    final x = d.dependency;
    if (!isActiveStatus(RaidKind.dependency, x.status) || !dated(x.dueDate)) {
      continue;
    }
    items.add(PlanningItem(
      kind: PlanningKind.dependency,
      id: x.id,
      projectId: x.projectId,
      projectName: d.projectName,
      label: '${x.ref != null ? '${x.ref} ' : ''}${x.description}',
      dateKind: 'Dependency needed by',
      dueIso: x.dueDate!.substring(0, 10),
      priority: 1,
    ));
  }

  for (final r in risks) {
    final x = r.risk;
    if (isTerminalStatus(RaidKind.risk, x.status)) continue;
    final title = '${x.ref != null ? '${x.ref} ' : ''}${x.title ?? x.description}';
    final weight = (x.steerco ? 2 : 0) +
        (riskBand(x.likelihood, x.impact) == 'high' ? 1 : 0);
    // An accepted risk is one we chose not to treat: its treatment date
    // is no commitment, but its review still is — accepting a risk is
    // not the end of watching it.
    if (isActiveStatus(RaidKind.risk, x.status) && dated(x.dueDate)) {
      items.add(PlanningItem(
        kind: PlanningKind.riskTreatment,
        id: x.id,
        projectId: x.projectId,
        projectName: r.projectName,
        label: title,
        dateKind: 'Risk treatment due',
        dueIso: x.dueDate!.substring(0, 10),
        priority: weight,
      ));
    }
    // A review beyond this week is parked: it is not raw material for
    // this week's plan, even though "next week" shows other dated work.
    // A dated treatment above is a commitment and stays regardless.
    // A cascaded copy's review is the source project's job — the copy is
    // read-only here, so a row for it would be a dead end and would
    // inflate the roll-up with reviews the session cannot hold.
    if (x.sourceProjectId == null &&
        dated(x.nextReviewAt) &&
        !parkedUntilReview(x.nextReviewAt, day0)) {
      items.add(PlanningItem(
        kind: PlanningKind.riskReview,
        id: x.id,
        projectId: x.projectId,
        projectName: r.projectName,
        label: title,
        dateKind: 'Risk review',
        dueIso: x.nextReviewAt!.substring(0, 10),
        priority: weight - 1,
      ));
    }
  }

  for (final i in issues) {
    final x = i.issue;
    if (isTerminalStatus(RaidKind.issue, x.status) || !dated(x.dueDate)) {
      continue;
    }
    items.add(PlanningItem(
      kind: PlanningKind.issue,
      id: x.id,
      projectId: x.projectId,
      projectName: i.projectName,
      label: '${x.ref != null ? '${x.ref} ' : ''}${x.title ?? x.description}',
      dateKind: 'Issue due',
      dueIso: x.dueDate!.substring(0, 10),
      priority: switch (x.priority) { 'critical' => 3, 'high' => 2, _ => 0 },
    ));
  }

  for (final a in activities) {
    final x = a.activity;
    if (x.status == 'complete') continue;
    final prefix = a.wpCode != null ? '[${a.wpCode}] ' : '';
    final single = x.activityType == 'milestone' ||
        x.activityType == 'hard_deadline' ||
        x.activityType == 'gate';
    if (single) {
      if (!dated(x.startDate)) continue;
      items.add(PlanningItem(
        kind: PlanningKind.milestone,
        id: x.id,
        projectId: x.projectId,
        projectName: a.projectName,
        label: '$prefix${x.name}',
        dateKind: switch (x.activityType) {
          'hard_deadline' => 'Hard deadline',
          'gate' => 'Gate',
          _ => 'Milestone',
        },
        dueIso: x.startDate!.substring(0, 10),
        priority: x.activityType == 'hard_deadline' ? 3 : 2,
      ));
      continue;
    }
    if (dated(x.startDate)) {
      items.add(PlanningItem(
        kind: PlanningKind.activityStart,
        id: x.id,
        projectId: x.projectId,
        projectName: a.projectName,
        label: '$prefix${x.name}',
        dateKind: 'Activity starts',
        dueIso: x.startDate!.substring(0, 10),
      ));
    }
    if (dated(x.endDate)) {
      items.add(PlanningItem(
        kind: PlanningKind.activityEnd,
        id: x.id,
        projectId: x.projectId,
        projectName: a.projectName,
        label: '$prefix${x.name}',
        dateKind: 'Activity ends',
        dueIso: x.endDate!.substring(0, 10),
        priority: 1,
      ));
    }
  }

  int cmp(PlanningItem a, PlanningItem b) {
    final d = a.dueIso.compareTo(b.dueIso);
    if (d != 0) return d;
    final p = b.priority.compareTo(a.priority);
    if (p != 0) return p;
    final k = a.kind.index.compareTo(b.kind.index);
    if (k != 0) return k;
    return a.label.compareTo(b.label);
  }

  final overdue = <PlanningItem>[];
  final todayItems = <PlanningItem>[];
  final byDay = <String, List<PlanningItem>>{};
  final nextWeek = <PlanningItem>[];
  for (final it in items) {
    if (it.dueIso.compareTo(todayIso) < 0) {
      // An activity that started in the past isn't "overdue" — only its
      // end date can be. Everything else with a past date is behind.
      if (it.kind == PlanningKind.activityStart) continue;
      overdue.add(it);
    } else if (it.dueIso == todayIso) {
      todayItems.add(it);
    } else if (it.dueIso.compareTo(sundayIso) <= 0) {
      byDay.putIfAbsent(it.dueIso, () => []).add(it);
    } else if (it.dueIso.compareTo(nextMondayIso) >= 0 &&
        it.dueIso.compareTo(nextSundayIso) <= 0) {
      nextWeek.add(it);
    }
  }
  final overdueRolled = rollUpOverdueReviews(overdue)..sort(cmp);
  todayItems.sort(cmp);
  nextWeek.sort(cmp);
  final days = byDay.keys.toList()..sort();
  final rest = [
    for (final iso in days)
      PlanningDay(
        iso: iso,
        date: DateTime.parse(iso),
        items: (byDay[iso]!..sort(cmp)),
      ),
  ];

  return PlanningHorizon(
    overdue: overdueRolled,
    today: todayItems,
    restOfWeek: rest,
    nextWeek: nextWeek,
  );
}

/// "Tue 30 Sep" for the rail's day headers.
String planningDayLabel(DateTime d) {
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${wd[d.weekday - 1]} ${d.day} ${mo[d.month - 1]}';
}
