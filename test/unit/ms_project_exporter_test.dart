import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/ms_project_exporter.dart';
import 'package:xml/xml.dart';

/// The MSPDI task children in schema order (checked against files written
/// by Project 2019). Project rejects a file whose children are out of
/// sequence, so every Task the exporter writes must respect this list.
const _taskOrder = [
  'UID', 'ID', 'Name', 'Active', 'Manual', 'Type', 'IsNull', 'CreateDate',
  'WBS', 'OutlineNumber', 'OutlineLevel', 'Priority', 'Start', 'Finish',
  'Duration', 'DurationFormat', 'Milestone', 'Summary', 'PercentComplete',
  'ActualStart', 'ActualFinish', 'ConstraintType', 'CalendarUID',
  'ConstraintDate', 'Deadline', 'Notes', 'PredecessorLink',
  'ExtendedAttribute',
];

const _projectOrder = [
  'SaveVersion', 'Name', 'Title', 'CreationDate', 'LastSaved',
  'ScheduleFromStart', 'StartDate', 'FinishDate', 'CalendarUID',
  'DefaultStartTime', 'DefaultFinishTime', 'MinutesPerDay', 'MinutesPerWeek',
  'DaysPerMonth', 'DefaultTaskType', 'DurationFormat', 'WorkFormat',
  'HonorConstraints', 'NewTasksEffortDriven', 'NewTasksEstimated',
  'WeekStartDay', 'CurrentDate', 'NewTaskStartDate', 'NewTasksAreManual',
  'ExtendedAttributes', 'Calendars', 'Tasks', 'Resources', 'Assignments',
];

/// Asserts [names] appear in the relative order given by [order].
void _expectInOrder(List<String> names, List<String> order, String where) {
  var last = -1;
  for (final n in names) {
    final idx = order.indexOf(n);
    expect(idx, greaterThanOrEqualTo(0), reason: '$where: unexpected element $n');
    expect(idx, greaterThanOrEqualTo(last),
        reason: '$where: $n is out of schema order in $names');
    last = idx;
  }
}

Future<AppDatabase> _seed({bool withAnchor = true}) async {
  final db = AppDatabase.memory();
  await db.projectDao.insertProject(ProjectsCompanion.insert(
    id: 'p',
    name: 'TAC Integration',
    startDate: const Value('2026-06-10'),
  ));
  final dao = db.programmeGanttDao;
  await dao.upsertHeader(ProgrammeHeadersCompanion(
    id: const Value('h'),
    projectId: const Value('p'),
    title: const Value('TAC Integration Plan'),
    hardDeadline: const Value('Go-live by 15 Jan'),
    hardDeadlineDate: const Value('2027-01-15'),
    month0Date: Value(withAnchor ? '2026-04-01' : null),
    monthLabels: Value(jsonEncode([
      'Apr 26', 'May 26', 'Jun 26', 'Jul 26', 'Aug 26',
      'Sep 26', 'Oct 26', 'Nov 26', 'Dec 26',
    ])),
  ));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r1'), projectId: Value('p'), ref: Value('R1'),
    description: Value('Vendor slips'),
  ));

  await dao.upsertWorkPackage(const TimelineWorkPackagesCompanion(
    id: Value('wpA'), projectId: Value('p'), name: Value('Platform & Enablement'),
    shortCode: Value('WP1'), sortOrder: Value(0),
  ));
  await dao.upsertWorkPackage(const TimelineWorkPackagesCompanion(
    id: Value('wpB'), projectId: Value('p'), name: Value('Empty package'),
    sortOrder: Value(1),
  ));

  Future<void> act(TimelineActivitiesCompanion c) => dao.upsertActivity(c);
  // Jul 26 only: 1 Jul (Wed) → 31 Jul (Fri), 23 working days.
  await act(const TimelineActivitiesCompanion(
    id: Value('design'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('Design'), startMonth: Value(3), endMonth: Value(3),
    owner: Value('Paul Murray'), sortOrder: Value(0), isCritical: Value(true),
  ));
  // Starts the same month Design ends → needs a lead.
  await act(const TimelineActivitiesCompanion(
    id: Value('review'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('Security review'), startMonth: Value(3), endMonth: Value(4),
    owner: Value('Sam Lee'), sortOrder: Value(1), status: Value('on_track'),
  ));
  await act(const TimelineActivitiesCompanion(
    id: Value('m1'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('Design complete'), activityType: Value('milestone'),
    startMonth: Value(3), endMonth: Value(3), sortOrder: Value(2),
  ));
  // Dated, complete, with a scenario spread driven by R1.
  await act(const TimelineActivitiesCompanion(
    id: Value('build'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('Build'), startMonth: Value(4), endMonth: Value(5),
    startDate: Value('2026-08-03'), endDate: Value('2026-09-18'),
    owner: Value('paul murray'), status: Value('complete'), sortOrder: Value(3),
    likelyMonth: Value(5), safeMonth: Value(6),
    varianceRaidLinksJson: Value('[{"type":"risk","id":"r1"}]'),
  ));
  // Parent with a Sep–Oct window; its second task breaches into Dec.
  await act(const TimelineActivitiesCompanion(
    id: Value('transition'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('Transition'), startMonth: Value(5), endMonth: Value(6),
    sortOrder: Value(4), owner: Value('Paul Murray'),
  ));
  await act(const TimelineActivitiesCompanion(
    id: Value('t1'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('Handbook'), parentActivityId: Value('transition'),
    startMonth: Value(5), endMonth: Value(5), sortOrder: Value(5),
    owner: Value('Sam Lee'),
  ));
  await act(const TimelineActivitiesCompanion(
    id: Value('t2'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('Hypercare'), parentActivityId: Value('transition'),
    startMonth: Value(6), endMonth: Value(8), sortOrder: Value(6),
  ));
  await act(const TimelineActivitiesCompanion(
    id: Value('golive'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('Priority 1 Go-Live'), activityType: Value('hard_deadline'),
    startMonth: Value(8), endMonth: Value(8), sortOrder: Value(7),
  ));
  await act(const TimelineActivitiesCompanion(
    id: Value('undated'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('Someday maybe'), sortOrder: Value(8),
  ));

  Future<void> dep(String id, String from, String to,
          {String type = 'finish_to_start', String? ext}) =>
      dao.upsertDependency(TimelineDependenciesCompanion(
        id: Value(id), projectId: const Value('p'),
        fromActivityId: Value(from), toActivityId: Value(to),
        dependencyType: Value(ext != null ? 'external' : type),
        externalLabel: Value(ext),
      ));
  await dep('d1', 'design', 'review');
  await dep('d2', 'design', 'm1');
  await dep('d3', 'm1', 'build');
  await dep('d4', '', 'build', ext: 'Vendor contract signed');
  await dep('d5', 'build', 't1', type: 'start_to_start');
  return db;
}

void main() {
  final now = DateTime(2026, 11, 4, 9);

  group('working-day maths', () {
    test('month bounds and weekend snapping', () {
      final m0 = DateTime(2026, 4);
      expect(monthStart(m0, 3), DateTime(2026, 7, 1));
      expect(monthEnd(m0, 6), DateTime(2026, 10, 31)); // a Saturday
      expect(previousWorkingDay(DateTime(2026, 10, 31)), DateTime(2026, 10, 30));
      expect(nextWorkingDay(DateTime(2026, 8, 1)), DateTime(2026, 8, 3)); // Sat → Mon
      expect(nextWorkingDay(DateTime(2026, 8, 3)), DateTime(2026, 8, 3));
    });

    test('working-day index counts Mon–Fri only', () {
      final mon = DateTime(2026, 7, 6);
      expect(workingDayIndex(DateTime(2026, 7, 10)) - workingDayIndex(mon), 4);
      expect(workingDayIndex(DateTime(2026, 7, 13)) - workingDayIndex(mon), 5);
      // July 2026 has 23 working days.
      expect(workingDayIndex(DateTime(2026, 7, 31)) - workingDayIndex(DateTime(2026, 7, 1)), 22);
    });

    test('a lead replays to the Keel start under Project\'s lag rule', () {
      final predStart = DateTime(2026, 7, 1, 8);
      final predFinish = DateTime(2026, 7, 31, 17);
      // Same-month overlap: successor starts 1 Jul too → 23-day lead.
      final lag = linkLagDaysFor(
        type: 1,
        predecessorStart: predStart, predecessorFinish: predFinish,
        successorStart: DateTime(2026, 7, 1, 8), successorFinish: DateTime(2026, 8, 31, 17),
      );
      expect(lag, -23);
      expect(addWorkingHours(predFinish, lag * kHoursPerDay), DateTime(2026, 7, 1, 8));

      // Same-day start = −1; Monday start when the predecessor ends Friday = −5.
      expect(linkLagDaysFor(
        type: 1,
        predecessorStart: DateTime(2026, 7, 6, 8), predecessorFinish: DateTime(2026, 7, 10, 17),
        successorStart: DateTime(2026, 7, 10, 8), successorFinish: DateTime(2026, 7, 10, 17),
      ), -1);
      expect(linkLagDaysFor(
        type: 1,
        predecessorStart: DateTime(2026, 7, 6, 8), predecessorFinish: DateTime(2026, 7, 10, 17),
        successorStart: DateTime(2026, 7, 6, 8), successorFinish: DateTime(2026, 7, 17, 17),
      ), -5);
      // A gap is not a lag: the constraint holds the date.
      expect(linkLagDaysFor(
        type: 1,
        predecessorStart: predStart, predecessorFinish: predFinish,
        successorStart: DateTime(2026, 9, 1, 8), successorFinish: DateTime(2026, 9, 30, 17),
      ), 0);
      // A milestone at 17:00 on the predecessor's last day needs no lead.
      expect(linkLagDaysFor(
        type: 1,
        predecessorStart: predStart, predecessorFinish: predFinish,
        successorStart: predFinish, successorFinish: predFinish,
      ), 0);
    });

    test('start-to-start and finish-to-finish leads measure their own ends', () {
      // SS: successor starts a week before the predecessor → −5.
      expect(linkLagDaysFor(
        type: 3,
        predecessorStart: DateTime(2026, 7, 13, 8), predecessorFinish: DateTime(2026, 7, 31, 17),
        successorStart: DateTime(2026, 7, 6, 8), successorFinish: DateTime(2026, 7, 31, 17),
      ), -5);
      // FF: successor finishes two working days earlier → −2.
      expect(linkLagDaysFor(
        type: 0,
        predecessorStart: DateTime(2026, 7, 1, 8), predecessorFinish: DateTime(2026, 7, 31, 17),
        successorStart: DateTime(2026, 7, 1, 8), successorFinish: DateTime(2026, 7, 29, 17),
      ), -2);
    });
  });

  group('plan tree', () {
    late AppDatabase db;
    late MsProjectExport out;
    late XmlDocument doc;
    late List<XmlElement> tasks;

    XmlElement taskNamed(String name) => tasks.firstWhere(
        (t) => t.getElement('Name')!.innerText == name,
        orElse: () => throw StateError('no task "$name"'));
    String txt(XmlElement t, String tag) => t.getElement(tag)?.innerText ?? '';

    setUpAll(() async {
      db = await _seed();
      out = await MsProjectExporter.build(
          db: db, projectId: 'p', projectName: 'TAC Integration', now: now);
      doc = XmlDocument.parse(out.xml);
      tasks = doc.rootElement.getElement('Tasks')!.findElements('Task').toList();
    });
    tearDownAll(() => db.close());

    test('root, namespace and project-level order', () {
      final root = doc.rootElement;
      expect(root.name.local, 'Project');
      expect(root.getAttribute('xmlns'), 'http://schemas.microsoft.com/project');
      _expectInOrder(
          root.childElements.map((e) => e.name.local).toList(), _projectOrder, 'Project');
      expect(txt(root, 'SaveVersion'), '14');
      expect(txt(root, 'Title'), 'TAC Integration Plan');
      expect(txt(root, 'StartDate'), '2026-07-01T08:00:00');
      expect(txt(root, 'FinishDate'), '2027-01-15T17:00:00');
      // Standard calendar, Monday–Friday.
      final days = root.getElement('Calendars')!.findAllElements('WeekDay').toList();
      expect(days.map((d) => txt(d, 'DayWorking')).join(), '0111110');
    });

    test('every task keeps schema order, ids are contiguous from 1', () {
      for (final t in tasks) {
        _expectInOrder(t.childElements.map((e) => e.name.local).toList(),
            _taskOrder, 'Task ${txt(t, 'Name')}');
      }
      expect(tasks.map((t) => int.parse(txt(t, 'UID'))).toList(),
          List.generate(tasks.length, (i) => i + 1));
      expect(tasks.map((t) => txt(t, 'ID')).toList(), tasks.map((t) => txt(t, 'UID')).toList());
      final levels = tasks.map((t) => int.parse(txt(t, 'OutlineLevel'))).toList();
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i] - levels[i - 1], lessThanOrEqualTo(1),
            reason: 'outline level must not skip at ${txt(tasks[i], 'Name')}');
      }
    });

    test('work package → summary, activities and tasks nest underneath', () {
      final wp = taskNamed('WP1  Platform & Enablement');
      expect(txt(wp, 'OutlineLevel'), '1');
      expect(txt(wp, 'OutlineNumber'), '1');
      expect(txt(wp, 'Summary'), '1');
      expect(txt(wp, 'ConstraintType'), '0');
      expect(wp.getElement('ConstraintDate'), isNull);
      // Rolled up from the children: Design (1 Jul) … Hypercare (31 Dec).
      expect(txt(wp, 'Start'), '2026-07-01T08:00:00');
      expect(txt(wp, 'Finish'), '2026-12-31T17:00:00');

      final design = taskNamed('Design');
      expect(txt(design, 'OutlineLevel'), '2');
      expect(txt(design, 'OutlineNumber'), '1.1');
      expect(txt(design, 'Start'), '2026-07-01T08:00:00');
      expect(txt(design, 'Finish'), '2026-07-31T17:00:00');
      expect(txt(design, 'Duration'), 'PT184H0M0S'); // 23 working days
      expect(txt(design, 'ConstraintType'), '4'); // start no earlier than
      expect(txt(design, 'ConstraintDate'), '2026-07-01T08:00:00');
      expect(txt(design, 'Summary'), '0');
      expect(txt(design, 'Notes'), contains('Marked critical in Keel.'));

      final handbook = taskNamed('Handbook');
      expect(txt(handbook, 'OutlineLevel'), '3');
      expect(txt(handbook, 'OutlineNumber'), '1.5.1');
    });

    test('a month-only milestone sits at the end of its month', () {
      final m = taskNamed('Design complete');
      expect(txt(m, 'Milestone'), '1');
      expect(txt(m, 'Start'), '2026-07-31T17:00:00');
      expect(txt(m, 'Finish'), '2026-07-31T17:00:00');
      expect(txt(m, 'Duration'), 'PT0H0M0S');
      expect(txt(m, 'Notes'), contains('exported at the end of that month'));
    });

    test('dates win over months and complete work is 100%', () {
      final b = taskNamed('Build');
      expect(txt(b, 'Start'), '2026-08-03T08:00:00');
      expect(txt(b, 'Finish'), '2026-09-18T17:00:00');
      expect(txt(b, 'PercentComplete'), '100');
      expect(txt(b, 'ActualStart'), '2026-08-03T08:00:00');
      expect(txt(b, 'ActualFinish'), '2026-09-18T17:00:00');
      expect(txt(b, 'Notes'), contains('External dependency: Vendor contract signed'));
    });

    test('links carry a lead only where Keel overlaps', () {
      final design = int.parse(txt(taskNamed('Design'), 'UID'));
      final review = taskNamed('Security review');
      final link = review.getElement('PredecessorLink')!;
      expect(txt(link, 'PredecessorUID'), '$design');
      expect(txt(link, 'Type'), '1');
      expect(txt(link, 'LinkLag'), '${-23 * kTenthsOfMinutesPerDay}');
      expect(txt(link, 'LagFormat'), '7');

      final m1 = taskNamed('Design complete').getElement('PredecessorLink')!;
      expect(txt(m1, 'LinkLag'), '0', reason: 'milestone at 17:00 on the last day');

      // m1 (31 Jul 17:00) → Build (3 Aug 08:00): a gap, so no lag.
      final build = taskNamed('Build').getElement('PredecessorLink')!;
      expect(txt(build, 'LinkLag'), '0');

      // SS Build (3 Aug) → Handbook (1 Sep): successor later, no lag.
      final hb = taskNamed('Handbook').getElement('PredecessorLink')!;
      expect(txt(hb, 'Type'), '3');
      expect(txt(hb, 'LinkLag'), '0');
    });

    test('for every link, predecessor + lag lands on the Keel start', () {
      final byUid = {for (final t in tasks) txt(t, 'UID'): t};
      var checked = 0;
      for (final t in tasks) {
        for (final l in t.findElements('PredecessorLink')) {
          if (txt(l, 'Type') != '1') continue;
          final pred = byUid[txt(l, 'PredecessorUID')]!;
          final lagHours =
              int.parse(txt(l, 'LinkLag')) ~/ kTenthsOfMinutesPerDay * kHoursPerDay;
          final computed =
              workingHoursPosition(DateTime.parse(txt(pred, 'Finish'))) + lagHours;
          final keelStart = workingHoursPosition(DateTime.parse(txt(t, 'Start')));
          expect(computed, lessThanOrEqualTo(keelStart),
              reason: '${txt(t, 'Name')} would be pushed by its link');
          checked++;
        }
      }
      expect(checked, greaterThanOrEqualTo(3));
    });

    test('a parent activity keeps its commitment window as the Deadline', () {
      final p = taskNamed('Transition');
      expect(txt(p, 'Summary'), '1');
      expect(txt(p, 'Start'), '2026-09-01T08:00:00');
      expect(txt(p, 'Finish'), '2026-12-31T17:00:00', reason: 'rolled up from Hypercare');
      expect(txt(p, 'Deadline'), '2026-10-30T17:00:00', reason: 'window end, 31 Oct is a Saturday');
      expect(txt(p, 'Notes'), contains('Keel commitment window: Sep 26 – Oct 26'));
      expect(p.getElement('PredecessorLink'), isNull);
    });

    test('a complete parent carries no actuals of its own', () async {
      final db2 = await _seed();
      addTearDown(db2.close);
      await db2.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
        id: Value('transition'), workPackageId: Value('wpA'), projectId: Value('p'),
        name: Value('Transition'), startMonth: Value(5), endMonth: Value(6),
        status: Value('complete'),
      ));
      final out2 = await MsProjectExporter.build(
          db: db2, projectId: 'p', projectName: 'TAC Integration', now: now);
      final p = XmlDocument.parse(out2.xml).findAllElements('Task')
          .firstWhere((t) => t.getElement('Name')!.innerText == 'Transition');
      expect(txt(p, 'Summary'), '1');
      expect(txt(p, 'PercentComplete'), '0');
      expect(p.getElement('ActualStart'), isNull);
      expect(p.getElement('ActualFinish'), isNull);
    });

    test('hard deadlines are pinned milestones with a Deadline', () {
      final g = taskNamed('Priority 1 Go-Live');
      expect(txt(g, 'Milestone'), '1');
      expect(txt(g, 'ConstraintType'), '2'); // must start on
      expect(txt(g, 'Start'), '2026-12-31T17:00:00');
      expect(txt(g, 'Deadline'), '2026-12-31T17:00:00');

      final hd = taskNamed('Go-live by 15 Jan');
      expect(txt(hd, 'OutlineLevel'), '1');
      expect(txt(hd, 'Start'), '2027-01-15T17:00:00');
      expect(txt(hd, 'ConstraintType'), '2');
    });

    test('status and scenario land in Text1 and Text2', () {
      final defs = doc.rootElement.getElement('ExtendedAttributes')!
          .findElements('ExtendedAttribute')
          .map((e) => (txt(e, 'FieldID'), txt(e, 'FieldName'), txt(e, 'Alias')))
          .toList();
      expect(defs, [
        ('188743731', 'Text1', 'Keel status'),
        ('188743734', 'Text2', 'Keel scenario'),
      ]);
      Map<String, String> ext(XmlElement t) => {
            for (final e in t.findElements('ExtendedAttribute'))
              txt(e, 'FieldID'): txt(e, 'Value'),
          };
      expect(ext(taskNamed('Security review'))['188743731'], 'On track');
      expect(ext(taskNamed('Build'))['188743731'], 'Complete');
      expect(ext(taskNamed('Build'))['188743734'],
          'Anchor Aug 26 · Likely Sep 26 · Safe Oct 26 · Driven by R1');
      expect(ext(taskNamed('WP1  Platform & Enablement')), isEmpty,
          reason: 'summaries carry no status');
    });

    test('owners become resources, assigned on leaves only, case-insensitive', () {
      final res = doc.rootElement.getElement('Resources')!.findElements('Resource')
          .map((r) => (txt(r, 'UID'), txt(r, 'Name'), txt(r, 'Initials')))
          .toList();
      expect(res, [('1', 'Paul Murray', 'PM'), ('2', 'Sam Lee', 'SL')]);
      final asg = doc.rootElement.getElement('Assignments')!.findElements('Assignment')
          .map((a) => (txt(a, 'TaskUID'), txt(a, 'ResourceUID')))
          .toList();
      final byUid = {for (final t in tasks) txt(t, 'UID'): t};
      for (final (taskUid, _) in asg) {
        expect(txt(byUid[taskUid]!, 'Summary'), '0',
            reason: 'no assignment on summary ${txt(byUid[taskUid]!, 'Name')}');
      }
      expect(asg, contains((txt(taskNamed('Design'), 'UID'), '1')));
      expect(asg, contains((txt(taskNamed('Build'), 'UID'), '1')), reason: 'paul murray dedups');
      expect(asg, contains((txt(taskNamed('Handbook'), 'UID'), '2')));
      expect(asg.where((a) => a.$1 == txt(taskNamed('Transition'), 'UID')), isEmpty);
    });

    test('warnings name what was left out', () {
      expect(out.warnings, hasLength(2));
      expect(out.warnings[0], contains('Empty package'));
      expect(out.warnings[1], contains('Someday maybe'));
      expect(tasks.where((t) => txt(t, 'Name') == 'Someday maybe'), isEmpty);
    });

    test('the file is well-formed for xmllint', () async {
      final which = await Process.run('which', ['xmllint']);
      if (which.exitCode != 0) {
        markTestSkipped('xmllint not installed');
        return;
      }
      final f = File('${Directory.systemTemp.path}/keel_msp_${DateTime.now().microsecondsSinceEpoch}.xml');
      await f.writeAsString(out.xml);
      try {
        final r = await Process.run('xmllint', ['--noout', f.path]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
      } finally {
        await f.delete();
      }
    });
  });

  group('without blocks', () {
    test('resources and custom fields can be switched off', () async {
      final db = await _seed();
      addTearDown(db.close);
      final out = await MsProjectExporter.build(
        db: db, projectId: 'p', projectName: 'TAC Integration', now: now,
        includeResources: false, includeCustomFields: false,
      );
      final root = XmlDocument.parse(out.xml).rootElement;
      expect(root.getElement('Resources'), isNull);
      expect(root.getElement('Assignments'), isNull);
      expect(root.getElement('ExtendedAttributes'), isNull);
      expect(root.findAllElements('ExtendedAttribute'), isEmpty);
    });
  });

  group('no month-0 anchor', () {
    test('falls back to the project start month and says so', () async {
      final db = await _seed(withAnchor: false);
      addTearDown(db.close);
      final out = await MsProjectExporter.build(
          db: db, projectId: 'p', projectName: 'TAC Integration', now: now);
      expect(out.warnings.first, contains('placed at 2026-06-01'));
      final root = XmlDocument.parse(out.xml).rootElement;
      final design = root.findAllElements('Task')
          .firstWhere((t) => t.getElement('Name')!.innerText == 'Design');
      // Month 3 from June = September.
      expect(design.getElement('Start')!.innerText, '2026-09-01T08:00:00');
    });
  });
}
