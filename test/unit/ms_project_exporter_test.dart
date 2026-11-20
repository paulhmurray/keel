import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/ms_project_checks.dart';
import 'package:keel/core/export/ms_project_exporter.dart';
import 'package:keel/core/export/ms_project_state.dart';
import 'package:xml/xml.dart';

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
    isBaseline: Value(true), baselineStart: Value(2), baselineEnd: Value(2),
    notes: Value('Kick-off with vendor\n'
        'Re-planned 2026-10-01: was Jun 26, now Jul 26. '
        'AI view (high confidence): fine.\n'
        'Added on plan review 2026-10-05: check scope'),
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
  // A dependency marker with an Oct–Dec window: a bar, not a milestone.
  await act(const TimelineActivitiesCompanion(
    id: Value('sit'), workPackageId: Value('wpA'), projectId: Value('p'),
    name: Value('SIT window'), activityType: Value('dependency_marker'),
    startMonth: Value(6), endMonth: Value(8), sortOrder: Value(8),
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
  // Links on the summary "Transition": in → first child, out → last child.
  await dep('d6', 'review', 'transition');
  await dep('d7', 'transition', 'golive');
  return db;
}


const _pid = 'p';

Future<MsProjectExport> _build(AppDatabase db,
        {MsProjectOptions options = const MsProjectOptions(), DateTime? now}) =>
    MsProjectExporter.build(
      db: db,
      projectId: _pid,
      projectName: 'TAC Integration',
      now: now ?? DateTime(2026, 11, 4, 9),
      options: options,
    );

String _txt(XmlElement t, String tag) => t.getElement(tag)?.innerText ?? '';

Map<String, String> _ext(XmlElement t) => {
      for (final e in t.findElements('ExtendedAttribute'))
        _txt(e, 'FieldID'): _txt(e, 'Value'),
    };

const _status = '188743731';
const _scenario = '188743734';
const _owner = '188743737';
const _keelId = '188743740';
const _remark = '188743743';

void main() {
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

    test('link gap: Friday 17:00 meets Monday 08:00; overlap is negative', () {
      int gap(int type, DateTime ps, DateTime pf, DateTime ss, DateTime sf) =>
          linkGapHours(type: type, predecessorStart: ps, predecessorFinish: pf,
              successorStart: ss, successorFinish: sf);
      final ps = DateTime(2026, 7, 6, 8), pf = DateTime(2026, 7, 10, 17);
      // FS into the next Monday: satisfied with no lag.
      expect(gap(1, ps, pf, DateTime(2026, 7, 13, 8), DateTime(2026, 7, 17, 17)), 0);
      // FS milestone at 17:00 on the predecessor's last day: satisfied.
      expect(gap(1, ps, pf, pf, pf), 0);
      // FS successor starting the same week: contradicted.
      expect(gap(1, ps, pf, DateTime(2026, 7, 8, 8), DateTime(2026, 7, 17, 17)), -24);
      // SS earlier start, FF earlier finish: contradicted.
      expect(gap(3, ps, pf, DateTime(2026, 7, 3, 8), pf), lessThan(0));
      expect(gap(0, ps, pf, ps, DateTime(2026, 7, 9, 17)), -8);
    });

    test('durations parse in minutes', () {
      expect(parseMsDurationMinutes('PT184H0M0S'), 184 * 60);
      expect(parseMsDurationMinutes('PT0H0M0S'), 0);
      expect(parseMsDurationMinutes('PT7H30M0S'), 450);
      expect(parseMsDurationMinutes(null), isNull);
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
    String uidOf(String name) => _txt(taskNamed(name), 'UID');

    setUpAll(() async {
      db = await _seed();
      out = await _build(db);
      doc = XmlDocument.parse(out.xml);
      tasks = doc.rootElement.getElement('Tasks')!.findElements('Task').toList();
    });
    tearDownAll(() => db.close());

    test('the self-check passes', () {
      expect(out.errors, isEmpty);
      expect(out.ok, isTrue);
    });

    test('root, namespace and project-level order', () {
      final root = doc.rootElement;
      expect(root.name.local, 'Project');
      expect(root.getAttribute('xmlns'), 'http://schemas.microsoft.com/project');
      _expectInOrder(root.childElements.map((e) => e.name.local).toList(),
          kMsProjectRootOrder, 'Project');
      expect(_txt(root, 'SaveVersion'), '14');
      expect(_txt(root, 'Title'), 'TAC Integration Plan');
      expect(_txt(root, 'StartDate'), '2026-07-01T08:00:00');
      expect(_txt(root, 'FinishDate'), '2027-01-15T17:00:00');
      final days = root.getElement('Calendars')!.findAllElements('WeekDay').toList();
      expect(days.map((d) => _txt(d, 'DayWorking')).join(), '0111110');
    });

    test('schema order everywhere; IDs are row numbers, UIDs unique', () {
      for (final t in tasks) {
        _expectInOrder(t.childElements.map((e) => e.name.local).toList(),
            kMsTaskOrder, 'Task ${_txt(t, 'Name')}');
      }
      for (final a in doc.findAllElements('Assignment')) {
        _expectInOrder(a.childElements.map((e) => e.name.local).toList(),
            kMsAssignmentOrder, 'Assignment');
      }
      expect(tasks.map((t) => _txt(t, 'ID')).toList(),
          List.generate(tasks.length, (i) => '${i + 1}'));
      final uids = tasks.map((t) => _txt(t, 'UID')).toList();
      expect(uids.toSet(), hasLength(uids.length));
      final levels = tasks.map((t) => int.parse(_txt(t, 'OutlineLevel'))).toList();
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i] - levels[i - 1], lessThanOrEqualTo(1));
      }
    });

    test('work package → summary, activities and tasks nest underneath', () {
      final wp = taskNamed('WP1  Platform & Enablement');
      expect(_txt(wp, 'OutlineLevel'), '1');
      expect(_txt(wp, 'Summary'), '1');
      expect(_txt(wp, 'ConstraintType'), '0');
      expect(wp.getElement('Work'), isNull, reason: 'Project rolls summaries up');
      expect(_txt(wp, 'Start'), '2026-07-01T08:00:00');
      expect(_txt(wp, 'Finish'), '2026-12-31T17:00:00');

      final design = taskNamed('Design');
      expect(_txt(design, 'OutlineNumber'), '1.1');
      expect(_txt(design, 'Start'), '2026-07-01T08:00:00');
      expect(_txt(design, 'Finish'), '2026-07-31T17:00:00');
      expect(_txt(design, 'Duration'), 'PT184H0M0S'); // 23 working days
      expect(_txt(design, 'ConstraintType'), '4');
      expect(_txt(design, 'ConstraintDate'), '2026-07-01T08:00:00');
      expect(_txt(taskNamed('Handbook'), 'OutlineNumber'), '1.5.1');
    });

    test('every leaf carries assignment-consistent work and actuals', () {
      final design = taskNamed('Design'); // assigned, not started
      expect(_txt(design, 'Work'), 'PT184H0M0S');
      expect(_txt(design, 'ActualWork'), 'PT0H0M0S');
      expect(_txt(design, 'RemainingWork'), 'PT184H0M0S');
      expect(_txt(design, 'RemainingDuration'), 'PT184H0M0S');

      final build = taskNamed('Build'); // assigned, complete
      expect(_txt(build, 'PercentComplete'), '100');
      expect(_txt(build, 'PercentWorkComplete'), '100');
      expect(_txt(build, 'ActualStart'), '2026-08-03T08:00:00');
      expect(_txt(build, 'ActualFinish'), '2026-09-18T17:00:00');
      expect(_txt(build, 'ActualWork'), _txt(build, 'Work'));
      expect(_txt(build, 'RemainingWork'), 'PT0H0M0S');

      // Unassigned leaf: no work at all.
      expect(_txt(taskNamed('Hypercare'), 'Work'), 'PT0H0M0S');
    });

    test('assignments carry Start, Finish and Work matching their task', () {
      final res = doc.rootElement.getElement('Resources')!.findElements('Resource')
          .map((r) => (_txt(r, 'UID'), _txt(r, 'Name'), _txt(r, 'Initials')))
          .toList();
      expect(res, [('1', 'Paul Murray', 'PM'), ('2', 'Sam Lee', 'SL')]);
      final byTask = {
        for (final a in doc.findAllElements('Assignment')) _txt(a, 'TaskUID'): a,
      };
      expect(byTask.keys.toSet(),
          {uidOf('Design'), uidOf('Security review'), uidOf('Build'), uidOf('Handbook')},
          reason: 'leaves with an owner only; "paul murray" dedups');
      final d = byTask[uidOf('Design')]!;
      expect(_txt(d, 'UID'), uidOf('Design'), reason: 'stable: one per task');
      expect(_txt(d, 'ResourceUID'), '1');
      expect(_txt(d, 'Start'), '2026-07-01T08:00:00');
      expect(_txt(d, 'Finish'), '2026-07-31T17:00:00');
      expect(_txt(d, 'Work'), 'PT184H0M0S');
      expect(_txt(d, 'ActualWork'), 'PT0H0M0S');
      expect(_txt(d, 'RemainingWork'), 'PT184H0M0S');
      expect(_txt(d, 'PercentWorkComplete'), '0');
      expect(d.getElement('ActualStart'), isNull);

      final b = byTask[uidOf('Build')]!;
      expect(_txt(b, 'PercentWorkComplete'), '100');
      expect(_txt(b, 'ActualStart'), '2026-08-03T08:00:00');
      expect(_txt(b, 'ActualFinish'), '2026-09-18T17:00:00');
      expect(_txt(b, 'ActualWork'), _txt(b, 'Work'));
      expect(_txt(b, 'RemainingWork'), 'PT0H0M0S');
    });

    test('a month-only milestone sits at the end of its month, remark in Text5', () {
      final m = taskNamed('Design complete');
      expect(_txt(m, 'Milestone'), '1');
      expect(_txt(m, 'Start'), '2026-07-31T17:00:00');
      expect(_txt(m, 'Finish'), '2026-07-31T17:00:00');
      expect(_txt(m, 'Duration'), 'PT0H0M0S');
      expect(_txt(m, 'Work'), 'PT0H0M0S');
      expect(m.getElement('Notes'), isNull);
      expect(_ext(m)[_remark], contains('exported at the end of that month'));
    });

    test('a milestone-type row with a multi-month window is a bar', () {
      final sit = taskNamed('SIT window');
      expect(_txt(sit, 'Milestone'), '0');
      expect(_txt(sit, 'Start'), '2026-10-01T08:00:00');
      expect(_txt(sit, 'Finish'), '2026-12-31T17:00:00');
      expect(parseMsDurationMinutes(_txt(sit, 'Duration')), greaterThan(0));
      expect(_ext(sit)[_remark], contains('exported as a bar'));
    });

    test('links have no lag and only where Keel\'s dates satisfy them', () {
      for (final l in doc.findAllElements('PredecessorLink')) {
        expect(_txt(l, 'LinkLag'), '0');
      }
      // Design (Jul) → Security review (starts Jul): contradicted, left out.
      expect(taskNamed('Security review').getElement('PredecessorLink'), isNull);
      expect(out.warnings.join('\n'),
          contains('finish-to-start "Design" → "Security review"'));

      List<(String, String)> links(String name) => [
            for (final l in taskNamed(name).findElements('PredecessorLink'))
              (_txt(l, 'PredecessorUID'), _txt(l, 'Type')),
          ];
      expect(links('Design complete'), [(uidOf('Design'), '1')]);
      expect(links('Build'), [(uidOf('Design complete'), '1')]);
      // SS from Build, and the link into the summary "Transition" lands on
      // its first child.
      expect(links('Handbook').toSet(),
          {(uidOf('Build'), '3'), (uidOf('Security review'), '1')});
      // Out of "Transition" leaves from its last child.
      expect(links('Priority 1 Go-Live'), [(uidOf('Hypercare'), '1')]);
      expect(out.warnings.join('\n'), contains('re-pointed'));
    });

    test('a parent keeps its window as the Deadline, plus status and owner', () {
      final p = taskNamed('Transition');
      expect(_txt(p, 'Summary'), '1');
      expect(_txt(p, 'Start'), '2026-09-01T08:00:00');
      expect(_txt(p, 'Finish'), '2026-12-31T17:00:00', reason: 'rolled up from Hypercare');
      expect(_txt(p, 'Deadline'), '2026-10-30T17:00:00');
      expect(p.getElement('PredecessorLink'), isNull);
      expect(_ext(p)[_status], 'Not started');
      expect(_ext(p)[_owner], 'Paul Murray');
      expect(_ext(p)[_remark], contains('Keel commitment window: Sep 26 – Oct 26'));
      // Hypercare runs to Dec, past the Sep–Oct window: listed, not moved.
      expect(out.warnings.join('\n'),
          contains('"Hypercare" (1 Oct 26 – 31 Dec 26) runs past its parent "Transition"'));
    });

    test('hard deadlines are pinned milestones with a Deadline', () {
      final g = taskNamed('Priority 1 Go-Live');
      expect(_txt(g, 'Milestone'), '1');
      expect(_txt(g, 'ConstraintType'), '2');
      expect(_txt(g, 'Start'), '2026-12-31T17:00:00');
      expect(_txt(g, 'Deadline'), '2026-12-31T17:00:00');
      final hd = taskNamed('Go-live by 15 Jan');
      expect(_txt(hd, 'OutlineLevel'), '1');
      expect(_txt(hd, 'Start'), '2027-01-15T17:00:00');
      expect(_ext(hd)[_keelId], 'hard-deadline:h');
    });

    test('Text1–Text5: status, scenario, owner, Keel ID, remark', () {
      final defs = doc.rootElement.getElement('ExtendedAttributes')!
          .findElements('ExtendedAttribute')
          .map((e) => (_txt(e, 'FieldID'), _txt(e, 'FieldName'), _txt(e, 'Alias')))
          .toList();
      expect(defs, [
        (_status, 'Text1', 'Keel status'),
        (_scenario, 'Text2', 'Keel scenario'),
        (_owner, 'Text3', 'Keel owner'),
        (_keelId, 'Text4', 'Keel ID'),
        (_remark, 'Text5', 'Keel remark'),
      ]);
      final build = _ext(taskNamed('Build'));
      expect(build[_status], 'Complete');
      expect(build[_scenario], 'Anchor Aug 26 · Likely Sep 26 · Safe Oct 26 · Driven by R1');
      expect(build[_owner], 'paul murray');
      expect(build[_keelId], 'build');
      expect(_ext(taskNamed('WP1  Platform & Enablement'))[_keelId], 'wpA');
    });

    test('public notes: what people wrote, no Keel history or explanations', () {
      final notes = _txt(taskNamed('Design'), 'Notes');
      expect(notes, contains('Kick-off with vendor'));
      expect(notes, isNot(contains('Re-planned')));
      expect(notes, isNot(contains('AI view')));
      expect(notes, isNot(contains('Added on plan review')));
      expect(notes, isNot(contains('Marked critical')));
      expect(_txt(taskNamed('Build'), 'Notes'),
          contains('External dependency: Vendor contract signed'));
    });

    test('Baseline 0 from Keel\'s month baseline', () {
      final bl = taskNamed('Design').getElement('Baseline')!;
      _expectInOrder(bl.childElements.map((e) => e.name.local).toList(),
          kMsBaselineOrder, 'Baseline');
      expect(_txt(bl, 'Number'), '0');
      expect(_txt(bl, 'Start'), '2026-06-01T08:00:00');
      expect(_txt(bl, 'Finish'), '2026-06-30T17:00:00');
      expect(_txt(bl, 'Duration'), 'PT176H0M0S'); // 22 working days
      expect(taskNamed('Build').getElement('Baseline'), isNull, reason: 'not baselined');
      // The work package's baseline rolls up from its children.
      final wp = taskNamed('WP1  Platform & Enablement').getElement('Baseline')!;
      expect(_txt(wp, 'Start'), '2026-06-01T08:00:00');
    });

    test('warnings name what was left out', () {
      final w = out.warnings.join('\n');
      expect(w, contains('Empty package'));
      expect(w, contains('Someday maybe'));
      expect(tasks.where((t) => _txt(t, 'Name') == 'Someday maybe'), isEmpty);
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

  group('options', () {
    test('pin dates writes leaves as manually scheduled', () async {
      final db = await _seed();
      addTearDown(db.close);
      final out = await _build(db, options: const MsProjectOptions(pinDates: true));
      expect(out.errors, isEmpty);
      final tasks = XmlDocument.parse(out.xml).findAllElements('Task').toList();
      for (final t in tasks) {
        _expectInOrder(t.childElements.map((e) => e.name.local).toList(),
            kMsTaskOrder, 'Task ${_txt(t, 'Name')}');
        if (_txt(t, 'Summary') == '1') {
          expect(_txt(t, 'Manual'), '0', reason: 'summaries roll up');
          continue;
        }
        expect(_txt(t, 'Manual'), '1');
        expect(_txt(t, 'ManualStart'), _txt(t, 'Start'));
        expect(_txt(t, 'ManualFinish'), _txt(t, 'Finish'));
        expect(_txt(t, 'ManualDuration'), _txt(t, 'Duration'));
        expect(_txt(t, 'ConstraintType'), '0');
        expect(t.getElement('ConstraintDate'), isNull);
      }
      final root = XmlDocument.parse(out.xml).rootElement;
      expect(_txt(root, 'NewTasksAreManual'), '0');
    });

    test('all notes keeps Keel history and explanations', () async {
      final db = await _seed();
      addTearDown(db.close);
      final out = await _build(db, options: const MsProjectOptions(notes: MsNotesMode.all));
      expect(out.errors, isEmpty);
      final design = XmlDocument.parse(out.xml).findAllElements('Task')
          .firstWhere((t) => _txt(t, 'Name') == 'Design');
      expect(_txt(design, 'Notes'), contains('Re-planned 2026-10-01'));
      expect(_txt(design, 'Notes'), contains('Marked critical in Keel.'));
    });

    test('resources and custom fields can be switched off', () async {
      final db = await _seed();
      addTearDown(db.close);
      final out = await MsProjectExporter.build(
        db: db, projectId: _pid, projectName: 'TAC Integration',
        now: DateTime(2026, 11, 4, 9),
        includeResources: false, includeCustomFields: false,
      );
      expect(out.errors, isEmpty);
      final root = XmlDocument.parse(out.xml).rootElement;
      expect(root.getElement('Resources'), isNull);
      expect(root.getElement('Assignments'), isNull);
      expect(root.getElement('ExtendedAttributes'), isNull);
      expect(root.findAllElements('ExtendedAttribute'), isEmpty);
      final design = root.findAllElements('Task')
          .firstWhere((t) => _txt(t, 'Name') == 'Design');
      expect(_txt(design, 'Work'), 'PT0H0M0S', reason: 'no assignment, no work');
    });
  });

  group('loops', () {
    test('two zero-gap links pointing both ways: the closing one is left out',
        () async {
      final db = await _seed();
      addTearDown(db.close);
      final dao = db.programmeGanttDao;
      for (final id in ['g1', 'g2']) {
        await dao.upsertActivity(TimelineActivitiesCompanion(
          id: Value(id), workPackageId: const Value('wpA'), projectId: const Value('p'),
          name: Value('Gate $id'), activityType: const Value('gate'),
          startMonth: const Value(4), endMonth: const Value(4), sortOrder: const Value(30),
        ));
      }
      Future<void> dep(String id, String from, String to) =>
          dao.upsertDependency(TimelineDependenciesCompanion(
            id: Value(id), projectId: const Value('p'),
            fromActivityId: Value(from), toActivityId: Value(to),
          ));
      await dep('l1', 'g1', 'g2');
      await dep('l2', 'g2', 'g1');
      final out = await _build(db);
      expect(out.errors, isEmpty);
      expect(out.warnings.join('\n'), contains('would close a loop'));
      final links = XmlDocument.parse(out.xml).findAllElements('Task')
          .where((t) => _txt(t, 'Name').startsWith('Gate '))
          .expand((t) => t.findElements('PredecessorLink'));
      expect(links, hasLength(1));
    });
  });

  group('stable UIDs and change summary', () {
    test('inserting a task mid-plan keeps every existing UID', () async {
      final db = await _seed();
      addTearDown(db.close);
      final first = await _build(db);
      await MsProjectExporter.saveState(db, _pid, first.state);
      Map<String, String> uidByKeel(String xml) => {
            for (final t in XmlDocument.parse(xml).findAllElements('Task'))
              _ext(t)[_keelId]!: _txt(t, 'UID'),
          };
      final before = uidByKeel(first.xml);

      await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
        id: Value('kickoff'), workPackageId: Value('wpA'), projectId: Value('p'),
        name: Value('Kick-off'), startMonth: Value(3), endMonth: Value(3),
        sortOrder: Value(-1),
      ));
      final second = await _build(db);
      expect(second.errors, isEmpty);
      final after = uidByKeel(second.xml);
      for (final e in before.entries) {
        expect(after[e.key], e.value, reason: e.key);
      }
      expect(int.parse(after['kickoff']!),
          greaterThan(before.values.map(int.parse).reduce((a, b) => a > b ? a : b)));
      // The row number still follows the outline.
      final kick = XmlDocument.parse(second.xml).findAllElements('Task')
          .firstWhere((t) => _txt(t, 'Name') == 'Kick-off');
      expect(_txt(kick, 'ID'), '2');
    });

    test('a removed row\'s UID is never handed out again', () async {
      final db = await _seed();
      addTearDown(db.close);
      final first = await _build(db);
      await MsProjectExporter.saveState(db, _pid, first.state);
      final sitUid = first.state.taskUids['sit']!;
      await db.programmeGanttDao.deleteActivity('sit');
      await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
        id: Value('new'), workPackageId: Value('wpA'), projectId: Value('p'),
        name: Value('New row'), startMonth: Value(3), endMonth: Value(3),
        sortOrder: Value(20),
      ));
      final second = await _build(db);
      expect(second.state.taskUids['new'], isNot(sitUid));
      expect(second.state.taskUids['sit'], sitUid, reason: 'kept on record');
    });

    test('changes since the last export', () async {
      final db = await _seed();
      addTearDown(db.close);
      final first = await _build(db);
      expect(first.changes.isFirstExport, isTrue);
      await MsProjectExporter.saveState(db, _pid, first.state);
      expect((await _build(db)).changes.isEmpty, isTrue);

      final dao = db.programmeGanttDao;
      final review = (await dao.getActivityById('review'))!;
      await dao.upsertActivity(review.toCompanion(true).copyWith(
            endMonth: const Value(5), status: const Value('at_risk')));
      final hb = (await dao.getActivityById('t1'))!;
      await dao.upsertActivity(hb.toCompanion(true).copyWith(
            parentActivityId: const Value(null), name: const Value('Ops handbook')));
      await dao.deleteActivity('m1');
      await dao.upsertActivity(const TimelineActivitiesCompanion(
        id: Value('kickoff'), workPackageId: Value('wpA'), projectId: Value('p'),
        name: Value('Kick-off'), startMonth: Value(3), endMonth: Value(3),
      ));
      final c = (await _build(db)).changes;
      expect(c.added.single, startsWith('Kick-off'));
      expect(c.removed.single, 'Design complete');
      expect(c.redated, [
        'Security review: 1 Jul 26 – 31 Aug 26 → 1 Jul 26 – 30 Sep 26',
        // Its first child left, so the parent's roll-up moved too.
        'Transition: 1 Sep 26 – 31 Dec 26 → 1 Oct 26 – 31 Dec 26',
      ]);
      expect(c.statusChanged.single, 'Security review: On track → At risk');
      expect(c.reparented.single, 'Ops handbook: Transition → WP1  Platform & Enablement');
      expect(c.renamed.single, 'Handbook → Ops handbook');
      expect(c.toText(), contains('Re-dated (2)'));
    });

    test('state survives a round trip and tolerates junk', () {
      const s = MsProjectState(
          taskUids: {'a': 5, 'b': 9}, resourceUids: {'x': 2},
          nextTaskUid: 3, nextResourceUid: 1);
      final back = MsProjectState.decode(s.encode());
      expect(back.taskUids, {'a': 5, 'b': 9});
      expect(back.nextTaskUid, 10, reason: 'never below a used UID');
      expect(back.nextResourceUid, 3);
      expect(MsProjectState.decode('not json').taskUids, isEmpty);
      expect(MsProjectState.decode(null).nextTaskUid, 1);
    });
  });

  group('self-check', () {
    late AppDatabase db;
    late String xml;
    setUpAll(() async {
      db = await _seed();
      xml = (await _build(db)).xml;
    });
    tearDownAll(() => db.close());

    test('catches a negative lag', () {
      final bad = xml.replaceFirst('<LinkLag>0</LinkLag>', '<LinkLag>-4800</LinkLag>');
      expect(validateMsProjectXml(bad).join('\n'), contains('lag of -1 days'));
    });

    test('catches an assignment without dates', () {
      final bad = xml.replaceFirst(
          RegExp(r'<Start>[^<]*</Start>\s*<Units>'), '<Units>');
      expect(validateMsProjectXml(bad).join('\n'), contains('Start/Finish missing'));
    });

    test('catches a duration that disagrees with the dates', () {
      final bad = xml.replaceFirst('<Duration>PT184H0M0S</Duration>',
          '<Duration>PT176H0M0S</Duration>');
      expect(validateMsProjectXml(bad).join('\n'),
          contains('does not match the 184h of working time'));
    });

    test('catches a task starting before the project', () {
      final bad = xml.replaceFirst(
          '<StartDate>2026-07-01T08:00:00</StartDate>',
          '<StartDate>2026-07-02T08:00:00</StartDate>');
      expect(validateMsProjectXml(bad).join('\n'), contains('before the project start'));
    });

    test('catches Keel history in public notes', () {
      final bad = xml.replaceFirst('Kick-off with vendor',
          'Kick-off with vendor\nRe-planned 2026-10-01: was Jun');
      expect(validateMsProjectXml(bad).join('\n'), contains('Keel history'));
    });
  });

  group('round-trip check', () {
    late AppDatabase db;
    late String xml;
    setUpAll(() async {
      db = await _seed();
      xml = (await _build(db)).xml;
    });
    tearDownAll(() => db.close());

    test('the file Keel wrote matches itself', () {
      expect(compareMsProjectFiles(expectedXml: xml, actualXml: xml), isEmpty);
    });

    test('names every task Project moved, by field', () {
      // What Project did to assigned tasks: dragged to the project start.
      final moved = xml.replaceFirst(
          RegExp(r'(<Name>Design</Name>[\s\S]*?)<Start>2026-07-01T08:00:00</Start>'),
          r'$1<Start>2026-04-01T08:00:00</Start>');
      final d = compareMsProjectFiles(expectedXml: xml, actualXml: moved);
      expect(d, hasLength(1));
      expect(d.single, contains('"Design"'));
      expect(d.single, contains('start 1 Jul 26 08:00 → 1 Apr 26 08:00'));
    });

    test('reports lost links, owners and outline changes', () {
      var changed = xml.replaceFirst(
          RegExp(r'<PredecessorLink>[\s\S]*?</PredecessorLink>'), '');
      changed = changed.replaceFirst(
          '<OutlineLevel>3</OutlineLevel>', '<OutlineLevel>2</OutlineLevel>');
      final d = compareMsProjectFiles(expectedXml: xml, actualXml: changed).join('\n');
      expect(d, contains('link lost'));
      expect(d, contains('outline level 3 → 2'));
    });

    test('pairs by Keel ID even when Project renumbers UIDs', () {
      final doc = XmlDocument.parse(xml);
      // Swap the UIDs of the first two tasks (links follow by Keel ID).
      final ts = doc.findAllElements('Task').toList();
      final u0 = ts[0].getElement('UID')!, u1 = ts[1].getElement('UID')!;
      final a = u0.innerText, b = u1.innerText;
      u0.innerText = '9990';
      u1.innerText = '9991';
      for (final p in doc.findAllElements('PredecessorUID')) {
        if (p.innerText == a) p.innerText = '9990';
        if (p.innerText == b) p.innerText = '9991';
      }
      for (final t in doc.findAllElements('TaskUID')) {
        if (t.innerText == a) t.innerText = '9990';
        if (t.innerText == b) t.innerText = '9991';
      }
      expect(compareMsProjectFiles(expectedXml: xml, actualXml: doc.toXmlString()),
          isEmpty);
    });

    test('Project\'s own summary row (UID 0) is ignored', () {
      final withRow0 = xml.replaceFirst('<Tasks>',
          '<Tasks><Task><UID>0</UID><ID>0</ID><Name>TAC</Name><OutlineLevel>0</OutlineLevel></Task>');
      expect(compareMsProjectFiles(expectedXml: xml, actualXml: withRow0), isEmpty);
    });
  });

  group('no month-0 anchor', () {
    test('falls back to the project start month and says so', () async {
      final db = await _seed(withAnchor: false);
      addTearDown(db.close);
      final out = await _build(db);
      expect(out.warnings.first, contains('placed at 2026-06-01'));
      final design = XmlDocument.parse(out.xml).findAllElements('Task')
          .firstWhere((t) => _txt(t, 'Name') == 'Design');
      expect(_txt(design, 'Start'), '2026-09-01T08:00:00');
    });
  });
}
