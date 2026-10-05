/// Register items that belong on the plan but aren't: open actions with
/// a due date and no plan link, pending decisions and open inbound
/// dependencies that gate nothing, open risks that no activity names as
/// a schedule driver. Keel already links each of these to a plan row;
/// this module finds the ones that were never linked, places each one
/// deterministically (the activity whose window holds the due month),
/// and lets the model improve the placement. Pure Dart — the dialog
/// does the writes.
library;

import '../database/database.dart';
import '../raid/dependency_plan_link.dart' show DependencyPlanLink;
import '../raid/raid_conversion_service.dart' show RaidKind;
import '../raid/raid_lifecycle.dart';
import '../raid/risk_rating.dart';
import 'date_precision.dart';
import 'replan.dart' show replanMonthLabel;
import 'replan_assist.dart' show firstJsonObject;
import 'variance_links.dart';

enum GapKind { action, decision, dependency, risk }

extension GapKindExt on GapKind {
  String get label => switch (this) {
        GapKind.action => 'Action',
        GapKind.decision => 'Decision',
        GapKind.dependency => 'Dependency',
        GapKind.risk => 'Risk',
      };

  /// What accepting does, in words.
  String get linkVerb => switch (this) {
        GapKind.action => 'sits under',
        GapKind.decision => 'gates',
        GapKind.dependency => 'gates',
        GapKind.risk => 'threatens',
      };
}

/// One register item with no plan link.
class PlanGap {
  final GapKind kind;
  final String id;
  final String? ref;
  final String title;
  final String? detail;
  final String? owner;
  final String status;

  /// ISO due / needed-by / treatment date, when there is one.
  final String? dueIso;

  /// Month index of [dueIso] against the plan anchor, or null.
  final int? dueMonth;

  const PlanGap({
    required this.kind,
    required this.id,
    required this.title,
    required this.status,
    this.ref,
    this.detail,
    this.owner,
    this.dueIso,
    this.dueMonth,
  });

  String get display => ref == null || ref!.isEmpty ? title : '$ref · $title';
}

/// Where a gap should go: an existing activity, or a new one.
class GapPlacement {
  final String? activityId;
  final String? newWorkPackageId;
  final String? newName;
  final int? newMonth;

  /// 'activity' | 'milestone' | 'gate' for a new row.
  final String newType;
  final String rationale;

  /// 'engine' | 'ai' | 'you'
  final String source;

  const GapPlacement({
    this.activityId,
    this.newWorkPackageId,
    this.newName,
    this.newMonth,
    this.newType = 'activity',
    this.rationale = '',
    this.source = 'engine',
  });

  bool get isNew => activityId == null && newWorkPackageId != null;
  bool get isEmpty => activityId == null && newWorkPackageId == null;

  GapPlacement copyWith({
    String? activityId,
    String? newWorkPackageId,
    String? newName,
    int? newMonth,
    String? newType,
    String? rationale,
    String? source,
    bool clearActivity = false,
    bool clearNew = false,
  }) =>
      GapPlacement(
        activityId: clearActivity ? null : activityId ?? this.activityId,
        newWorkPackageId:
            clearNew ? null : newWorkPackageId ?? this.newWorkPackageId,
        newName: clearNew ? null : newName ?? this.newName,
        newMonth: clearNew ? null : newMonth ?? this.newMonth,
        newType: newType ?? this.newType,
        rationale: rationale ?? this.rationale,
        source: source ?? this.source,
      );
}

int? _monthOf(String? iso, DateTime? month0) {
  if (iso == null || month0 == null) return null;
  final d = DateTime.tryParse(iso);
  return d == null ? null : monthIndexOf(d, month0);
}

/// Finds everything in the registers that should be on the plan and
/// isn't. Closed and cascaded items are never gaps.
List<PlanGap> collectPlanGaps({
  required List<ProjectAction> actions,
  required List<Decision> decisions,
  required List<ProgramDependency> dependencies,
  required List<Risk> risks,
  required List<TimelineActivity> activities,
  required String? month0Date,
}) {
  final month0 = month0Date != null ? DateTime.tryParse(month0Date) : null;
  final out = <PlanGap>[];

  for (final a in actions) {
    if (a.sourceProjectId != null || a.isParent) continue;
    if (a.status == 'closed' || a.planActivityId != null) continue;
    if (a.dueDate == null) continue;
    out.add(PlanGap(
      kind: GapKind.action,
      id: a.id,
      ref: a.ref,
      title: a.description,
      owner: a.owner,
      status: a.status,
      dueIso: a.dueDate,
      dueMonth: _monthOf(a.dueDate, month0),
    ));
  }

  for (final d in decisions) {
    if (d.sourceProjectId != null || d.planActivityId != null) continue;
    if (isTerminalStatus(RaidKind.decision, d.status)) continue;
    if (d.dueDate == null) continue;
    out.add(PlanGap(
      kind: GapKind.decision,
      id: d.id,
      ref: d.ref,
      title: d.description,
      detail: d.impactStatement,
      owner: d.decisionMaker,
      status: d.status,
      dueIso: d.dueDate,
      dueMonth: _monthOf(d.dueDate, month0),
    ));
  }

  for (final d in dependencies) {
    if (d.sourceProjectId != null || d.planActivityId != null) continue;
    if (isTerminalStatus(RaidKind.dependency, d.status)) continue;
    if (!DependencyPlanLink.canShowOnPlan(d.dependencyType)) continue;
    if (d.dueDate == null) continue;
    out.add(PlanGap(
      kind: GapKind.dependency,
      id: d.id,
      ref: d.ref,
      title: d.description,
      detail: [
        if ((d.counterparty ?? '').trim().isNotEmpty) 'from ${d.counterparty}',
        if ((d.impactStatement ?? '').trim().isNotEmpty) d.impactStatement!,
      ].join(' — '),
      owner: d.owner,
      status: d.status,
      dueIso: d.dueDate,
      dueMonth: _monthOf(d.dueDate, month0),
    ));
  }

  // Risks already named as a schedule driver on any activity are linked.
  final linkedRisks = <String>{
    for (final a in activities)
      for (final l in effectiveVarianceLinks(
        linksJson: a.varianceRaidLinksJson,
        legacyType: a.varianceRaidType,
        legacyId: a.varianceRaidId,
      ))
        if (l.type == 'risk') l.id,
  };
  for (final r in risks) {
    if (r.sourceProjectId != null || linkedRisks.contains(r.id)) continue;
    if (isTerminalStatus(RaidKind.risk, r.status)) continue;
    final high = riskBand(r.likelihood, r.impact) == 'high';
    if (r.dueDate == null && !high) continue;
    out.add(PlanGap(
      kind: GapKind.risk,
      id: r.id,
      ref: r.ref,
      title: (r.title ?? '').trim().isNotEmpty ? r.title!.trim() : r.description,
      detail: r.mitigation,
      owner: r.owner,
      status: '${r.status} · ${r.likelihood}/${r.impact}',
      dueIso: r.dueDate,
      dueMonth: _monthOf(r.dueDate, month0),
    ));
  }

  return out;
}

/// The engine's own placement: the open, top-level activity whose window
/// holds the due month, nearest by start when several do; failing that,
/// the activity nearest in time; failing that, a new row in the first
/// work package at the due month. Null only when the plan is empty.
GapPlacement? placeGapDeterministically(
  PlanGap gap, {
  required List<TimelineActivity> activities,
  required List<TimelineWorkPackage> workPackages,
  required DateTime? month0,
}) {
  final candidates = activities
      .where((a) =>
          a.sourceProjectId == null &&
          a.parentActivityId == null &&
          a.activityType == 'activity' &&
          a.status != 'complete' &&
          a.startMonth != null)
      .toList();
  final due = gap.dueMonth;
  String why(TimelineActivity a) => month0 == null
      ? 'Runs when this is due.'
      : 'Runs ${replanMonthLabel(a.startMonth!, month0)}–'
          '${replanMonthLabel(a.endMonth ?? a.startMonth!, month0)}, '
          'which covers when this is due.';
  if (due != null) {
    final covering = candidates
        .where((a) => a.startMonth! <= due && (a.endMonth ?? a.startMonth!) >= due)
        .toList()
      ..sort((x, y) => y.startMonth!.compareTo(x.startMonth!));
    if (covering.isNotEmpty) {
      return GapPlacement(activityId: covering.first.id, rationale: why(covering.first));
    }
    if (candidates.isNotEmpty) {
      int dist(TimelineActivity a) {
        final s = a.startMonth!;
        final e = a.endMonth ?? s;
        return due < s ? s - due : due - e;
      }
      candidates.sort((x, y) => dist(x).compareTo(dist(y)));
      final a = candidates.first;
      return GapPlacement(
        activityId: a.id,
        rationale: 'Nearest activity in time; nothing runs in the month this is due.',
      );
    }
  } else if (candidates.isNotEmpty) {
    return GapPlacement(
      activityId: candidates.first.id,
      rationale: 'No date on the item; the first open activity is a starting point.',
    );
  }
  if (workPackages.isEmpty) return null;
  return GapPlacement(
    newWorkPackageId: workPackages.first.id,
    newName: gap.display,
    newMonth: due,
    rationale: 'Nothing on the plan covers this; a new row is proposed.',
  );
}

// ─── AI placement ────────────────────────────────────────────────────────

class GapAssistPrompt {
  final String system;
  final String user;
  const GapAssistPrompt({required this.system, required this.user});
}

const String _kPersona =
    'You are helping a project manager keep a delivery plan current. A '
    'register item (an action, a decision, a dependency or a risk) is not '
    'yet attached to any plan activity. Choose the existing activity it '
    'belongs with, or, only if none fits, propose one new activity. Use '
    'only the activities listed; never invent ids. Answer ONLY with a '
    'single JSON object and nothing else.';

String _line(String label, String? value) =>
    value == null || value.trim().isEmpty ? '' : '$label: ${value.trim()}\n';

/// Builds the prompt for one gap. [activities] should be the open,
/// top-level rows, trimmed to those nearest the due month when the plan
/// is large (the dialog caps it).
GapAssistPrompt gapAssistPrompt({
  required PlanGap gap,
  required List<TimelineActivity> activities,
  required List<TimelineWorkPackage> workPackages,
  required DateTime? month0,
  required GapPlacement? engine,
  String? projectContext,
}) {
  final wpName = {for (final w in workPackages) w.id: w.name};
  String span(TimelineActivity a) => month0 == null || a.startMonth == null
      ? 'unscheduled'
      : '${replanMonthLabel(a.startMonth!, month0)}–'
          '${replanMonthLabel(a.endMonth ?? a.startMonth!, month0)}';
  final meaning = switch (gap.kind) {
    GapKind.action => 'the activity this action is part of',
    GapKind.decision => 'the activity that cannot start until this decision is made',
    GapKind.dependency => 'the activity that cannot start until this lands',
    GapKind.risk => 'the activity whose schedule this risk threatens most',
  };
  final b = StringBuffer()
    ..write(_line('Item', '${gap.kind.label}: ${gap.display}'))
    ..write(_line('Detail', gap.detail))
    ..write(_line('Owner', gap.owner))
    ..write(_line('Status', gap.status))
    ..write(_line('Due', month0 != null && gap.dueMonth != null
        ? '${gap.dueIso} (${replanMonthLabel(gap.dueMonth!, month0)})'
        : gap.dueIso))
    ..write('\nPlan activities (id | work package | name | window):\n');
  for (final a in activities) {
    b.writeln('${a.id} | ${wpName[a.workPackageId] ?? '?'} | ${a.name} | ${span(a)}');
  }
  b.write('\nWork packages (id | name):\n');
  for (final w in workPackages) {
    b.writeln('${w.id} | ${w.name}');
  }
  if (engine?.activityId != null) {
    b.write('\nThe engine\'s guess: ${engine!.activityId} (${engine.rationale})\n');
  }
  b
    ..write('\nChoose $meaning. Reply with exactly this JSON:\n')
    ..write('{"activity_id": "<id from the list>" | null, ')
    ..write('"new_activity": {"work_package_id": "<id>", "name": "<at most 8 words>", '
        '"month": "<YYYY-MM>"} | null, ')
    ..write('"rationale": "<one sentence>"}\n')
    ..write('Prefer an existing activity. Propose new_activity only when no '
        'listed activity is about this work.');
  return GapAssistPrompt(
    system: projectContext == null || projectContext.trim().isEmpty
        ? _kPersona
        : '$projectContext\n\n---\n\n$_kPersona',
    user: b.toString(),
  );
}

/// Parses the model's placement. Ids are checked against the plan; an
/// unknown id or a malformed object yields null so the engine's guess
/// stands.
GapPlacement? parseGapPlacement(
  String raw, {
  required Set<String> activityIds,
  required Set<String> workPackageIds,
  required DateTime? month0,
}) {
  final obj = firstJsonObject(raw);
  if (obj == null) return null;
  final rationale = '${obj['rationale'] ?? ''}'.trim();
  final actId = obj['activity_id'];
  if (actId is String && activityIds.contains(actId)) {
    return GapPlacement(activityId: actId, rationale: rationale, source: 'ai');
  }
  final nw = obj['new_activity'];
  if (nw is Map) {
    final wp = nw['work_package_id'];
    final name = '${nw['name'] ?? ''}'.trim();
    if (wp is String && workPackageIds.contains(wp) && name.isNotEmpty) {
      int? month;
      final m = '${nw['month'] ?? ''}'.trim();
      final parsed = RegExp(r'^(\d{4})-(\d{2})').firstMatch(m);
      if (parsed != null && month0 != null) {
        month = monthIndexOf(
            DateTime(int.parse(parsed.group(1)!), int.parse(parsed.group(2)!), 1),
            month0);
      }
      return GapPlacement(
        newWorkPackageId: wp,
        newName: name.split(RegExp(r'\s+')).take(8).join(' '),
        newMonth: month,
        rationale: rationale,
        source: 'ai',
      );
    }
  }
  return null;
}
