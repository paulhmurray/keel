import 'dart:convert';

import 'package:xml/xml.dart';

import '../database/database.dart';
import '../plan/variance_links.dart';
import '../platform/web_download.dart';

/// Exports the Plan as a Microsoft Project XML file (the MSPDI format),
/// which desktop Project opens directly through File ▸ Open — no import
/// wizard, no field mapping.
///
/// Shape of the file:
///   Work package → summary task (outline level 1)
///   Activity     → task (level 2); a parent activity with tasks becomes a
///                  summary, its Keel commitment window kept as a Deadline
///   Task         → task (level 3)
///   Milestones, gates, hard deadlines and dependency markers → milestones
///
/// Dates. Keel plans in months with optional day-precise dates. A month-only
/// span runs from the first working day of its start month (08:00) to the
/// last working day of its end month (17:00) on a Monday–Friday calendar
/// written into the file. A month-only milestone sits at the END of its
/// month — the "by" reading. Every leaf carries a Start-No-Earlier-Than
/// constraint on its Keel start, so Project keeps the dates as planned.
///
/// Links. Keel's finish-to-start / start-to-start / finish-to-finish arrows
/// become predecessor links. Where Keel has a successor starting before its
/// predecessor finishes (normal at month grain — "design ends Jul, review
/// starts Jul"), the link carries a negative lag so Project computes the
/// same start Keel shows instead of pushing the successor out.
///
/// The element ORDER inside Project, Task, Resource and Assignment follows
/// the MSPDI schema sequence, checked against files written by Project 2019.
/// Project rejects a file whose children are out of sequence, so keep new
/// elements in schema order.
class MsProjectExport {
  final String xml;

  /// Things the reader should know about the file: skipped rows, the anchor
  /// used when the plan had none, and so on.
  final List<String> warnings;

  const MsProjectExport(this.xml, this.warnings);
}

class MsProjectExporter {
  static const _ns = 'http://schemas.microsoft.com/project';

  // Well-known custom field ids.
  static const _kText1 = 188743731;
  static const _kText2 = 188743734;

  /// Builds the file. [now] is injectable for tests. [includeResources] and
  /// [includeCustomFields] let a reader who hits an import error bisect the
  /// file by switching blocks off.
  static Future<MsProjectExport> build({
    required AppDatabase db,
    required String projectId,
    required String projectName,
    DateTime? now,
    bool includeResources = true,
    bool includeCustomFields = true,
  }) async {
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

    final plan = buildMsProjectPlan(
      header: header,
      workPackages: wps,
      activities: acts,
      dependencies: deps,
      raidRefById: raidRefById,
      projectStartDate: project?.startDate,
      now: now ?? DateTime.now(),
    );
    final xml = _writeXml(
      plan,
      title: header?.title ?? projectName,
      name: projectName,
      now: now ?? DateTime.now(),
      includeResources: includeResources,
      includeCustomFields: includeCustomFields,
    );
    return MsProjectExport(xml, plan.warnings);
  }

  /// Builds and saves the file; returns the save message and the warnings.
  static Future<(String, List<String>)> export({
    required AppDatabase db,
    required String projectId,
    required String projectName,
  }) async {
    final out = await build(db: db, projectId: projectId, projectName: projectName);
    final slug = projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final message = await saveAndOpen(
      'ms_project_${slug}_$date.xml',
      utf8.encode(out.xml),
      mimeType: 'application/xml',
    );
    return (message, out.warnings);
  }

  // ─── XML ──────────────────────────────────────────────────────────────────

  static String _writeXml(
    MsProjectPlan plan, {
    required String title,
    required String name,
    required DateTime now,
    required bool includeResources,
    required bool includeCustomFields,
  }) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    b.element('Project', nest: () {
      b.namespace(_ns);
      void el(String tag, Object value) =>
          b.element(tag, nest: value.toString());

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

      if (includeCustomFields) {
        b.element('ExtendedAttributes', nest: () {
          for (final (id, fname, alias) in const [
            (_kText1, 'Text1', 'Keel status'),
            (_kText2, 'Text2', 'Keel scenario'),
          ]) {
            b.element('ExtendedAttribute', nest: () {
              el('FieldID', id);
              el('FieldName', fname);
              el('Alias', alias);
            });
          }
        });
      }

      _writeCalendars(b);

      b.element('Tasks', nest: () {
        for (final t in plan.tasks) {
          b.element('Task', nest: () {
            el('UID', t.uid);
            el('ID', t.uid);
            el('Name', t.name);
            el('Active', 1);
            el('Manual', 0);
            el('Type', 0);
            el('IsNull', 0);
            el('CreateDate', msDate(now));
            el('WBS', t.outlineNumber);
            el('OutlineNumber', t.outlineNumber);
            el('OutlineLevel', t.outlineLevel);
            el('Priority', 500);
            el('Start', msDate(t.start));
            el('Finish', msDate(t.finish));
            el('Duration', msDuration(t.durationHours));
            el('DurationFormat', 7);
            el('Milestone', t.isMilestone ? 1 : 0);
            el('Summary', t.isSummary ? 1 : 0);
            el('PercentComplete', t.percentComplete);
            if (t.percentComplete == 100) {
              el('ActualStart', msDate(t.start));
              el('ActualFinish', msDate(t.finish));
            }
            el('ConstraintType', t.constraintType);
            el('CalendarUID', -1);
            if (t.constraintType != 0) {
              el('ConstraintDate', msDate(t.start));
            }
            if (t.deadline != null) el('Deadline', msDate(t.deadline!));
            if (t.notes.isNotEmpty) el('Notes', t.notes);
            for (final l in t.links) {
              b.element('PredecessorLink', nest: () {
                el('PredecessorUID', l.predecessorUid);
                el('Type', l.type);
                el('CrossProject', 0);
                el('LinkLag', l.lagTenthsOfMinutes);
                el('LagFormat', 7);
              });
            }
            if (includeCustomFields) {
              for (final (id, value) in [
                (_kText1, t.statusLabel),
                (_kText2, t.scenarioText),
              ]) {
                if (value.isEmpty) continue;
                b.element('ExtendedAttribute', nest: () {
                  el('FieldID', id);
                  el('Value', value);
                });
              }
            }
          });
        }
      });

      if (includeResources) {
        b.element('Resources', nest: () {
          for (final r in plan.resources) {
            b.element('Resource', nest: () {
              el('UID', r.uid);
              el('ID', r.uid);
              el('Name', r.name);
              el('Type', 1); // work
              el('IsNull', 0);
              el('Initials', r.initials);
              el('MaxUnits', '1.00');
            });
          }
        });
        b.element('Assignments', nest: () {
          var uid = 1;
          for (final a in plan.assignments) {
            b.element('Assignment', nest: () {
              el('UID', uid++);
              el('TaskUID', a.taskUid);
              el('ResourceUID', a.resourceUid);
              el('Units', '1.00');
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
  static void _writeCalendars(XmlBuilder b) {
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
}

// ─── Plan model ─────────────────────────────────────────────────────────────

class MsTask {
  final int uid;
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
  final List<MsLink> links;

  const MsTask({
    required this.uid,
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
    required this.links,
  });
}

class MsLink {
  final int predecessorUid;
  /// 0 finish-to-finish · 1 finish-to-start · 2 start-to-finish · 3 start-to-start.
  final int type;
  /// Negative for a lead (overlap); Project stores lag in tenths of a minute.
  final int lagTenthsOfMinutes;
  const MsLink(this.predecessorUid, this.type, this.lagTenthsOfMinutes);

  int get lagDays => lagTenthsOfMinutes ~/ kTenthsOfMinutesPerDay;
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
  const MsProjectPlan({
    required this.tasks,
    required this.resources,
    required this.assignments,
    required this.start,
    required this.finish,
    required this.warnings,
  });

  MsTask? taskNamed(String name) =>
      tasks.cast<MsTask?>().firstWhere((t) => t!.name == name, orElse: () => null);
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
/// the date and lag maths are testable without a database.
MsProjectPlan buildMsProjectPlan({
  required ProgrammeHeader? header,
  required List<TimelineWorkPackage> workPackages,
  required List<TimelineActivity> activities,
  required List<TimelineDependency> dependencies,
  required Map<String, String> raidRefById,
  required String? projectStartDate,
  required DateTime now,
}) {
  final warnings = <String>[];

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
  // Summary span of a parent = roll-up of its children's spans.
  final childrenOf = <String, List<TimelineActivity>>{};
  for (final a in activities) {
    if (a.parentActivityId != null) {
      childrenOf.putIfAbsent(a.parentActivityId!, () => []).add(a);
    }
  }

  // ── Pass 2: build the tree ────────────────────────────────────────────
  final tasks = <_Draft>[];
  final uidByActivityId = <String, int>{};
  var nextUid = 1;
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
        uid: nextUid++,
        name: _wpName(wp),
        outlineNumber: '$wpNumber',
        level: 1,
        span: cs,
        summary: false,
        milestone: false,
        constraintType: 4,
        notes: [
          if (wp.description?.isNotEmpty ?? false) wp.description!,
          if (wp.sourceProjectId != null) 'Cascaded from a linked project.',
        ],
      ));
      continue;
    }

    wpNumber++;
    final wpDraft = _Draft(
      uid: nextUid++,
      name: _wpName(wp),
      outlineNumber: '$wpNumber',
      level: 1,
      span: null, // rolled up below
      summary: true,
      milestone: false,
      constraintType: 0,
      notes: [if (wp.description?.isNotEmpty ?? false) wp.description!],
    );
    tasks.add(wpDraft);

    var actNumber = 0;
    for (final a in ordered) {
      // Tasks are emitted under their parent; orphans count as activities.
      if (a.parentActivityId != null && wpIds.contains(a.parentActivityId)) {
        continue;
      }
      final kids = (childrenOf[a.id] ?? const [])
          .where((c) => spans.containsKey(c.id))
          .toList();
      final own = spans[a.id];
      if (own == null && kids.isEmpty) continue;

      actNumber++;
      final actUid = nextUid++;
      uidByActivityId[a.id] = actUid;
      final isSummary = kids.isNotEmpty;
      final notes = _notesFor(a, raidRefById, externalByTarget, monthLabel);
      if (isSummary && own != null) {
        notes.insert(
          0,
          'Keel commitment window: ${monthLabel(a.startMonth ?? 0)} – '
          '${monthLabel(a.endMonth ?? a.startMonth ?? 0)} (kept as the Deadline).',
        );
      }
      tasks.add(_Draft(
        uid: actUid,
        name: a.name,
        outlineNumber: '$wpNumber.$actNumber',
        level: 2,
        span: isSummary ? null : own,
        summary: isSummary,
        milestone: !isSummary && _isPoint(a.activityType),
        constraintType: isSummary ? 0 : (a.activityType == 'hard_deadline' ? 2 : 4),
        deadline: isSummary
            ? own?.finish
            : (a.activityType == 'hard_deadline' ? own?.finish : null),
        notes: notes,
        statusLabel: kMsStatusLabels[a.status] ?? a.status,
        scenarioText: _scenarioText(a, raidRefById, monthLabel),
        percentComplete: a.status == 'complete' ? 100 : 0,
        owner: a.owner,
        activityId: a.id,
      ));
      var taskNumber = 0;
      for (final c in kids) {
        taskNumber++;
        final cUid = nextUid++;
        uidByActivityId[c.id] = cUid;
        tasks.add(_Draft(
          uid: cUid,
          name: c.name,
          outlineNumber: '$wpNumber.$actNumber.$taskNumber',
          level: 3,
          span: spans[c.id],
          summary: false,
          milestone: _isPoint(c.activityType),
          constraintType: c.activityType == 'hard_deadline' ? 2 : 4,
          deadline: c.activityType == 'hard_deadline' ? spans[c.id]!.finish : null,
          notes: _notesFor(c, raidRefById, externalByTarget, monthLabel),
          statusLabel: kMsStatusLabels[c.status] ?? c.status,
          scenarioText: _scenarioText(c, raidRefById, monthLabel),
          percentComplete: c.status == 'complete' ? 100 : 0,
          owner: c.owner,
          activityId: c.id,
        ));
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
        uid: nextUid++,
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
        notes: const ['The plan\'s hard deadline from Keel.'],
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
    DateTime? s, f;
    for (var j = i + 1; j < tasks.length && tasks[j].level > t.level; j++) {
      final c = tasks[j].span;
      if (c == null) continue;
      if (s == null || c.start.isBefore(s)) s = c.start;
      if (f == null || c.finish.isAfter(f)) f = c.finish;
    }
    t.span = (s != null && f != null) ? _Span(s, f) : _Span.point(month0);
  }

  // ── Pass 4: links, with a lead where Keel overlaps ────────────────────
  final linksByUid = <int, List<MsLink>>{};
  var droppedLinks = 0;
  final draftByUid = {for (final t in tasks) t.uid: t};
  for (final d in dependencies) {
    if (d.externalLabel?.isNotEmpty ?? false) continue;
    final from = uidByActivityId[d.fromActivityId];
    final to = uidByActivityId[d.toActivityId];
    if (from == null || to == null || from == to) {
      droppedLinks++;
      continue;
    }
    final pred = draftByUid[from]!;
    final succ = draftByUid[to]!;
    if (pred.summary || succ.summary) {
      // Project refuses links on summary tasks; keep the fact in the notes.
      succ.notes.add('Keel link from "${pred.name}" (summary rows cannot be linked).');
      continue;
    }
    final type = switch (d.dependencyType) {
      'start_to_start' => 3,
      'finish_to_finish' => 0,
      _ => 1,
    };
    final lag = _linkLagDays(
      type: type,
      predecessor: pred.span!,
      successor: succ.span!,
    );
    linksByUid.putIfAbsent(to, () => []).add(
      MsLink(from, type, lag * kTenthsOfMinutesPerDay),
    );
  }
  if (droppedLinks > 0) {
    warnings.add('Dropped $droppedLinks dependency arrow'
        '${droppedLinks == 1 ? '' : 's'} whose activity is not in the file.');
  }

  // ── Resources: one per distinct owner, assigned on leaves ─────────────
  final resources = <MsResource>[];
  final resourceUidByKey = <String, int>{};
  final assignments = <MsAssignment>[];
  for (final t in tasks) {
    final owner = t.owner?.trim();
    if (t.summary || owner == null || owner.isEmpty) continue;
    final key = owner.toLowerCase();
    final uid = resourceUidByKey.putIfAbsent(key, () {
      resources.add(MsResource(resources.length + 1, owner));
      return resources.length;
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
          statusLabel: t.summary ? '' : t.statusLabel,
          scenarioText: t.scenarioText,
          links: linksByUid[t.uid] ?? const [],
        ),
    ],
    resources: resources,
    assignments: assignments,
    start: start,
    finish: finish,
    warnings: warnings,
  );
}

class _Draft {
  final int uid;
  final String name;
  final String outlineNumber;
  final int level;
  _Span? span;
  final bool summary;
  final bool milestone;
  final int constraintType;
  final DateTime? deadline;
  final List<String> notes;
  final String statusLabel;
  final String scenarioText;
  final int percentComplete;
  final String? owner;
  final String? activityId;
  _Draft({
    required this.uid,
    required this.name,
    required this.outlineNumber,
    required this.level,
    required this.span,
    required this.summary,
    required this.milestone,
    required this.constraintType,
    this.deadline,
    required this.notes,
    this.statusLabel = '',
    this.scenarioText = '',
    this.percentComplete = 0,
    this.owner,
    this.activityId,
  });
}

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
      isPoint ? 0 : (workingDayIndex(finish) - workingDayIndex(start) + 1) * kHoursPerDay;
}

bool _isPoint(String type) =>
    type == 'milestone' ||
    type == 'hard_deadline' ||
    type == 'gate' ||
    type == 'dependency_marker';

_Span? _spanFor(TimelineActivity a, DateTime month0) {
  final point = _isPoint(a.activityType);
  final sd = a.startDate != null ? DateTime.tryParse(a.startDate!) : null;
  final ed = a.endDate != null ? DateTime.tryParse(a.endDate!) : null;
  if (point) {
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

List<String> _notesFor(
  TimelineActivity a,
  Map<String, String> raidRefById,
  Map<String, List<String>> externalByTarget,
  String Function(int) monthLabel,
) {
  final out = <String>[];
  if (a.notes?.isNotEmpty ?? false) out.add(a.notes!);
  if (a.contributors?.isNotEmpty ?? false) {
    try {
      final names = (jsonDecode(a.contributors!) as List).cast<String>();
      if (names.isNotEmpty) out.add('Contributors: ${names.join(', ')}');
    } catch (_) {}
  }
  for (final label in externalByTarget[a.id] ?? const []) {
    out.add('External dependency: $label');
  }
  if (a.isCritical) out.add('Marked critical in Keel.');
  if (a.activityType == 'ongoing') out.add('Ongoing / recurring work in Keel.');
  if (a.sourceProjectId != null) out.add('Cascaded from a linked project.');
  if (a.startDate == null && a.startMonth != null && _isPoint(a.activityType)) {
    out.add('Keel places this in ${monthLabel(a.startMonth!)}; '
        'exported at the end of that month.');
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

/// Lag in working days for a link so that Project computes the successor
/// where Keel put it. Zero when the successor already starts after the
/// predecessor finishes (the gap is a planning choice, not a lag — the
/// constraint holds the date); negative (a lead) when they overlap.
///
/// Project's rule per type: FS succ.start ≥ pred.finish + lag;
/// SS succ.start ≥ pred.start + lag; FF succ.finish ≥ pred.finish + lag.
int _linkLagDays({
  required int type,
  required _Span predecessor,
  required _Span successor,
}) {
  final (from, to) = switch (type) {
    3 => (predecessor.start, successor.start),
    0 => (predecessor.finish, successor.finish),
    _ => (predecessor.finish, successor.start),
  };
  final gapHours = workingHoursPosition(to) - workingHoursPosition(from);
  if (gapHours >= 0) return 0;
  return gapHours ~/ kHoursPerDay;
}

/// Lag maths exposed for tests without the private span type.
int linkLagDaysFor({
  required int type,
  required DateTime predecessorStart,
  required DateTime predecessorFinish,
  required DateTime successorStart,
  required DateTime successorFinish,
}) =>
    _linkLagDays(
      type: type,
      predecessor: _Span(predecessorStart, predecessorFinish),
      successor: _Span(successorStart, successorFinish),
    );

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
