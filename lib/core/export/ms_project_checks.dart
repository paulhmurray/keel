import 'package:xml/xml.dart';

import '../plan/plan_note_markers.dart';
import 'ms_project_exporter.dart';
import 'ms_project_state.dart';

/// Trust checks for the Microsoft Project export:
///
/// * [validateMsProjectXml] re-reads the file Keel just wrote and lists
///   every rule it breaks. The export refuses to save a file that fails.
/// * [compareMsProjectFiles] compares the XML that Project saves (File ▸
///   Save As ▸ XML) with what Keel would export now, task by task. An
///   empty result means the .mpp shows the plan as Keel has it.

// ─── Reading MSPDI ──────────────────────────────────────────────────────────

class MsFileLink {
  final int predecessorUid;
  final int type;
  final int lag; // tenths of a minute
  const MsFileLink(this.predecessorUid, this.type, this.lag);
}

class MsFileTask {
  final int uid;
  final int? id;
  final String name;
  final int outlineLevel;
  final DateTime? start;
  final DateTime? finish;
  final int? durationMinutes;
  final int? workMinutes;
  final bool milestone;
  final bool summary;
  final bool manual;
  final int percentComplete;
  final int constraintType;
  final String notes;
  final DateTime? manualStart;
  final DateTime? manualFinish;
  final int? manualDurationMinutes;
  final List<MsFileLink> links;
  final Map<int, String> ext;
  final List<(DateTime?, DateTime?, int?)> baselines; // Number 0 only
  final List<String> childOrder;

  const MsFileTask({
    required this.uid,
    required this.id,
    required this.name,
    required this.outlineLevel,
    required this.start,
    required this.finish,
    required this.durationMinutes,
    required this.workMinutes,
    required this.milestone,
    required this.summary,
    required this.manual,
    required this.percentComplete,
    required this.constraintType,
    required this.notes,
    required this.manualStart,
    required this.manualFinish,
    required this.manualDurationMinutes,
    required this.links,
    required this.ext,
    required this.baselines,
    required this.childOrder,
  });

  String get keelId => ext[MsProjectExporter.kText4] ?? '';
  String get label => '"$name" (UID $uid)';
}

class MsFileAssignment {
  final int taskUid;
  final int resourceUid;
  final DateTime? start;
  final DateTime? finish;
  final int? workMinutes;
  final int? actualWorkMinutes;
  final int? remainingWorkMinutes;
  final int? percentWorkComplete;
  final List<String> childOrder;
  const MsFileAssignment({
    required this.taskUid,
    required this.resourceUid,
    required this.start,
    required this.finish,
    required this.workMinutes,
    required this.actualWorkMinutes,
    required this.remainingWorkMinutes,
    required this.percentWorkComplete,
    required this.childOrder,
  });
}

class MsFile {
  final String saveVersion;
  final DateTime? start;
  final DateTime? finish;
  final List<String> rootOrder;
  final List<MsFileTask> tasks; // UID 0 (the project summary row) left out
  final Map<int, String> resources;
  final List<MsFileAssignment> assignments;

  const MsFile({
    required this.saveVersion,
    required this.start,
    required this.finish,
    required this.rootOrder,
    required this.tasks,
    required this.resources,
    required this.assignments,
  });

  /// Reads an MSPDI document. Unknown elements are ignored, so it reads
  /// both Keel's own file and the much fuller one Project saves.
  factory MsFile.parse(String xml) {
    final root = XmlDocument.parse(xml).rootElement;
    String? txt(XmlElement e, String tag) => e.getElement(tag)?.innerText;
    int? intOf(XmlElement e, String tag) {
      final v = txt(e, tag);
      return v == null ? null : int.tryParse(v.trim());
    }

    DateTime? dateOf(XmlElement e, String tag) {
      final v = txt(e, tag);
      return v == null ? null : DateTime.tryParse(v.trim());
    }

    final tasks = <MsFileTask>[];
    for (final t in root.getElement('Tasks')?.findElements('Task') ?? const <XmlElement>[]) {
      final uid = intOf(t, 'UID') ?? -1;
      if (uid == 0) continue;
      if (txt(t, 'IsNull') == '1') continue;
      tasks.add(MsFileTask(
        uid: uid,
        id: intOf(t, 'ID'),
        name: txt(t, 'Name') ?? '',
        outlineLevel: intOf(t, 'OutlineLevel') ?? 0,
        start: dateOf(t, 'Start'),
        finish: dateOf(t, 'Finish'),
        durationMinutes: parseMsDurationMinutes(txt(t, 'Duration')),
        workMinutes: parseMsDurationMinutes(txt(t, 'Work')),
        milestone: txt(t, 'Milestone') == '1',
        summary: txt(t, 'Summary') == '1',
        manual: txt(t, 'Manual') == '1',
        percentComplete: intOf(t, 'PercentComplete') ?? 0,
        constraintType: intOf(t, 'ConstraintType') ?? 0,
        notes: txt(t, 'Notes') ?? '',
        manualStart: dateOf(t, 'ManualStart'),
        manualFinish: dateOf(t, 'ManualFinish'),
        manualDurationMinutes: parseMsDurationMinutes(txt(t, 'ManualDuration')),
        links: [
          for (final l in t.findElements('PredecessorLink'))
            MsFileLink(
              intOf(l, 'PredecessorUID') ?? -1,
              intOf(l, 'Type') ?? 1,
              intOf(l, 'LinkLag') ?? 0,
            ),
        ],
        ext: {
          for (final e in t.findElements('ExtendedAttribute'))
            if (intOf(e, 'FieldID') != null) intOf(e, 'FieldID')!: txt(e, 'Value') ?? '',
        },
        baselines: [
          for (final b in t.findElements('Baseline'))
            if ((intOf(b, 'Number') ?? 0) == 0)
              (dateOf(b, 'Start'), dateOf(b, 'Finish'),
                  parseMsDurationMinutes(txt(b, 'Duration'))),
        ],
        childOrder: [for (final c in t.childElements) c.name.local],
      ));
    }

    final resources = <int, String>{};
    for (final r in root.getElement('Resources')?.findElements('Resource') ?? const <XmlElement>[]) {
      final uid = intOf(r, 'UID');
      final name = txt(r, 'Name');
      if (uid != null && uid > 0 && name != null) resources[uid] = name;
    }

    final assignments = <MsFileAssignment>[];
    for (final a in root.getElement('Assignments')?.findElements('Assignment') ?? const <XmlElement>[]) {
      final res = intOf(a, 'ResourceUID') ?? -65535;
      if (res < 0) continue; // Project's "unassigned" placeholder
      assignments.add(MsFileAssignment(
        taskUid: intOf(a, 'TaskUID') ?? -1,
        resourceUid: res,
        start: dateOf(a, 'Start'),
        finish: dateOf(a, 'Finish'),
        workMinutes: parseMsDurationMinutes(txt(a, 'Work')),
        actualWorkMinutes: parseMsDurationMinutes(txt(a, 'ActualWork')),
        remainingWorkMinutes: parseMsDurationMinutes(txt(a, 'RemainingWork')),
        percentWorkComplete: intOf(a, 'PercentWorkComplete'),
        childOrder: [for (final c in a.childElements) c.name.local],
      ));
    }

    return MsFile(
      saveVersion: txt(root, 'SaveVersion') ?? '',
      start: dateOf(root, 'StartDate'),
      finish: dateOf(root, 'FinishDate'),
      rootOrder: [for (final c in root.childElements) c.name.local],
      tasks: tasks,
      resources: resources,
      assignments: assignments,
    );
  }
}

/// "PT184H0M0S" → 11040; "PT1.5H…" and Project's elapsed forms are
/// rounded. Null when absent or unreadable.
int? parseMsDurationMinutes(String? v) {
  if (v == null) return null;
  final m = RegExp(r'^-?PT(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?$')
      .firstMatch(v.trim());
  if (m == null) return null;
  final h = double.parse(m.group(1) ?? '0');
  final mi = double.parse(m.group(2) ?? '0');
  final s = double.parse(m.group(3) ?? '0');
  return (h * 60 + mi + s / 60).round();
}

// ─── Schema order (from the MSPDI schema's sequences) ──────────────────────

const kMsProjectRootOrder = [
  'SaveVersion', 'Name', 'Title', 'CreationDate', 'LastSaved',
  'ScheduleFromStart', 'StartDate', 'FinishDate', 'CalendarUID',
  'DefaultStartTime', 'DefaultFinishTime', 'MinutesPerDay', 'MinutesPerWeek',
  'DaysPerMonth', 'DefaultTaskType', 'DurationFormat', 'WorkFormat',
  'HonorConstraints', 'NewTasksEffortDriven', 'NewTasksEstimated',
  'WeekStartDay', 'CurrentDate', 'NewTaskStartDate', 'NewTasksAreManual',
  'ExtendedAttributes', 'Calendars', 'Tasks', 'Resources', 'Assignments',
];

const kMsTaskOrder = [
  'UID', 'ID', 'Name', 'Active', 'Manual', 'Type', 'IsNull', 'CreateDate',
  'WBS', 'OutlineNumber', 'OutlineLevel', 'Priority', 'Start', 'Finish',
  'Duration', 'DurationFormat', 'Work', 'Milestone', 'Summary',
  'PercentComplete', 'PercentWorkComplete', 'ActualStart', 'ActualFinish',
  'ActualDuration', 'ActualWork', 'RemainingDuration', 'RemainingWork',
  'ConstraintType', 'CalendarUID', 'ConstraintDate', 'Deadline', 'Notes',
  'PredecessorLink', 'ExtendedAttribute', 'Baseline', 'ManualStart',
  'ManualFinish', 'ManualDuration',
];

const kMsAssignmentOrder = [
  'UID', 'TaskUID', 'ResourceUID', 'PercentWorkComplete', 'ActualFinish',
  'ActualStart', 'ActualWork', 'Finish', 'RemainingWork', 'Start', 'Units',
  'Work',
];

const kMsBaselineOrder = ['Number', 'Start', 'Finish', 'Duration', 'DurationFormat'];

/// First element of [names] out of [order]'s sequence (or not in it).
String? _orderProblem(List<String> names, List<String> order) {
  var last = -1;
  for (final n in names) {
    final i = order.indexOf(n);
    if (i < 0) return '<$n> is not an element Keel writes here';
    if (i < last) return '<$n> is out of schema order';
    last = i;
  }
  return null;
}

// ─── A. Self-check ──────────────────────────────────────────────────────────

/// Every rule the file Keel just wrote breaks, as readable sentences.
List<String> validateMsProjectXml(
  String xml, {
  MsProjectOptions options = const MsProjectOptions(),
}) {
  final errors = <String>[];
  late final MsFile f;
  try {
    f = MsFile.parse(xml);
  } catch (e) {
    return ['The file is not well-formed XML: $e'];
  }
  final doc = XmlDocument.parse(xml).rootElement;

  if (f.saveVersion != '14') {
    errors.add('SaveVersion is "${f.saveVersion}", expected 14 (MSPDI as '
        'desktop Project 2010 and later read it).');
  }
  final rootProblem = _orderProblem(f.rootOrder, kMsProjectRootOrder);
  if (rootProblem != null) errors.add('Project: $rootProblem.');

  // Identity and outline.
  final byUid = <int, MsFileTask>{};
  final keelIds = <String>{};
  var lastLevel = 0;
  for (var i = 0; i < f.tasks.length; i++) {
    final t = f.tasks[i];
    if (byUid.containsKey(t.uid)) errors.add('UID ${t.uid} is used twice.');
    byUid[t.uid] = t;
    if (t.id != i + 1) errors.add('${t.label}: ID ${t.id}, expected ${i + 1}.');
    if (t.outlineLevel < 1 || t.outlineLevel > lastLevel + 1) {
      errors.add('${t.label}: outline level ${t.outlineLevel} skips a level.');
    }
    lastLevel = t.outlineLevel;
    final orderProblem = _orderProblem(t.childOrder, kMsTaskOrder);
    if (orderProblem != null) errors.add('${t.label}: $orderProblem.');
    if (options.includeCustomFields) {
      if (t.keelId.isEmpty) {
        errors.add('${t.label}: no Keel ID in Text4.');
      } else if (!keelIds.add(t.keelId)) {
        errors.add('${t.label}: Keel ID ${t.keelId} appears twice.');
      }
    }
  }
  for (final b in doc.findAllElements('Baseline')) {
    final names = [for (final c in b.childElements) c.name.local];
    final p = _orderProblem(names, kMsBaselineOrder);
    if (p != null) errors.add('Baseline: $p.');
  }

  final projectStart = f.start;
  final projectFinish = f.finish;

  for (var i = 0; i < f.tasks.length; i++) {
    final t = f.tasks[i];
    final s = t.start, fin = t.finish;
    if (s == null || fin == null) {
      errors.add('${t.label}: missing Start or Finish.');
      continue;
    }
    // Calendar: working days, 08:00 starts and 17:00 finishes (a
    // milestone sits at 17:00).
    for (final (what, d) in [('Start', s), ('Finish', fin)]) {
      if (!isWorkingDay(d)) {
        errors.add('${t.label}: $what ${msDate(d)} is not a working day.');
      }
    }
    if (t.milestone) {
      if (s != fin || s.hour != 17 || s.minute != 0) {
        errors.add('${t.label}: a milestone must start and finish at the '
            'same 17:00 (has ${msDate(s)} – ${msDate(fin)}).');
      }
    } else {
      if (s.hour != 8 || s.minute != 0) {
        errors.add('${t.label}: Start ${msDate(s)} is not at 08:00.');
      }
      if (fin.hour != 17 || fin.minute != 0) {
        errors.add('${t.label}: Finish ${msDate(fin)} is not at 17:00.');
      }
    }
    if (fin.isBefore(s)) errors.add('${t.label}: finishes before it starts.');
    if (projectStart != null && s.isBefore(projectStart)) {
      errors.add('${t.label}: starts ${msDate(s)}, before the project start '
          '${msDate(projectStart)}.');
    }
    if (projectFinish != null && fin.isAfter(projectFinish)) {
      errors.add('${t.label}: finishes ${msDate(fin)}, after the project '
          'finish ${msDate(projectFinish)}.');
    }
    final working = (workingHoursPosition(fin) - workingHoursPosition(s)) * 60;
    final expectMinutes = t.milestone ? 0 : working;
    if (t.durationMinutes != expectMinutes) {
      errors.add('${t.label}: Duration ${_h(t.durationMinutes)} does not '
          'match the ${_h(expectMinutes)} of working time from '
          '${msDate(s)} to ${msDate(fin)}.');
    }
    if (t.milestone && (t.workMinutes ?? 0) != 0) {
      errors.add('${t.label}: a milestone carries work ${_h(t.workMinutes)}.');
    }

    // Summaries: no links, a date range covering their children.
    if (t.summary) {
      if (t.links.isNotEmpty) errors.add('${t.label}: a summary row has links.');
      for (var j = i + 1; j < f.tasks.length && f.tasks[j].outlineLevel > t.outlineLevel; j++) {
        final c = f.tasks[j];
        if (c.start != null && c.start!.isBefore(s) ||
            c.finish != null && c.finish!.isAfter(fin)) {
          errors.add('${t.label}: does not span its child ${c.label}.');
        }
      }
    }

    // Scheduling mode.
    if (options.pinDates && !t.summary) {
      if (!t.manual) errors.add('${t.label}: "pin dates" is on but it is auto-scheduled.');
      if (t.manualStart != s || t.manualFinish != fin ||
          t.manualDurationMinutes != t.durationMinutes) {
        errors.add('${t.label}: ManualStart/Finish/Duration do not match its dates.');
      }
    } else {
      if (t.manual) errors.add('${t.label}: manually scheduled although "pin dates" is off.');
      if (!t.summary && t.constraintType == 0) {
        errors.add('${t.label}: auto-scheduled with no date constraint — '
            'Project would move it to the project start.');
      }
    }

    // Links: zero lag, a real non-summary predecessor, satisfied by dates.
    for (final l in t.links) {
      final p = byUid[l.predecessorUid];
      if (p == null) {
        errors.add('${t.label}: links to UID ${l.predecessorUid}, which is not in the file.');
        continue;
      }
      if (l.lag != 0) {
        errors.add('${t.label}: link from ${p.label} has a lag of '
            '${l.lag ~/ kTenthsOfMinutesPerDay} days; Keel exports links with no lag.');
      }
      if (p.summary) errors.add('${t.label}: linked from the summary ${p.label}.');
      if (p.start != null && p.finish != null) {
        final gap = linkGapHours(
          type: l.type,
          predecessorStart: p.start!,
          predecessorFinish: p.finish!,
          successorStart: s,
          successorFinish: fin,
        );
        if (gap < 0) {
          errors.add('${t.label}: its dates contradict the link from '
              '${p.label}, so Project would move it.');
        }
      }
    }

    // Baseline 0.
    for (final (bs, bf, bd) in t.baselines) {
      if (bs == null || bf == null || bd == null) {
        errors.add('${t.label}: Baseline 0 lacks start, finish or duration.');
        continue;
      }
      final bw = bs == bf ? 0 : (workingHoursPosition(bf) - workingHoursPosition(bs)) * 60;
      if (bd != bw) {
        errors.add('${t.label}: Baseline 0 duration ${_h(bd)} does not match '
            '${msDate(bs)} – ${msDate(bf)}.');
      }
    }

    // Notes.
    if (options.notes == MsNotesMode.publicOnly) {
      for (final line in t.notes.split('\n')) {
        if (isKeelGeneratedNoteLine(line)) {
          errors.add('${t.label}: Notes carry Keel history ("${_clip(line)}") '
              'although "public notes only" is on.');
        }
      }
    }
    if (t.notes.contains('exported at the end of that month')) {
      errors.add('${t.label}: an exporter remark is in Notes.');
    }
  }

  // Cycles (Project refuses a circular dependency).
  final preds = {for (final t in f.tasks) t.uid: [for (final l in t.links) l.predecessorUid]};
  final state = <int, int>{}; // 1 visiting, 2 done
  bool cyclic(int u) {
    if (state[u] == 1) return true;
    if (state[u] == 2) return false;
    state[u] = 1;
    for (final p in preds[u] ?? const <int>[]) {
      if (cyclic(p)) return true;
    }
    state[u] = 2;
    return false;
  }
  for (final t in f.tasks) {
    if (cyclic(t.uid)) {
      errors.add('${t.label}: its links form a loop.');
      break;
    }
  }

  // Assignments agree with their task.
  final assignedTasks = <int>{};
  for (final a in f.assignments) {
    final t = byUid[a.taskUid];
    final what = 'Assignment of ${f.resources[a.resourceUid] ?? 'resource ${a.resourceUid}'}';
    if (t == null) {
      errors.add('$what: task UID ${a.taskUid} is not in the file.');
      continue;
    }
    if (!assignedTasks.add(a.taskUid)) {
      errors.add('${t.label}: assigned more than once.');
    }
    final p = _orderProblem(a.childOrder, kMsAssignmentOrder);
    if (p != null) errors.add('$what on ${t.label}: $p.');
    if (t.summary) errors.add('$what on the summary ${t.label}.');
    if (!f.resources.containsKey(a.resourceUid)) {
      errors.add('$what on ${t.label}: no such resource.');
    }
    if (a.start != t.start || a.finish != t.finish) {
      errors.add('$what on ${t.label}: Start/Finish '
          '${a.start == null ? 'missing' : msDate(a.start!)} – '
          '${a.finish == null ? 'missing' : msDate(a.finish!)} differ from the task.');
    }
    final expectWork = t.milestone ? 0 : t.durationMinutes;
    if (a.workMinutes != expectWork) {
      errors.add('$what on ${t.label}: Work ${_h(a.workMinutes)}, expected ${_h(expectWork)}.');
    }
    if (t.workMinutes != a.workMinutes) {
      errors.add('${t.label}: task Work ${_h(t.workMinutes)} differs from its assignment.');
    }
    if (a.actualWorkMinutes == null || a.remainingWorkMinutes == null ||
        a.actualWorkMinutes! + a.remainingWorkMinutes! != (a.workMinutes ?? -1)) {
      errors.add('$what on ${t.label}: actual + remaining work does not add up to Work.');
    }
    if (a.percentWorkComplete != t.percentComplete) {
      errors.add('$what on ${t.label}: ${a.percentWorkComplete}% work complete '
          'but the task is ${t.percentComplete}%.');
    }
  }

  return errors;
}

String _h(int? minutes) => minutes == null ? 'none' : '${minutes ~/ 60}h';
String _clip(String s) => s.length > 50 ? '${s.substring(0, 50)}…' : s;

// ─── B. Round-trip check ────────────────────────────────────────────────────

/// Compares the file Project saved ([actualXml]) with Keel's export of
/// the plan now ([expectedXml]). Tasks pair by Keel ID (Text4), falling
/// back to UID. One line per task that differs; empty = safe to upload.
List<String> compareMsProjectFiles({
  required String expectedXml,
  required String actualXml,
}) {
  final exp = MsFile.parse(expectedXml);
  final act = MsFile.parse(actualXml);

  final actByKeel = {for (final t in act.tasks) if (t.keelId.isNotEmpty) t.keelId: t};
  final actByUid = {for (final t in act.tasks) t.uid: t};
  final expByUid = {for (final t in exp.tasks) t.uid: t};

  // Pair first, so a link in either file can be named by the Keel row it
  // comes from even when Project's file lacks Text4.
  final pairOf = <int, MsFileTask>{}; // expected uid → actual task
  for (final e in exp.tasks) {
    final a = (e.keelId.isNotEmpty ? actByKeel[e.keelId] : null) ?? actByUid[e.uid];
    if (a != null) pairOf[e.uid] = a;
  }
  final keelOfActual = <int, String>{
    for (final e in exp.tasks)
      if (pairOf[e.uid] != null)
        pairOf[e.uid]!.uid: e.keelId.isNotEmpty ? e.keelId : 'uid:${e.uid}',
  };
  String keelOfExp(int uid) {
    final t = expByUid[uid];
    return t == null || t.keelId.isEmpty ? 'uid:$uid' : t.keelId;
  }

  String keelOfAct(int uid) => keelOfActual[uid] ?? 'actual-uid:$uid';

  Map<int, List<String>> owners(MsFile f) {
    final out = <int, List<String>>{};
    for (final a in f.assignments) {
      final n = f.resources[a.resourceUid];
      if (n != null) out.putIfAbsent(a.taskUid, () => []).add(n.toLowerCase());
    }
    for (final l in out.values) {
      l.sort();
    }
    return out;
  }

  final expOwners = owners(exp);
  final actOwners = owners(act);
  String at(DateTime? d) => d == null ? 'none' : msDayLabel(msDate(d)) +
      ((d.hour == 8 || d.hour == 17) && d.minute == 0
          ? (d.hour == 8 ? ' 08:00' : ' 17:00')
          : '');
  String linkText(MsFile f, Map<int, MsFileTask> byUid, MsFileLink l) {
    final p = byUid[l.predecessorUid];
    final type = switch (l.type) { 0 => 'FF', 3 => 'SS', 2 => 'SF', _ => 'FS' };
    final lag = l.lag == 0 ? '' : ' lag ${l.lag / kTenthsOfMinutesPerDay}d';
    return '$type from "${p?.name ?? 'UID ${l.predecessorUid}'}"$lag';
  }

  final out = <String>[];
  final matched = <int>{};
  for (final e in exp.tasks) {
    final a = pairOf[e.uid];
    if (a == null) {
      out.add('"${e.name}": missing from the Project file.');
      continue;
    }
    matched.add(a.uid);
    final diffs = <String>[];
    if (a.name != e.name) diffs.add('name "${a.name}"');
    if (a.start != e.start) diffs.add('start ${at(e.start)} → ${at(a.start)}');
    if (a.finish != e.finish) diffs.add('finish ${at(e.finish)} → ${at(a.finish)}');
    // Project computes a summary's % complete from its children.
    if (!e.summary && a.percentComplete != e.percentComplete) {
      diffs.add('${e.percentComplete}% → ${a.percentComplete}% complete');
    }
    if (a.outlineLevel != e.outlineLevel) {
      diffs.add('outline level ${e.outlineLevel} → ${a.outlineLevel}');
    }
    if (a.milestone != e.milestone) {
      diffs.add(e.milestone ? 'no longer a milestone' : 'became a milestone');
    }
    final eo = (expOwners[e.uid] ?? const []).join(', ');
    final ao = (actOwners[a.uid] ?? const []).join(', ');
    if (eo != ao) diffs.add('owner ${eo.isEmpty ? 'none' : eo} → ${ao.isEmpty ? 'none' : ao}');
    final el = {
      for (final l in e.links)
        '${keelOfExp(l.predecessorUid)}|${l.type}|${l.lag}': linkText(exp, expByUid, l),
    };
    final al = {
      for (final l in a.links)
        '${keelOfAct(l.predecessorUid)}|${l.type}|${l.lag}': linkText(act, actByUid, l),
    };
    for (final k in el.keys) {
      if (!al.containsKey(k)) diffs.add('link lost: ${el[k]}');
    }
    for (final k in al.keys) {
      if (!el.containsKey(k)) diffs.add('extra link: ${al[k]}');
    }
    if (diffs.isNotEmpty) out.add('"${e.name}" (UID ${a.uid}): ${diffs.join('; ')}.');
  }
  for (final a in act.tasks) {
    if (!matched.contains(a.uid)) {
      out.add('"${a.name}" (UID ${a.uid}): in the Project file but not in the Keel plan.');
    }
  }
  return out;
}
