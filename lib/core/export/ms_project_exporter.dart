import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../database/database.dart';
import '../plan/plan_note_markers.dart';
import '../plan/variance_links.dart';
import '../platform/web_download.dart';
import 'ms_project_checks.dart';
import 'ms_project_state.dart';

/// Exports the Plan as a Microsoft Project XML file (the MSPDI format),
/// which desktop Project opens directly through File ▸ Open — no import
/// wizard, no field mapping. Keel is the source of truth: the file is
/// written so Project shows every bar where Keel has it, with nothing to
/// correct by hand.
///
/// Shape of the file:
///   Work package → summary task (outline level 1)
///   Activity     → task (level 2); a parent activity with tasks becomes a
///                  summary, its Keel commitment window kept as a Deadline
///   Task         → task (level 3)
///   Milestones, gates, hard deadlines and dependency markers → milestones,
///   unless Keel gives them a multi-month window: then they are bars.
///
/// Dates. Keel plans in months with optional day-precise dates. A month-only
/// span runs from the first working day of its start month (08:00) to the
/// last working day of its end month (17:00) on a Monday–Friday calendar
/// written into the file. A month-only milestone sits at the END of its
/// month — the "by" reading. Every leaf carries a Start-No-Earlier-Than
/// constraint on its Keel start (or, with "pin dates", is manually
/// scheduled), so Project keeps the dates as planned.
///
/// Assignments. Each owner is a resource assigned to their leaf tasks with
/// the assignment's own Start, Finish and Work written out. Project
/// schedules an assignment that lacks them from the PROJECT start and then
/// drags the task to fit — the cause of bars landing on 1 April.
///
/// Links. Keel's arrows become predecessor links with zero lag, only where
/// Keel's dates already satisfy them. A link the dates contradict (normal
/// at month grain — "design ends Jul, review starts Jul") is left out and
/// listed, never bent to fit with a negative lag. A link on a summary row
/// is re-pointed to its first child (incoming) or last child (outgoing).
///
/// UIDs come from [MsProjectState], so a row keeps its UID across exports.
///
/// The element ORDER inside Project, Task, Resource, Assignment and
/// Baseline follows the MSPDI schema sequence. Project rejects a file whose
/// children are out of sequence, so keep new elements in schema order; the
/// self-check in ms_project_checks.dart enforces it.
class MsProjectExport {
  final String xml;

  /// Non-fatal findings for the reader: links left out or re-pointed,
  /// children outside their parent's window, skipped rows, a missing
  /// anchor.
  final List<String> warnings;

  /// Self-check failures. Any here and the file is not saved.
  final List<String> errors;

  final MsChangeSummary changes;

  /// UIDs (and the snapshot of this export) to store once the file is
  /// saved.
  final MsProjectState state;

  const MsProjectExport({
    required this.xml,
    required this.warnings,
    this.errors = const [],
    this.changes = const MsChangeSummary(since: null),
    this.state = MsProjectState.empty,
  });

  bool get ok => errors.isEmpty;
}

/// How Keel's own notes travel.
enum MsNotesMode {
  /// What people wrote, contributors and external dependencies. Re-plan
  /// history, AI commentary and Keel's explanatory lines stay out.
  publicOnly,

  /// Everything, including Keel's history and explanations.
  all,
}

class MsProjectOptions {
  /// Write leaves as manually scheduled (Manual=1 with ManualStart /
  /// ManualFinish / ManualDuration): Project cannot move anything. Off =
  /// auto-scheduled with Start-No-Earlier-Than constraints.
  final bool pinDates;
  final MsNotesMode notes;
  final bool includeResources;
  final bool includeCustomFields;

  const MsProjectOptions({
    this.pinDates = false,
    this.notes = MsNotesMode.publicOnly,
    this.includeResources = true,
    this.includeCustomFields = true,
  });
}

/// The export refused to write a file because its self-check failed.
class MsProjectExportRefused implements Exception {
  final List<String> errors;
  const MsProjectExportRefused(this.errors);

  @override
  String toString() =>
      'The Microsoft Project file failed Keel\'s own check, so it was not '
      'saved:\n${errors.map((e) => '  • $e').join('\n')}';
}

/// Outcome of a saved export.
class MsProjectExportResult {
  final String message;
  final List<String> warnings;
  final MsChangeSummary changes;
  const MsProjectExportResult(this.message, this.warnings, this.changes);
}

class MsProjectExporter {
  static const _ns = 'http://schemas.microsoft.com/project';

  // Well-known custom field ids (Text1…Text5 step by 3).
  static const kText1 = 188743731;
  static const kText2 = 188743734;
  static const kText3 = 188743737;
  static const kText4 = 188743740;
  static const kText5 = 188743743;

  static const customFields = [
    (kText1, 'Text1', 'Keel status'),
    (kText2, 'Text2', 'Keel scenario'),
    (kText3, 'Text3', 'Keel owner'),
    (kText4, 'Text4', 'Keel ID'),
    (kText5, 'Text5', 'Keel remark'),
  ];

  /// Builds and self-checks the file. [now] is injectable for tests.
  /// Nothing is written to the database; see [export].
  static Future<MsProjectExport> build({
    required AppDatabase db,
    required String projectId,
    required String projectName,
    DateTime? now,
    MsProjectOptions options = const MsProjectOptions(),
    // Kept for callers that bisect an import error by switching blocks off.
    bool? includeResources,
    bool? includeCustomFields,
  }) async {
    final opts = MsProjectOptions(
      pinDates: options.pinDates,
      notes: options.notes,
      includeResources: includeResources ?? options.includeResources,
      includeCustomFields: includeCustomFields ?? options.includeCustomFields,
    );
    final at = now ?? DateTime.now();
    final dao = db.programmeGanttDao;
    final header = await dao.getHeader(projectId);
    final wps = await dao.getWorkPackages(projectId);
    final acts = await dao.getActivitiesForProject(projectId);
    final deps = await dao.getDependencies(projectId);
    final project = await db.projectDao.getProjectById(projectId);

    final raidRefById = <String, String>{};
    for (final r in await db.raidDao.getRisksForProject(projectId)) {
      raidRefById[r.id] = r.ref ?? 'Risk';
    }
    for (final a in await db.raidDao.getAssumptionsForProject(projectId)) {
      raidRefById[a.id] = a.ref ?? 'Assumption';
    }
    for (final i in await db.raidDao.getIssuesForProject(projectId)) {
      raidRefById[i.id] = i.ref ?? 'Issue';
    }
    for (final d in await db.raidDao.getDependenciesForProject(projectId)) {
      raidRefById[d.id] = d.ref ?? 'Dependency';
    }

    final previous = MsProjectState.decode(header?.msProjectState);
    final plan = buildMsProjectPlan(
      header: header,
      workPackages: wps,
      activities: acts,
      dependencies: deps,
      raidRefById: raidRefById,
      projectStartDate: project?.startDate,
      now: at,
      state: previous,
      notesMode: opts.notes,
      pinDates: opts.pinDates,
    );
    final xml = writeMsProjectXml(
      plan,
      title: header?.title ?? projectName,
      name: projectName,
      now: at,
      options: opts,
    );
    final errors = validateMsProjectXml(xml, options: opts);
    final snapshot = plan.snapshot(at);
    return MsProjectExport(
      xml: xml,
      warnings: plan.warnings,
      errors: errors,
      changes: diffSnapshots(previous.last, snapshot),
      state: plan.state.copyWith(last: snapshot),
    );
  }

  /// Builds, checks and saves the file, then remembers its UIDs and a
  /// snapshot for the next export's change summary. Throws
  /// [MsProjectExportRefused] when the self-check fails.
  static Future<MsProjectExportResult> export({
    required AppDatabase db,
    required String projectId,
    required String projectName,
    MsProjectOptions options = const MsProjectOptions(),
  }) async {
    final out = await build(
      db: db,
      projectId: projectId,
      projectName: projectName,
      options: options,
    );
    if (!out.ok) throw MsProjectExportRefused(out.errors);
    final slug = projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final message = await saveAndOpen(
      'ms_project_${slug}_$date.xml',
      utf8.encode(out.xml),
      mimeType: 'application/xml',
    );
    await saveState(db, projectId, out.state);
    return MsProjectExportResult(message, out.warnings, out.changes);
  }

  /// Stores [state] on the plan header, creating the header if the plan
  /// has none yet.
  static Future<void> saveState(
    AppDatabase db,
    String projectId,
    MsProjectState state,
  ) async {
    final dao = db.programmeGanttDao;
    final header = await dao.getHeader(projectId);
    await dao.upsertHeader(ProgrammeHeadersCompanion(
      id: Value(header?.id ?? const Uuid().v4()),
      projectId: Value(projectId),
      msProjectState: Value(state.encode()),
    ));
  }

  /// "Verify MS Project file": compares the XML Project saved against the
  /// plan as Keel would export it now. Empty = the .mpp matches Keel.
  static Future<List<String>> verify({
    required AppDatabase db,
    required String projectId,
    required String projectName,
    required String projectXml,
  }) async {
    final expected = await build(
      db: db,
      projectId: projectId,
      projectName: projectName,
    );
    return compareMsProjectFiles(
      expectedXml: expected.xml,
      actualXml: projectXml,
    );
  }
}

// ─── XML ────────────────────────────────────────────────────────────────────

/// Serialises [plan]. Public for tests.
String writeMsProjectXml(
  MsProjectPlan plan, {
  required String title,
  required String name,
  required DateTime now,
  MsProjectOptions options = const MsProjectOptions(),
}) {
  const ns = MsProjectExporter._ns;
  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  b.element('Project', nest: () {
    b.namespace(ns);
    void el(String tag, Object value) => b.element(tag, nest: value.toString());

    // Project-level fields, in schema order.
    el('SaveVersion', 14);
    el('Name', name);
    el('Title', title);
    el('CreationDate', msDate(now));
    el('LastSaved', msDate(now));
    el('ScheduleFromStart', 1);
    el('StartDate', msDate(plan.start));
    el('FinishDate', msDate(plan.finish));
    el('CalendarUID', 1);
    el('DefaultStartTime', '08:00:00');
    el('DefaultFinishTime', '17:00:00');
    el('MinutesPerDay', 480);
    el('MinutesPerWeek', 2400);
    el('DaysPerMonth', 20);
    el('DefaultTaskType', 0); // fixed units
    el('DurationFormat', 7); // days
    el('WorkFormat', 2); // hours
    el('HonorConstraints', 1);
    el('NewTasksEffortDriven', 0);
    el('NewTasksEstimated', 0);
    el('WeekStartDay', 1); // Monday
    el('CurrentDate', msDate(now));
    el('NewTaskStartDate', 0);
    el('NewTasksAreManual', 0);

    if (options.includeCustomFields) {
      b.element('ExtendedAttributes', nest: () {
        for (final (id, fname, alias) in MsProjectExporter.customFields) {
          b.element('ExtendedAttribute', nest: () {
            el('FieldID', id);
            el('FieldName', fname);
            el('Alias', alias);
          });
        }
      });
    }

    _writeCalendars(b);

    final assigned = options.includeResources
        ? {for (final a in plan.assignments) a.taskUid}
        : const <int>{};

    b.element('Tasks', nest: () {
      var id = 0;
      for (final t in plan.tasks) {
        id++;
        final leaf = !t.isSummary;
        final manual = options.pinDates && leaf;
        final dur = msDuration(t.durationHours);
        final done = t.percentComplete == 100;
        final work = assigned.contains(t.uid) ? t.durationHours : 0;
        b.element('Task', nest: () {
          el('UID', t.uid);
          el('ID', id); // row number; the UID is the stable identity
          el('Name', t.name);
          el('Active', 1);
          el('Manual', manual ? 1 : 0);
          el('Type', 0);
          el('IsNull', 0);
          el('CreateDate', msDate(now));
          el('WBS', t.outlineNumber);
          el('OutlineNumber', t.outlineNumber);
          el('OutlineLevel', t.outlineLevel);
          el('Priority', 500);
          el('Start', msDate(t.start));
          el('Finish', msDate(t.finish));
          el('Duration', dur);
          el('DurationFormat', 7);
          if (leaf) el('Work', msDuration(work));
          el('Milestone', t.isMilestone ? 1 : 0);
          el('Summary', t.isSummary ? 1 : 0);
          el('PercentComplete', t.percentComplete);
          if (leaf) el('PercentWorkComplete', t.percentComplete);
          if (done) {
            el('ActualStart', msDate(t.start));
            el('ActualFinish', msDate(t.finish));
          }
          if (leaf) {
            el('ActualDuration', done ? dur : msDuration(0));
            el('ActualWork', msDuration(done ? work : 0));
            el('RemainingDuration', done ? msDuration(0) : dur);
            el('RemainingWork', msDuration(done ? 0 : work));
          }
          final constraint = manual ? 0 : t.constraintType;
          el('ConstraintType', constraint);
          el('CalendarUID', -1);
          if (constraint != 0) el('ConstraintDate', msDate(t.start));
          if (t.deadline != null) el('Deadline', msDate(t.deadline!));
          if (t.notes.isNotEmpty) el('Notes', t.notes);
          for (final l in t.links) {
            b.element('PredecessorLink', nest: () {
              el('PredecessorUID', l.predecessorUid);
              el('Type', l.type);
              el('CrossProject', 0);
              el('LinkLag', 0);
              el('LagFormat', 7);
            });
          }
          if (options.includeCustomFields) {
            for (final (fid, value) in [
              (MsProjectExporter.kText1, t.statusLabel),
              (MsProjectExporter.kText2, t.scenarioText),
              (MsProjectExporter.kText3, t.owner),
              (MsProjectExporter.kText4, t.keelId),
              (MsProjectExporter.kText5, t.remark),
            ]) {
              if (value.isEmpty) continue;
              b.element('ExtendedAttribute', nest: () {
                el('FieldID', fid);
                el('Value', value);
              });
            }
          }
          final bl = t.baseline;
          if (bl != null) {
            b.element('Baseline', nest: () {
              el('Number', 0);
              el('Start', msDate(bl.start));
              el('Finish', msDate(bl.finish));
              el('Duration', msDuration(bl.durationHours));
              el('DurationFormat', 7);
            });
          }
          if (manual) {
            el('ManualStart', msDate(t.start));
            el('ManualFinish', msDate(t.finish));
            el('ManualDuration', dur);
          }
        });
      }
    });

    if (options.includeResources) {
      b.element('Resources', nest: () {
        var id = 0;
        for (final r in plan.resources) {
          b.element('Resource', nest: () {
            el('UID', r.uid);
            el('ID', ++id);
            el('Name', r.name);
            el('Type', 1); // work
            el('IsNull', 0);
            el('Initials', r.initials);
            el('MaxUnits', '1.00');
          });
        }
      });
      final byUid = {for (final t in plan.tasks) t.uid: t};
      b.element('Assignments', nest: () {
        for (final a in plan.assignments) {
          final t = byUid[a.taskUid]!;
          final work = t.durationHours; // units 1.0 over the whole span
          final done = t.percentComplete == 100;
          b.element('Assignment', nest: () {
            // One assignment per task, so the task's UID is stable for it.
            el('UID', a.taskUid);
            el('TaskUID', a.taskUid);
            el('ResourceUID', a.resourceUid);
            el('PercentWorkComplete', t.percentComplete);
            if (done) {
              el('ActualFinish', msDate(t.finish));
              el('ActualStart', msDate(t.start));
            }
            el('ActualWork', msDuration(done ? work : 0));
            el('Finish', msDate(t.finish));
            el('RemainingWork', msDuration(done ? 0 : work));
            el('Start', msDate(t.start));
            el('Units', '1.00');
            el('Work', msDuration(work));
          });
        }
      });
    }
  });
  // Pretty-print the structure but never touch text: a double space in a
  // name or a newline in Notes must reach Project exactly as written.
  return b.buildDocument().toXmlString(
        pretty: true,
        indent: '  ',
        preserveWhitespace: (node) =>
            node is XmlElement && node.children.every((c) => c is XmlText),
      );
}

/// The Standard calendar: Monday–Friday, 08:00–12:00 and 13:00–17:00.
/// DayType 1 is Sunday, 7 is Saturday.
void _writeCalendars(XmlBuilder b) {
  b.element('Calendars', nest: () {
    b.element('Calendar', nest: () {
      b.element('UID', nest: '1');
      b.element('Name', nest: 'Standard');
      b.element('IsBaseCalendar', nest: '1');
      b.element('BaseCalendarUID', nest: '-1');
      b.element('WeekDays', nest: () {
        for (var day = 1; day <= 7; day++) {
          final working = day >= 2 && day <= 6;
          b.element('WeekDay', nest: () {
            b.element('DayType', nest: '$day');
            b.element('DayWorking', nest: working ? '1' : '0');
            if (working) {
              b.element('WorkingTimes', nest: () {
                for (final (from, to) in const [
                  ('08:00:00', '12:00:00'),
                  ('13:00:00', '17:00:00'),
                ]) {
                  b.element('WorkingTime', nest: () {
                    b.element('FromTime', nest: from);
                    b.element('ToTime', nest: to);
                  });
                }
              });
            }
          });
        }
      });
    });
  });
}

// ─── Plan model ─────────────────────────────────────────────────────────────

class MsTask {
  final int uid;
  final String keelId;
  final String? parentKeelId;
  final String name;
  final String outlineNumber;
  final int outlineLevel;
  final DateTime start;
  final DateTime finish;
  final int durationHours;
  final bool isMilestone;
  final bool isSummary;
  final int percentComplete;
  /// 0 as soon as possible · 2 must start on · 4 start no earlier than.
  final int constraintType;
  final DateTime? deadline;
  final String notes;
  final String statusLabel;
  final String scenarioText;
  final String owner;
  /// Exporter remarks ("exported at the end of that month"): Text5, never
  /// Notes.
  final String remark;
  final MsBaseline? baseline;
  final List<MsLink> links;

  const MsTask({
    required this.uid,
    required this.keelId,
    this.parentKeelId,
    required this.name,
    required this.outlineNumber,
    required this.outlineLevel,
    required this.start,
    required this.finish,
    required this.durationHours,
    required this.isMilestone,
    required this.isSummary,
    required this.percentComplete,
    required this.constraintType,
    required this.deadline,
    required this.notes,
    required this.statusLabel,
    required this.scenarioText,
    this.owner = '',
    this.remark = '',
    this.baseline,
    required this.links,
  });
}

class MsBaseline {
  final DateTime start;
  final DateTime finish;
  final int durationHours;
  const MsBaseline(this.start, this.finish, this.durationHours);
}

class MsLink {
  final int predecessorUid;
  /// 0 finish-to-finish · 1 finish-to-start · 2 start-to-finish · 3 start-to-start.
  final int type;
  const MsLink(this.predecessorUid, this.type);
}

class MsResource {
  final int uid;
  final String name;
  const MsResource(this.uid, this.name);

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.map((p) => p[0].toUpperCase()).take(3).join();
  }
}

class MsAssignment {
  final int taskUid;
  final int resourceUid;
  const MsAssignment(this.taskUid, this.resourceUid);
}

class MsProjectPlan {
  final List<MsTask> tasks;
  final List<MsResource> resources;
  final List<MsAssignment> assignments;
  final DateTime start;
  final DateTime finish;
  final List<String> warnings;
  /// UIDs after this build (known rows kept theirs, new rows got new ones).
  final MsProjectState state;
  const MsProjectPlan({
    required this.tasks,
    required this.resources,
    required this.assignments,
    required this.start,
    required this.finish,
    required this.warnings,
    this.state = MsProjectState.empty,
  });

  MsTask? taskNamed(String name) =>
      tasks.cast<MsTask?>().firstWhere((t) => t!.name == name, orElse: () => null);

  MsExportSnapshot snapshot(DateTime at) => MsExportSnapshot(at, {
        for (final t in tasks)
          t.keelId: MsSnapshotRow(
            name: t.name,
            start: msDate(t.start),
            finish: msDate(t.finish),
            parent: t.parentKeelId,
            status: t.statusLabel,
          ),
      });
}

/// Ten minutes-tenths per working day: 480 minutes × 10.
const int kTenthsOfMinutesPerDay = 4800;
const int kHoursPerDay = 8;

const Map<String, String> kMsStatusLabels = {
  'not_started': 'Not started',
  'on_track': 'On track',
  'at_risk': 'At risk',
  'complete': 'Complete',
  'overdue': 'Overdue',
};

/// Turns Keel's plan rows into the task tree the writer serialises. Pure, so
/// the date and link maths are testable without a database.
MsProjectPlan buildMsProjectPlan({
  required ProgrammeHeader? header,
  required List<TimelineWorkPackage> workPackages,
  required List<TimelineActivity> activities,
  required List<TimelineDependency> dependencies,
  required Map<String, String> raidRefById,
  required String? projectStartDate,
  required DateTime now,
  MsProjectState state = MsProjectState.empty,
  MsNotesMode notesMode = MsNotesMode.publicOnly,
  bool pinDates = false,
}) {
  final warnings = <String>[];
  final publicOnly = notesMode == MsNotesMode.publicOnly;

  // Month-0 anchor: the header's, else the project start, else this month.
  final anchor =
      header?.month0Date != null ? DateTime.tryParse(header!.month0Date!) : null;
  final fallback =
      projectStartDate != null ? DateTime.tryParse(projectStartDate) : null;
  final base = anchor ?? fallback ?? now;
  final month0 = DateTime(base.year, base.month);
  if (anchor == null) {
    warnings.add(
      'The plan has no month-0 anchor (Plan ▸ header settings), so month '
      '0 was placed at ${_ymd(month0)}. Set the anchor and export again '
      'for true dates.',
    );
  }

  List<String> labels = const [];
  if (header?.monthLabels != null) {
    try {
      labels = (jsonDecode(header!.monthLabels!) as List).cast<String>();
    } catch (_) {}
  }
  String monthLabel(int m) =>
      m >= 0 && m < labels.length ? labels[m] : _monthName(monthStart(month0, m));

  final actsByWp = <String, List<TimelineActivity>>{};
  for (final a in activities) {
    actsByWp.putIfAbsent(a.workPackageId, () => []).add(a);
  }
  final externalByTarget = <String, List<String>>{};
  for (final d in dependencies) {
    if (d.externalLabel?.isNotEmpty ?? false) {
      externalByTarget.putIfAbsent(d.toActivityId, () => []).add(d.externalLabel!);
    }
  }

  // ── Pass 1: spans for every activity (dates win over months) ──────────
  final spans = <String, _Span>{};
  for (final a in activities) {
    final span = _spanFor(a, month0);
    if (span != null) spans[a.id] = span;
  }
  final childrenOf = <String, List<TimelineActivity>>{};
  for (final a in activities) {
    if (a.parentActivityId != null) {
      childrenOf.putIfAbsent(a.parentActivityId!, () => []).add(a);
    }
  }

  _Draft activityDraft(
    TimelineActivity a, {
    required String outline,
    required int level,
    required String parentKey,
    required bool summary,
  }) {
    final own = spans[a.id];
    final point = _isPointActivity(a);
    final remarks = <String>[];
    if (summary && own != null) {
      remarks.add('Keel commitment window: ${monthLabel(a.startMonth ?? 0)} – '
          '${monthLabel(a.endMonth ?? a.startMonth ?? 0)} (kept as the Deadline).');
    }
    if (!summary && a.startDate == null && a.startMonth != null) {
      if (point) {
        remarks.add('Keel places this in ${monthLabel(a.startMonth!)}; '
            'exported at the end of that month.');
      } else if (_isPointType(a.activityType)) {
        remarks.add('Keel window ${monthLabel(a.startMonth!)} – '
            '${monthLabel(a.endMonth!)}; exported as a bar.');
      }
    }
    return _Draft(
      key: a.id,
      parentKey: parentKey,
      name: a.name,
      outlineNumber: outline,
      level: level,
      span: summary ? null : own,
      window: summary ? own : null,
      summary: summary,
      milestone: !summary && point,
      constraintType: summary ? 0 : (a.activityType == 'hard_deadline' ? 2 : 4),
      deadline: summary
          ? own?.finish
          : (a.activityType == 'hard_deadline' ? own?.finish : null),
      notes: _notesFor(a, externalByTarget, publicOnly: publicOnly),
      remarks: remarks,
      statusLabel: kMsStatusLabels[a.status] ?? a.status,
      scenarioText: _scenarioText(a, raidRefById, monthLabel),
      percentComplete: a.status == 'complete' ? 100 : 0,
      owner: a.owner,
      baseline: summary ? null : _baselineFor(a, month0),
    );
  }

  // ── Pass 2: build the tree ────────────────────────────────────────────
  final tasks = <_Draft>[];
  final draftByActivityId = <String, _Draft>{};
  var wpNumber = 0;
  final skippedWps = <String>[];

  for (final wp in workPackages) {
    final wpActs = actsByWp[wp.id] ?? const [];
    final ordered = _wbsOrder(wpActs);
    final wpIds = {for (final a in wpActs) a.id};
    final members = ordered.where((a) => spans.containsKey(a.id) ||
        (childrenOf[a.id] ?? const []).any((c) => spans.containsKey(c.id)));
    if (members.isEmpty) {
      // A work package header alone: use its cascaded span if it has one.
      final cs = _cascadeSpan(wp, month0);
      if (cs == null) {
        skippedWps.add(wp.name);
        continue;
      }
      wpNumber++;
      tasks.add(_Draft(
        key: wp.id,
        name: _wpName(wp),
        outlineNumber: '$wpNumber',
        level: 1,
        span: cs,
        summary: false,
        milestone: false,
        constraintType: 4,
        notes: [
          if (wp.description?.isNotEmpty ?? false) wp.description!,
          if (!publicOnly && wp.sourceProjectId != null)
            'Cascaded from a linked project.',
        ],
      ));
      continue;
    }

    wpNumber++;
    tasks.add(_Draft(
      key: wp.id,
      name: _wpName(wp),
      outlineNumber: '$wpNumber',
      level: 1,
      span: null, // rolled up below
      summary: true,
      milestone: false,
      constraintType: 0,
      notes: [if (wp.description?.isNotEmpty ?? false) wp.description!],
    ));

    var actNumber = 0;
    for (final a in ordered) {
      // Tasks are emitted under their parent; orphans count as activities.
      if (a.parentActivityId != null && wpIds.contains(a.parentActivityId)) {
        continue;
      }
      final kids = (childrenOf[a.id] ?? const [])
          .where((c) => spans.containsKey(c.id))
          .toList();
      if (spans[a.id] == null && kids.isEmpty) continue;

      actNumber++;
      final d = activityDraft(a,
          outline: '$wpNumber.$actNumber',
          level: 2,
          parentKey: wp.id,
          summary: kids.isNotEmpty);
      tasks.add(d);
      draftByActivityId[a.id] = d;
      var taskNumber = 0;
      for (final c in kids) {
        taskNumber++;
        final cd = activityDraft(c,
            outline: '$wpNumber.$actNumber.$taskNumber',
            level: 3,
            parentKey: a.id,
            summary: false);
        tasks.add(cd);
        draftByActivityId[c.id] = cd;
      }
    }
  }

  // The plan's hard deadline, if it has a date, as a top-level milestone.
  if (header?.hardDeadlineDate != null) {
    final d = DateTime.tryParse(header!.hardDeadlineDate!);
    if (d != null) {
      final point = _Span.point(previousWorkingDay(d));
      wpNumber++;
      tasks.add(_Draft(
        key: 'hard-deadline:${header.id}',
        name: header.hardDeadline?.isNotEmpty == true
            ? header.hardDeadline!
            : 'Hard deadline',
        outlineNumber: '$wpNumber',
        level: 1,
        span: point,
        summary: false,
        milestone: true,
        constraintType: 2,
        deadline: point.finish,
        notes: const [],
        remarks: const ['The plan\'s hard deadline from Keel.'],
      ));
    }
  }

  if (skippedWps.isNotEmpty) {
    warnings.add(
      'Skipped ${skippedWps.length} work package'
      '${skippedWps.length == 1 ? '' : 's'} with no dated activities: '
      '${skippedWps.join(', ')}.',
    );
  }
  final undated = activities.where((a) => !spans.containsKey(a.id) &&
      !(childrenOf[a.id] ?? const []).any((c) => spans.containsKey(c.id)));
  if (undated.isNotEmpty) {
    warnings.add(
      'Skipped ${undated.length} activit${undated.length == 1 ? 'y' : 'ies'} '
      'with no month or date: ${undated.map((a) => a.name).join(', ')}.',
    );
  }

  // ── Pass 3: roll summaries up from their children ─────────────────────
  // Children follow their summary and have a deeper level, so walk back.
  for (var i = tasks.length - 1; i >= 0; i--) {
    final t = tasks[i];
    if (!t.summary) continue;
    DateTime? s, f, bs, bf;
    for (final c in _descendants(tasks, i)) {
      final cs = c.span;
      if (cs != null) {
        if (s == null || cs.start.isBefore(s)) s = cs.start;
        if (f == null || cs.finish.isAfter(f)) f = cs.finish;
      }
      final cb = c.baseline;
      if (cb != null) {
        if (bs == null || cb.start.isBefore(bs)) bs = cb.start;
        if (bf == null || cb.finish.isAfter(bf)) bf = cb.finish;
      }
    }
    t.span = (s != null && f != null) ? _Span(s, f) : _Span.point(month0);
    if (bs != null && bf != null) t.baseline = _Span(bs, bf);
  }

  // Children that run outside their parent's Keel window are exported as
  // they are, and listed.
  for (var i = 0; i < tasks.length; i++) {
    final w = tasks[i].window;
    if (w == null) continue;
    for (final c in _descendants(tasks, i)) {
      final cs = c.span!;
      final before = workingHoursPosition(cs.start) < workingHoursPosition(w.start);
      final after = workingHoursPosition(cs.finish) > workingHoursPosition(w.finish);
      if (!before && !after) continue;
      warnings.add('"${c.name}" (${_day(cs.start)} – ${_day(cs.finish)}) runs '
          '${before ? 'before' : 'past'} its parent "${tasks[i].name}"\'s Keel '
          'window (${_day(w.start)} – ${_day(w.finish)}); exported as Keel has it.');
    }
  }

  // ── Pass 4: links — zero lag where the dates agree, else left out ─────
  final linkTargets = <_Draft, List<(_Draft, int)>>{};
  var missingEnds = 0;
  final dropped = <String>[];
  for (final d in dependencies) {
    if (d.externalLabel?.isNotEmpty ?? false) continue;
    final pred0 = draftByActivityId[d.fromActivityId];
    final succ0 = draftByActivityId[d.toActivityId];
    if (pred0 == null || succ0 == null) {
      missingEnds++;
      continue;
    }
    // Project can't link a summary row: an outgoing link leaves from its
    // last child, an incoming one arrives at its first.
    final pred = _childEnd(tasks, pred0, last: true);
    final succ = _childEnd(tasks, succ0, last: false);
    if (pred == succ) continue;
    final type = switch (d.dependencyType) {
      'start_to_start' => 3,
      'finish_to_finish' => 0,
      _ => 1,
    };
    final repointed = pred != pred0 || succ != succ0;
    final via = repointed
        ? ' (re-pointed from "${pred0.name}" → "${succ0.name}", a summary row)'
        : '';
    final gap = linkGapHours(
      type: type,
      predecessorStart: pred.span!.start,
      predecessorFinish: pred.span!.finish,
      successorStart: succ.span!.start,
      successorFinish: succ.span!.finish,
    );
    if (gap < 0) {
      dropped.add(_contradiction(type, pred, succ) + via);
      continue;
    }
    final list = linkTargets.putIfAbsent(succ, () => []);
    if (list.any((l) => l.$1 == pred && l.$2 == type)) continue;
    // Two zero-gap links can point both ways (milestones on the same
    // 17:00); Project refuses a loop, so the closing link stays out.
    if (_reachesViaPredecessors(linkTargets, from: pred, target: succ)) {
      dropped.add('"${pred.name}" → "${succ.name}" would close a loop of links$via');
      continue;
    }
    list.add((pred, type));
    if (repointed) {
      warnings.add('Link "${pred0.name}" → "${succ0.name}" re-pointed to '
          '"${pred.name}" → "${succ.name}": Project cannot link summary rows.');
    }
  }
  if (dropped.isNotEmpty) {
    warnings.add('Left out ${dropped.length} link${dropped.length == 1 ? '' : 's'} '
        'that Keel\'s dates contradict (Project would move the successor) '
        'or that would loop:');
    warnings.addAll(dropped.map((d) => '  • $d'));
  }
  if (missingEnds > 0) {
    warnings.add('Dropped $missingEnds dependency arrow'
        '${missingEnds == 1 ? '' : 's'} whose activity is not in the file.');
  }

  // ── Pass 5: stable UIDs, then resources and assignments ───────────────
  final uids = MsUidAllocator(state);
  for (final t in tasks) {
    t.uid = uids.task(t.key);
  }

  final resources = <MsResource>[];
  final resourceUidByKey = <String, int>{};
  final assignments = <MsAssignment>[];
  for (final t in tasks) {
    final owner = t.owner?.trim();
    if (t.summary || owner == null || owner.isEmpty) continue;
    final key = owner.toLowerCase();
    final uid = resourceUidByKey.putIfAbsent(key, () {
      final u = uids.resource(key);
      resources.add(MsResource(u, owner));
      return u;
    });
    assignments.add(MsAssignment(t.uid, uid));
  }

  DateTime? start, finish;
  for (final t in tasks) {
    final s = t.span!;
    if (start == null || s.start.isBefore(start)) start = s.start;
    if (finish == null || s.finish.isAfter(finish)) finish = s.finish;
  }
  start ??= nextWorkingDay(month0).add(const Duration(hours: 8));
  finish ??= start.add(const Duration(hours: 9));

  return MsProjectPlan(
    tasks: [
      for (final t in tasks)
        MsTask(
          uid: t.uid,
          keelId: t.key,
          parentKeelId: t.parentKey,
          name: t.name,
          outlineNumber: t.outlineNumber,
          outlineLevel: t.level,
          start: t.span!.start,
          finish: t.span!.finish,
          durationHours: t.milestone ? 0 : t.span!.durationHours,
          isMilestone: t.milestone,
          isSummary: t.summary,
          // Project computes a summary's progress from its children, so a
          // complete parent must not carry its own actuals.
          percentComplete: t.summary ? 0 : t.percentComplete,
          constraintType: t.constraintType,
          deadline: t.deadline,
          notes: t.notes.join('\n'),
          statusLabel: t.statusLabel,
          scenarioText: t.scenarioText,
          owner: t.owner?.trim() ?? '',
          remark: t.remarks.join(' '),
          baseline: t.baseline == null
              ? null
              : MsBaseline(t.baseline!.start, t.baseline!.finish,
                  t.baseline!.durationHours),
          links: [
            for (final (p, type) in linkTargets[t] ?? const <(_Draft, int)>[])
              MsLink(p.uid, type),
          ],
        ),
    ],
    resources: resources,
    assignments: assignments,
    start: start,
    finish: finish,
    warnings: warnings,
    state: uids.state,
  );
}

class _Draft {
  int uid = 0;
  final String key;
  final String? parentKey;
  final String name;
  final String outlineNumber;
  final int level;
  _Span? span;
  /// A parent activity's own Keel window (its commitment).
  final _Span? window;
  final bool summary;
  final bool milestone;
  final int constraintType;
  final DateTime? deadline;
  final List<String> notes;
  final List<String> remarks;
  final String statusLabel;
  final String scenarioText;
  final int percentComplete;
  final String? owner;
  _Span? baseline;
  _Draft({
    required this.key,
    this.parentKey,
    required this.name,
    required this.outlineNumber,
    required this.level,
    required this.span,
    this.window,
    required this.summary,
    required this.milestone,
    required this.constraintType,
    this.deadline,
    required this.notes,
    this.remarks = const [],
    this.statusLabel = '',
    this.scenarioText = '',
    this.percentComplete = 0,
    this.owner,
    this.baseline,
  });
}

/// True when [target] is upstream of [from] through existing links.
bool _reachesViaPredecessors(
  Map<_Draft, List<(_Draft, int)>> predsOf, {
  required _Draft from,
  required _Draft target,
}) {
  final seen = <_Draft>{};
  final stack = [from];
  while (stack.isNotEmpty) {
    final d = stack.removeLast();
    if (d == target) return true;
    if (!seen.add(d)) continue;
    for (final (p, _) in predsOf[d] ?? const <(_Draft, int)>[]) {
      stack.add(p);
    }
  }
  return false;
}

Iterable<_Draft> _descendants(List<_Draft> tasks, int i) sync* {
  for (var j = i + 1; j < tasks.length && tasks[j].level > tasks[i].level; j++) {
    yield tasks[j];
  }
}

/// [d] itself, or for a summary the child a link should attach to: the
/// earliest-starting leaf (incoming) or the latest-finishing one
/// (outgoing). Ties go to outline order — first child in, last child out.
_Draft _childEnd(List<_Draft> tasks, _Draft d, {required bool last}) {
  if (!d.summary) return d;
  final i = tasks.indexOf(d);
  _Draft? best;
  for (final c in _descendants(tasks, i)) {
    if (c.summary) continue;
    if (best == null) {
      best = c;
    } else if (last) {
      if (!c.span!.finish.isBefore(best.span!.finish)) best = c;
    } else if (c.span!.start.isBefore(best.span!.start)) {
      best = c;
    }
  }
  return best ?? d;
}

String _contradiction(int type, _Draft p, _Draft s) => switch (type) {
      3 => 'start-to-start "${p.name}" → "${s.name}": "${s.name}" starts '
          '${_day(s.span!.start)}, before "${p.name}" starts ${_day(p.span!.start)}',
      0 => 'finish-to-finish "${p.name}" → "${s.name}": "${s.name}" finishes '
          '${_day(s.span!.finish)}, before "${p.name}" finishes ${_day(p.span!.finish)}',
      _ => 'finish-to-start "${p.name}" → "${s.name}": "${s.name}" starts '
          '${_day(s.span!.start)}, before "${p.name}" finishes ${_day(p.span!.finish)}',
    };

String _day(DateTime d) => msDayLabel(msDate(d));

/// A working-time span: [start] at 08:00 on a working day, [finish] at
/// 17:00 on a working day on or after it. A point (milestone) has both at
/// 17:00 on the same day.
class _Span {
  final DateTime start;
  final DateTime finish;
  const _Span(this.start, this.finish);

  factory _Span.days(DateTime firstDay, DateTime lastDay) {
    var s = nextWorkingDay(firstDay);
    var f = previousWorkingDay(lastDay);
    if (f.isBefore(s)) f = s;
    return _Span(
      DateTime(s.year, s.month, s.day, 8),
      DateTime(f.year, f.month, f.day, 17),
    );
  }

  factory _Span.point(DateTime day) {
    final d = previousWorkingDay(day);
    final at = DateTime(d.year, d.month, d.day, 17);
    return _Span(at, at);
  }

  bool get isPoint => start == finish;

  int get durationHours =>
      isPoint ? 0 : workingHoursPosition(finish) - workingHoursPosition(start);
}

bool _isPointType(String type) =>
    type == 'milestone' ||
    type == 'hard_deadline' ||
    type == 'gate' ||
    type == 'dependency_marker';

/// A point in time — unless Keel gives a milestone-like row a window that
/// runs past its first month (or past its start date): then it is a bar.
/// A hard deadline is always a point.
bool _isPointActivity(TimelineActivity a) {
  if (!_isPointType(a.activityType)) return false;
  if (a.activityType == 'hard_deadline') return true;
  final sd = a.startDate != null ? DateTime.tryParse(a.startDate!) : null;
  if (sd != null) {
    final ed = a.endDate != null ? DateTime.tryParse(a.endDate!) : null;
    return ed == null || !ed.isAfter(sd);
  }
  final s = a.startMonth, e = a.endMonth;
  return s == null || e == null || e <= s;
}

_Span? _spanFor(TimelineActivity a, DateTime month0) {
  final sd = a.startDate != null ? DateTime.tryParse(a.startDate!) : null;
  final ed = a.endDate != null ? DateTime.tryParse(a.endDate!) : null;
  if (_isPointActivity(a)) {
    final day = sd ??
        (a.startMonth != null ? monthEnd(month0, a.startMonth!) : null);
    return day == null ? null : _Span.point(day);
  }
  final first = sd ?? (a.startMonth != null ? monthStart(month0, a.startMonth!) : null);
  if (first == null) return null;
  final last = ed ??
      (a.endMonth != null
          ? monthEnd(month0, a.endMonth!)
          : (a.startMonth != null ? monthEnd(month0, a.startMonth!) : first));
  return _Span.days(first, last.isBefore(first) ? first : last);
}

/// Keel's baseline is month-grained (baselineStart / baselineEnd); it maps
/// to dates by the same rule as the live months.
_Span? _baselineFor(TimelineActivity a, DateTime month0) {
  if (!a.isBaseline || a.baselineStart == null) return null;
  final s = a.baselineStart!;
  final e = a.baselineEnd ?? s;
  final point = _isPointType(a.activityType) &&
      (a.activityType == 'hard_deadline' || e <= s);
  if (point) return _Span.point(monthEnd(month0, s));
  return _Span.days(monthStart(month0, s), monthEnd(month0, e < s ? s : e));
}

_Span? _cascadeSpan(TimelineWorkPackage wp, DateTime month0) {
  final sd = wp.cascadeStartDate != null ? DateTime.tryParse(wp.cascadeStartDate!) : null;
  final ed = wp.cascadeEndDate != null ? DateTime.tryParse(wp.cascadeEndDate!) : null;
  if (sd != null) return _Span.days(sd, ed ?? sd);
  if (wp.cascadeStartMonth != null) {
    return _Span.days(
      monthStart(month0, wp.cascadeStartMonth!),
      monthEnd(month0, wp.cascadeEndMonth ?? wp.cascadeStartMonth!),
    );
  }
  return null;
}

String _wpName(TimelineWorkPackage wp) =>
    (wp.shortCode?.isNotEmpty ?? false) ? '${wp.shortCode}  ${wp.name}' : wp.name;

/// Notes as they travel. Public: what a person wrote (minus Keel's
/// re-plan history, AI commentary and plan-review stamps), contributors
/// and external dependencies. All: Keel's history and explanations too.
List<String> _notesFor(
  TimelineActivity a,
  Map<String, List<String>> externalByTarget, {
  required bool publicOnly,
}) {
  final out = <String>[];
  final own = (a.notes ?? '')
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .where((l) => !publicOnly || !isKeelGeneratedNoteLine(l))
      .join('\n');
  if (own.isNotEmpty) out.add(own);
  if (a.contributors?.isNotEmpty ?? false) {
    try {
      final names = (jsonDecode(a.contributors!) as List).cast<String>();
      if (names.isNotEmpty) out.add('Contributors: ${names.join(', ')}');
    } catch (_) {}
  }
  for (final label in externalByTarget[a.id] ?? const []) {
    out.add('External dependency: $label');
  }
  if (!publicOnly) {
    if (a.isCritical) out.add('Marked critical in Keel.');
    if (a.activityType == 'ongoing') out.add('Ongoing / recurring work in Keel.');
    if (a.sourceProjectId != null) out.add('Cascaded from a linked project.');
  }
  return out;
}

String _scenarioText(
  TimelineActivity a,
  Map<String, String> raidRefById,
  String Function(int) monthLabel,
) {
  if (a.likelyMonth == null && a.safeMonth == null) return '';
  final parts = <String>[
    if (a.startMonth != null) 'Anchor ${monthLabel(a.startMonth!)}',
    if (a.likelyMonth != null) 'Likely ${monthLabel(a.likelyMonth!)}',
    if (a.safeMonth != null) 'Safe ${monthLabel(a.safeMonth!)}',
  ];
  final links = effectiveVarianceLinks(
    linksJson: a.varianceRaidLinksJson,
    legacyType: a.varianceRaidType,
    legacyId: a.varianceRaidId,
  );
  final refs = [
    for (final l in links)
      if (raidRefById[l.id] != null) raidRefById[l.id]!,
  ];
  if (refs.isNotEmpty) parts.add('Driven by ${refs.join(', ')}');
  return parts.join(' · ');
}

/// Keeps a parent activity's tasks right after it; an orphan whose parent
/// is missing is promoted to a top-level activity rather than nested under
/// whichever row happens to precede it.
List<TimelineActivity> _wbsOrder(List<TimelineActivity> acts) {
  final ids = {for (final a in acts) a.id};
  final byParent = <String, List<TimelineActivity>>{};
  final roots = <TimelineActivity>[];
  for (final a in acts) {
    if (a.parentActivityId != null && ids.contains(a.parentActivityId)) {
      byParent.putIfAbsent(a.parentActivityId!, () => []).add(a);
    } else {
      roots.add(a);
    }
  }
  final ordered = <TimelineActivity>[];
  for (final a in roots) {
    ordered.add(a);
    ordered.addAll(byParent[a.id] ?? const []);
  }
  return ordered;
}

// ─── Working-day maths (pure) ───────────────────────────────────────────────

/// First day of month [index] counted from [month0].
DateTime monthStart(DateTime month0, int index) =>
    DateTime(month0.year, month0.month + index, 1);

/// Last day of month [index] counted from [month0].
DateTime monthEnd(DateTime month0, int index) =>
    DateTime(month0.year, month0.month + index + 1, 0);

bool isWorkingDay(DateTime d) =>
    d.weekday != DateTime.saturday && d.weekday != DateTime.sunday;

// Day stepping is done in UTC so a daylight-saving change can never turn
// "plus one day" into 23 hours and land on the wrong calendar day.
DateTime _utcDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);
DateTime _localDay(DateTime utc) => DateTime(utc.year, utc.month, utc.day);

/// [d] itself if it is a working day, else the following Monday.
DateTime nextWorkingDay(DateTime d) {
  var day = _utcDay(d);
  while (!isWorkingDay(day)) {
    day = day.add(const Duration(days: 1));
  }
  return _localDay(day);
}

/// [d] itself if it is a working day, else the preceding Friday.
DateTime previousWorkingDay(DateTime d) {
  var day = _utcDay(d);
  while (!isWorkingDay(day)) {
    day = day.subtract(const Duration(days: 1));
  }
  return _localDay(day);
}

final DateTime _epochMonday = DateTime.utc(2000, 1, 3);

/// Ordinal of [d]'s working day since a fixed Monday, so that the number
/// of working days between two working days is the difference.
int workingDayIndex(DateTime d) {
  final days = _utcDay(d).difference(_epochMonday).inDays;
  final weeks = days ~/ 7;
  final rem = days - weeks * 7;
  return weeks * 5 + (rem < 5 ? rem : 5);
}

/// Position of a span end in working hours: a start sits at 08:00 (the
/// beginning of its working day), a finish at 17:00 (the end). Two
/// DateTimes with the same position are the same instant in working time
/// (Friday 17:00 and Monday 08:00, say), which is how Project compares
/// them when it applies a link.
int workingHoursPosition(DateTime t) =>
    workingDayIndex(t) * kHoursPerDay + (t.hour >= 17 ? kHoursPerDay : 0);

/// Working hours from the end a link measures on the predecessor to the
/// end it constrains on the successor, by Project's rule per type:
/// FS succ.start ≥ pred.finish; SS succ.start ≥ pred.start;
/// FF succ.finish ≥ pred.finish. Zero or more = Keel's dates satisfy the
/// link with no lag; negative = they contradict it.
int linkGapHours({
  required int type,
  required DateTime predecessorStart,
  required DateTime predecessorFinish,
  required DateTime successorStart,
  required DateTime successorFinish,
}) {
  final (from, to) = switch (type) {
    3 => (predecessorStart, successorStart),
    0 => (predecessorFinish, successorFinish),
    _ => (predecessorFinish, successorStart),
  };
  return workingHoursPosition(to) - workingHoursPosition(from);
}

/// Adds [hours] of working time to [t] on the Mon–Fri 08:00–17:00 calendar
/// (lunch ignored: Project's lag arithmetic works in whole working days
/// here). Used by tests to replay Project's "predecessor + lag" rule.
DateTime addWorkingHours(DateTime t, int hours) {
  var pos = workingHoursPosition(t) + hours;
  // Convert back: day index and whether we land at the end of a day.
  var dayIdx = pos ~/ kHoursPerDay;
  var rem = pos - dayIdx * kHoursPerDay;
  if (rem < 0) {
    dayIdx -= 1;
    rem += kHoursPerDay;
  }
  final day = _dayForWorkingIndex(dayIdx);
  return DateTime(day.year, day.month, day.day, rem == 0 ? 8 : 17);
}

DateTime _dayForWorkingIndex(int idx) {
  final weeks = idx ~/ 5;
  final rem = idx - weeks * 5;
  return _localDay(_epochMonday.add(Duration(days: weeks * 7 + rem)));
}

String msDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}T${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String msDuration(int hours) => 'PT${hours}H0M0S';

String _ymd(DateTime d) => msDate(d).substring(0, 10);

String _monthName(DateTime d) {
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${names[d.month - 1]} ${d.year % 100}';
}
