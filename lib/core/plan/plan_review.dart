/// "Review my plan": is the plan in a sensible order, and is anything
/// obviously missing? Two layers. The deterministic checks are graph
/// facts — arrows that point backwards in time, rows nothing connects
/// to, milestones nothing feeds, work packages with no milestone, a hard
/// deadline nothing leads to. The model then reads the whole WBS and
/// says what it would reorder, insert, or mark as a milestone; every
/// suggestion is validated against real ids and offered as a card. Pure
/// Dart: findings and prompts in, nothing written here.
library;

import '../database/database.dart';
import 'replan.dart' show replanMonthLabel;
import 'replan_assist.dart' show firstJsonObject;

enum FindingSeverity { warn, info }

/// One deterministic observation about the plan.
class PlanFinding {
  final FindingSeverity severity;
  final String code;
  final String message;
  final List<String> activityIds;
  const PlanFinding({
    required this.severity,
    required this.code,
    required this.message,
    this.activityIds = const [],
  });
}

const _kPoints = {'milestone', 'hard_deadline', 'gate'};

String _span(TimelineActivity a, DateTime? month0) {
  if (a.startMonth == null) return 'unscheduled';
  if (month0 == null) return 'M${a.startMonth}–M${a.endMonth ?? a.startMonth}';
  final s = replanMonthLabel(a.startMonth!, month0);
  final e = replanMonthLabel(a.endMonth ?? a.startMonth!, month0);
  return s == e ? s : '$s–$e';
}

/// Runs the graph checks. Cascaded rows and tasks are left to their
/// owners; checks run over the project's own top-level rows.
List<PlanFinding> checkPlan({
  required List<TimelineActivity> activities,
  required List<TimelineDependency> dependencies,
  required List<TimelineWorkPackage> workPackages,
  required String? month0Date,
  String? hardDeadlineDate,
}) {
  final month0 = month0Date != null ? DateTime.tryParse(month0Date) : null;
  final rows = activities
      .where((a) => a.sourceProjectId == null && a.parentActivityId == null)
      .toList();
  final byId = {for (final a in rows) a.id: a};
  final internal = dependencies
      .where((d) =>
          d.dependencyType != 'external' &&
          byId.containsKey(d.fromActivityId) &&
          byId.containsKey(d.toActivityId))
      .toList();
  final external = dependencies
      .where((d) => d.dependencyType == 'external' && byId.containsKey(d.toActivityId))
      .toList();
  final out = <PlanFinding>[];

  if (rows.isEmpty) {
    return const [
      PlanFinding(
          severity: FindingSeverity.info,
          code: 'empty',
          message: 'The plan has no activities yet.'),
    ];
  }

  // 1. Arrows that point backwards in time.
  for (final d in internal) {
    final from = byId[d.fromActivityId]!;
    final to = byId[d.toActivityId]!;
    if (from.startMonth == null || to.startMonth == null) continue;
    final fs = from.startMonth!, fe = from.endMonth ?? fs;
    final ts = to.startMonth!, te = to.endMonth ?? ts;
    final bad = switch (d.dependencyType) {
      'start_to_start' => ts < fs,
      'finish_to_finish' => te < fe,
      _ => ts < fe,
    };
    if (bad) {
      out.add(PlanFinding(
        severity: FindingSeverity.warn,
        code: 'backwards_arrow',
        message: '${to.name} (${_span(to, month0)}) starts before '
            '${from.name} (${_span(from, month0)}) ${d.dependencyType == 'start_to_start' ? 'starts' : 'ends'}, '
            'but the arrow says it must wait. Re-plan will push it.',
        activityIds: [from.id, to.id],
      ));
    }
  }

  // 2. Nothing connects to it.
  final linked = <String>{
    for (final d in internal) ...[d.fromActivityId, d.toActivityId],
    for (final d in external) d.toActivityId,
  };
  if (internal.isEmpty && rows.length > 1) {
    out.add(const PlanFinding(
      severity: FindingSeverity.info,
      code: 'no_arrows',
      message: 'No dependency arrows at all. Without them Re-plan cannot '
          'push work that is gated, and the critical path means nothing.',
    ));
  } else {
    final isolated = rows
        .where((a) => a.activityType == 'activity' && !linked.contains(a.id))
        .toList();
    if (isolated.isNotEmpty) {
      out.add(PlanFinding(
        severity: FindingSeverity.info,
        code: 'isolated',
        message: '${isolated.length} ${isolated.length == 1 ? 'activity has' : 'activities have'} '
            'no arrows in or out: ${isolated.take(5).map((a) => a.name).join(', ')}'
            '${isolated.length > 5 ? '…' : ''}.',
        activityIds: isolated.map((a) => a.id).toList(),
      ));
    }
  }

  // 3. Milestones and gates nothing feeds.
  final fedInto = <String>{for (final d in [...internal, ...external]) d.toActivityId};
  for (final a in rows.where((a) => _kPoints.contains(a.activityType))) {
    if (!fedInto.contains(a.id)) {
      out.add(PlanFinding(
        severity: FindingSeverity.warn,
        code: 'orphan_point',
        message: '${a.name} is a ${a.activityType.replaceAll('_', ' ')} '
            '(${_span(a, month0)}) that nothing leads to. Which work has to '
            'finish for it to be met?',
        activityIds: [a.id],
      ));
    }
  }

  // 4. Work packages with work but no end point.
  for (final w in workPackages) {
    final inWp = rows.where((a) => a.workPackageId == w.id).toList();
    if (inWp.isEmpty) continue;
    if (!inWp.any((a) => _kPoints.contains(a.activityType))) {
      out.add(PlanFinding(
        severity: FindingSeverity.info,
        code: 'wp_no_point',
        message: 'Work package "${w.name}" has ${inWp.length} '
            '${inWp.length == 1 ? 'row' : 'rows'} but no milestone or gate '
            'marking what "done" looks like.',
      ));
    }
  }

  // 5. The hard deadline, if any, has nothing leading to it.
  if ((hardDeadlineDate ?? '').isNotEmpty &&
      !rows.any((a) => a.activityType == 'hard_deadline')) {
    out.add(PlanFinding(
      severity: FindingSeverity.warn,
      code: 'deadline_not_on_plan',
      message: 'The plan header names a hard deadline ($hardDeadlineDate) '
          'but no row of type hard deadline exists, so nothing can be '
          'traced to it.',
    ));
  }

  // 6. Unscheduled rows.
  final unscheduled = rows.where((a) => a.startMonth == null).toList();
  if (unscheduled.isNotEmpty) {
    out.add(PlanFinding(
      severity: FindingSeverity.info,
      code: 'unscheduled',
      message: '${unscheduled.length} ${unscheduled.length == 1 ? 'row has' : 'rows have'} '
          'no month: ${unscheduled.take(5).map((a) => a.name).join(', ')}'
          '${unscheduled.length > 5 ? '…' : ''}.',
      activityIds: unscheduled.map((a) => a.id).toList(),
    ));
  }

  out.sort((x, y) => x.severity.index.compareTo(y.severity.index));
  return out;
}

// ─── AI review ───────────────────────────────────────────────────────────

enum SuggestionKind { reorder, missing, point }

/// One thing the model would change, validated against real ids.
class PlanSuggestion {
  final SuggestionKind kind;
  final String message;

  /// For reorder: the row that should come first. For missing/point:
  /// the row the new one follows (may be null).
  final String? afterId;

  /// For reorder: the row that should wait. For missing/point: the row
  /// the new one precedes (may be null).
  final String? beforeId;

  /// For missing/point: where the new row goes and what it is called.
  final String? workPackageId;
  final String? name;

  /// 'activity' | 'milestone' | 'gate'
  final String type;

  const PlanSuggestion({
    required this.kind,
    required this.message,
    this.afterId,
    this.beforeId,
    this.workPackageId,
    this.name,
    this.type = 'activity',
  });

  bool get createsRow => kind != SuggestionKind.reorder;
}

class PlanReviewPrompt {
  final String system;
  final String user;
  const PlanReviewPrompt({required this.system, required this.user});
}

const int kPlanReviewMaxRows = 150;
const int kPlanReviewMaxSuggestions = 8;

const String _kPersona =
    'You are reviewing a delivery plan with an experienced programme '
    'manager\'s eye. You will be shown the whole work breakdown: work '
    'packages, their activities in order, each activity\'s window, status '
    'and what it depends on. Judge three things: whether the order of '
    'the work is sensible for this kind of delivery; which commonly '
    'needed steps are absent; where a milestone or gate is missing. '
    'Be specific and sparing — at most $kPlanReviewMaxSuggestions suggestions, the ones that '
    'matter. Use only the ids listed; never invent ids. Answer ONLY with '
    'a single JSON object and nothing else.';

PlanReviewPrompt planReviewPrompt({
  required List<TimelineActivity> activities,
  required List<TimelineDependency> dependencies,
  required List<TimelineWorkPackage> workPackages,
  required DateTime? month0,
  List<PlanFinding> findings = const [],
  String? projectContext,
}) {
  final rows = activities
      .where((a) => a.sourceProjectId == null && a.parentActivityId == null)
      .toList();
  final byId = {for (final a in rows) a.id: a};
  final preds = <String, List<String>>{};
  for (final d in dependencies) {
    if (d.dependencyType == 'external') {
      preds.putIfAbsent(d.toActivityId, () => []).add('external: ${d.externalLabel ?? '?'}');
    } else if (byId.containsKey(d.fromActivityId)) {
      preds.putIfAbsent(d.toActivityId, () => []).add(d.fromActivityId);
    }
  }
  final b = StringBuffer()
    ..writeln('Work breakdown (work package → rows in plan order).')
    ..writeln('Row format: id | type | name | window | status | depends on');
  var written = 0;
  for (final w in workPackages) {
    final inWp = rows.where((a) => a.workPackageId == w.id).toList()
      ..sort((x, y) => x.sortOrder.compareTo(y.sortOrder));
    if (inWp.isEmpty) continue;
    b.writeln('\n## ${w.name} (id ${w.id})');
    for (final a in inWp) {
      if (written++ >= kPlanReviewMaxRows) break;
      b.writeln('${a.id} | ${a.activityType.replaceAll('_', ' ')} | ${a.name} | '
          '${_span(a, month0)} | ${a.status.replaceAll('_', ' ')} | '
          '${(preds[a.id] ?? const []).join(', ')}');
    }
  }
  if (rows.length > kPlanReviewMaxRows) {
    b.writeln('\n(${rows.length - kPlanReviewMaxRows} more rows not shown.)');
  }
  if (findings.isNotEmpty) {
    b.writeln('\nAlready known (do not repeat):');
    for (final f in findings) {
      b.writeln('- ${f.message}');
    }
  }
  b
    ..writeln('\nReply with exactly this JSON:')
    ..writeln('{"suggestions": [')
    ..writeln('  {"kind": "reorder", "first_id": "<id>", "then_id": "<id>", "message": "<why>"},')
    ..writeln('  {"kind": "missing", "work_package_id": "<id>", "name": "<new activity, at most 8 words>", '
        '"after_id": "<id or null>", "before_id": "<id or null>", "message": "<why>"},')
    ..writeln('  {"kind": "point", "work_package_id": "<id>", "name": "<milestone or gate name>", '
        '"type": "milestone" | "gate", "after_id": "<id or null>", "message": "<why>"}')
    ..writeln(']}')
    ..write('Order suggestions by importance. An empty list is a fine answer '
        'for a sound plan.');
  return PlanReviewPrompt(
    system: projectContext == null || projectContext.trim().isEmpty
        ? _kPersona
        : '$projectContext\n\n---\n\n$_kPersona',
    user: b.toString(),
  );
}

/// Parses and validates the model's suggestions. Unknown ids drop the
/// suggestion; a reorder that already has an arrow is dropped too.
List<PlanSuggestion> parsePlanSuggestions(
  String raw, {
  required Set<String> activityIds,
  required Set<String> workPackageIds,
  required List<TimelineDependency> dependencies,
}) {
  final obj = firstJsonObject(raw);
  final list = obj?['suggestions'];
  if (list is! List) return const [];
  String? id(dynamic v) => v is String && activityIds.contains(v) ? v : null;
  final out = <PlanSuggestion>[];
  for (final e in list) {
    if (e is! Map) continue;
    final kind = '${e['kind'] ?? ''}'.trim();
    final message = '${e['message'] ?? ''}'.trim();
    if (message.isEmpty) continue;
    switch (kind) {
      case 'reorder':
        final first = id(e['first_id']);
        final then = id(e['then_id']);
        if (first == null || then == null || first == then) continue;
        final exists = dependencies.any(
            (d) => d.fromActivityId == first && d.toActivityId == then);
        if (exists) continue;
        out.add(PlanSuggestion(
            kind: SuggestionKind.reorder, message: message,
            afterId: first, beforeId: then));
      case 'missing':
      case 'point':
        final wp = e['work_package_id'];
        final name = '${e['name'] ?? ''}'.trim();
        if (wp is! String || !workPackageIds.contains(wp) || name.isEmpty) continue;
        final type = kind == 'point'
            ? ('${e['type'] ?? 'milestone'}' == 'gate' ? 'gate' : 'milestone')
            : 'activity';
        out.add(PlanSuggestion(
          kind: kind == 'point' ? SuggestionKind.point : SuggestionKind.missing,
          message: message,
          afterId: id(e['after_id']),
          beforeId: id(e['before_id']),
          workPackageId: wp,
          name: name.split(RegExp(r'\s+')).take(8).join(' '),
          type: type,
        ));
      default:
        continue;
    }
    if (out.length == kPlanReviewMaxSuggestions) break;
  }
  return out;
}

/// The month a new row should land in: just after what it follows, else
/// just before what it precedes, else null (unscheduled).
int? suggestedMonth(PlanSuggestion s, Map<String, TimelineActivity> byId) {
  final after = s.afterId != null ? byId[s.afterId!] : null;
  if (after?.startMonth != null) return after!.endMonth ?? after.startMonth;
  final before = s.beforeId != null ? byId[s.beforeId!] : null;
  if (before?.startMonth != null) return before!.startMonth;
  return null;
}
