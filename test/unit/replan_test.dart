import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/plan/replan.dart';

/// Re-plan arithmetic: slipped not-started work moves to today, the
/// consequences flow through the dependency graph, started work never
/// moves, and every move carries a reason in words.
///
/// Month 0 is June 2026 throughout; "today" is 5 Oct 2026 (month 4).
const _m0 = '2026-06-01';
final _today = DateTime(2026, 10, 5);

TimelineActivity _act(
  String id, {
  int? start,
  int? end,
  String? startDate,
  String? endDate,
  String status = 'not_started',
  String type = 'activity',
  String? sourceProjectId,
  bool critical = false,
}) =>
    TimelineActivity(
      id: id,
      workPackageId: 'wp',
      projectId: 'p1',
      name: id,
      activityType: type,
      status: status,
      startMonth: start,
      endMonth: end ?? start,
      startDate: startDate,
      endDate: endDate,
      isCritical: critical,
      isBaseline: false,
      sortOrder: 0,
      sourceProjectId: sourceProjectId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

TimelineDependency _dep(String from, String to,
        {String type = 'finish_to_start', String? external}) =>
    TimelineDependency(
      id: 'd-$from-$to',
      projectId: 'p1',
      fromActivityId: external != null ? '' : from,
      toActivityId: to,
      dependencyType: external != null ? 'external' : type,
      externalLabel: external,
      createdAt: DateTime(2026),
    );

ReplanProposal _run(List<TimelineActivity> acts,
        [List<TimelineDependency> deps = const [], String? deadline]) =>
    buildReplanProposal(
      activities: acts,
      dependencies: deps,
      month0Date: _m0,
      hardDeadlineDate: deadline,
      today: _today,
    );

void main() {
  group('candidates', () {
    test('a month-only row starting before this month slips to this month, '
        'duration kept', () {
      final p = _run([_act('a', start: 1, end: 3)]);
      final c = p.changes.single;
      expect(c.slipped, isTrue);
      expect(c.toStartMonth, 4);
      expect(c.toEndMonth, 6);
      expect(c.reasons.single, contains('Start was Jul 2026'));
    });

    test('a dated row slips to today by days and its months follow', () {
      final p = _run([
        _act('a', start: 1, end: 2,
            startDate: '2026-07-10', endDate: '2026-08-20'),
      ]);
      final c = p.changes.single;
      expect(c.toStartDate, '2026-10-05');
      expect(c.toEndDate, '2026-11-15', reason: '41-day duration kept');
      expect(c.toStartMonth, 4);
      expect(c.toEndMonth, 5);
    });

    test('a start-only date moves the start by days and keeps the end at '
        'month precision — never an invented end date', () {
      final p = _run([
        _act('a', start: 1, end: 3, startDate: '2026-07-10'),
      ]);
      final c = p.changes.single;
      expect(c.toStartDate, '2026-10-05');
      expect(c.toEndDate, isNull);
      expect(c.toStartMonth, 4);
      expect(c.toEndMonth, 6, reason: 'three-month span kept');
    });

    test('the current month, the future, started, complete and cascaded '
        'rows are left alone', () {
      final p = _run([
        _act('thisMonth', start: 4),
        _act('future', start: 6),
        _act('started', start: 1, status: 'amber'),
        _act('done', start: 1, status: 'complete'),
        _act('foreign', start: 1, sourceProjectId: 'other'),
        _act('undated'),
      ]);
      expect(p.changes, isEmpty);
      expect(p.warnings, isEmpty);
    });

    test('no month-0 anchor means no changes and one warning', () {
      final p = buildReplanProposal(
        activities: [_act('a', start: 1)],
        dependencies: const [],
        month0Date: null,
        today: _today,
      );
      expect(p.changes, isEmpty);
      expect(p.warnings.single.message, contains('month-0 anchor'));
    });
  });

  group('dependencies', () {
    test('finish → start pushes a not-started successor and says why', () {
      // a: Jul–Sep slips to Oct–Dec. b: Oct–Nov must now start Dec.
      final p = _run(
        [_act('a', start: 1, end: 3), _act('b', start: 4, end: 5)],
        [_dep('a', 'b')],
      );
      final b = p.changeFor('b')!;
      expect(b.slipped, isFalse);
      expect(b.pushedBy, ['a']);
      expect(b.toStartMonth, 6);
      expect(b.toEndMonth, 7);
      expect(b.reasons.single, contains('Pushed by a (finish → start)'));
      expect(b.reasons.single, contains('Dec 2026'));
      expect(p.slippedCount, 1);
      expect(p.pushedCount, 1);
    });

    test('pushes chain through several hops', () {
      final p = _run(
        [
          _act('a', start: 1, end: 1),
          _act('b', start: 5, end: 5),
          _act('c', start: 6, end: 6),
        ],
        [_dep('a', 'b'), _dep('b', 'c')],
      );
      // a → Oct(4). b must start ≥ 4: already 5, untouched. c untouched.
      expect(p.changes.map((c) => c.id), ['a']);

      final p2 = _run(
        [
          _act('a', start: 1, end: 3),
          _act('b', start: 5, end: 5),
          _act('c', start: 5, end: 6),
        ],
        [_dep('a', 'b'), _dep('b', 'c')],
      );
      // a → Oct–Dec(4–6). b → 6. c must start ≥ 6 → 6–7.
      expect(p2.changeFor('b')!.toStartMonth, 6);
      expect(p2.changeFor('c')!.toStartMonth, 6);
      expect(p2.changeFor('c')!.toEndMonth, 7);
      expect(p2.changeFor('c')!.pushedBy, ['b']);
    });

    test('start → start and finish → finish respect their own anchors', () {
      final ss = _run(
        [_act('a', start: 1, end: 3), _act('b', start: 2, end: 2)],
        [_dep('a', 'b', type: 'start_to_start')],
      );
      // a starts 4 now; b must start ≥ 4.
      expect(ss.changeFor('b')!.toStartMonth, 4);

      final ff = _run(
        [_act('a', start: 1, end: 3), _act('b', start: 4, end: 5)],
        [_dep('a', 'b', type: 'finish_to_finish')],
      );
      // a ends 6 now; b must end ≥ 6 → 5–6.
      expect(ff.changeFor('b')!.toStartMonth, 5);
      expect(ff.changeFor('b')!.toEndMonth, 6);
    });

    test('day-level finish → start lands the day after the predecessor',
        () {
      final p = _run(
        [
          _act('a', start: 1, end: 1,
              startDate: '2026-07-01', endDate: '2026-07-10'),
          _act('b', start: 4, end: 4,
              startDate: '2026-10-06', endDate: '2026-10-08'),
        ],
        [_dep('a', 'b')],
      );
      // a → 5 Oct–14 Oct. b must start 15 Oct, 3-day duration kept.
      expect(p.changeFor('a')!.toEndDate, '2026-10-14');
      expect(p.changeFor('b')!.toStartDate, '2026-10-15');
      expect(p.changeFor('b')!.toEndDate, '2026-10-17');
    });

    test('a slipped row waits for a late, still-running predecessor', () {
      // a is in progress and runs Nov 2026–Jan 2027. b should have
      // started in July but is gated by a, so today is not good enough.
      final p = _run(
        [
          _act('a', start: 5, end: 7, status: 'green'),
          _act('b', start: 1, end: 2),
        ],
        [_dep('a', 'b')],
      );
      final b = p.changes.single;
      expect(b.id, 'b');
      expect(b.slipped, isTrue);
      expect(b.toStartMonth, 7);
      expect(b.toEndMonth, 8);
      expect(b.reasons.last, contains('Held by a (finish → start)'));
      expect(b.reasons.last, contains('still running'));
      expect(p.warnings, isEmpty, reason: 'nothing untouched is inconsistent');
    });

    test('a start-only predecessor anchors finish → start at month level',
        () {
      final p = _run(
        [
          _act('a', start: 1, end: 3, startDate: '2026-07-10'),
          _act('b', start: 4, end: 4, startDate: '2026-10-06'),
        ],
        [_dep('a', 'b')],
      );
      // a → start 5 Oct, months 4–6 (no end date). b must start ≥ month 6.
      expect(p.changeFor('b')!.toStartMonth, 6);
      expect(p.changeFor('b')!.toStartDate, '2026-12-06',
          reason: 'day of month kept when moved by whole months');
    });

    test('a started successor never moves; the conflict is a warning', () {
      final p = _run(
        [
          _act('a', start: 1, end: 3),
          _act('b', start: 4, end: 5, status: 'green'),
        ],
        [_dep('a', 'b')],
      );
      expect(p.changes.map((c) => c.id), ['a']);
      expect(p.warnings.single.activityId, 'b');
      expect(p.warnings.single.message, contains('already started'));
    });

    test('external dependencies never move anything but are called out',
        () {
      final p = _run(
        [_act('a', start: 1, end: 2)],
        [_dep('', 'a', external: 'Vendor contract')],
      );
      final a = p.changes.single;
      expect(a.toStartMonth, 4);
      expect(a.reasons.last, contains('Vendor contract (external)'));
    });

    test('a cycle terminates', () {
      final p = _run(
        [_act('a', start: 1, end: 1), _act('b', start: 1, end: 1)],
        [_dep('a', 'b'), _dep('b', 'a')],
      );
      expect(p.changes.length, 2);
    });
  });

  group('extensions and order', () {
    test('an accepted extension lengthens the row and pushes successors',
        () {
      final p = _run(
        [_act('a', start: 1, end: 3), _act('b', start: 7, end: 7)],
        [_dep('a', 'b')],
      );
      expect(p.changes.map((c) => c.id), ['a'], reason: 'b has room');

      final p2 = buildReplanProposal(
        activities: [_act('a', start: 1, end: 3), _act('b', start: 7, end: 7)],
        dependencies: [_dep('a', 'b')],
        month0Date: _m0,
        today: _today,
        extensions: {'a': const ReplanExtension(months: 2)},
      );
      final a = p2.changeFor('a')!;
      expect(a.toStartMonth, 4);
      expect(a.toEndMonth, 8, reason: 'Oct–Dec plus two months');
      expect(a.reasons.last, contains('Extended from Dec 2026 to Feb 2027'));
      expect(p2.changeFor('b')!.toStartMonth, 8);
    });

    test('a dated extension adds days and keeps months in step', () {
      final p = buildReplanProposal(
        activities: [
          _act('a', start: 1, end: 1,
              startDate: '2026-07-01', endDate: '2026-07-10'),
        ],
        dependencies: const [],
        month0Date: _m0,
        today: _today,
        extensions: {'a': const ReplanExtension(days: 30)},
      );
      final a = p.changes.single;
      expect(a.toStartDate, '2026-10-05');
      expect(a.toEndDate, '2026-11-13');
      expect(a.toEndMonth, 5);
    });

    test('extensions on rows that cannot move are ignored', () {
      final p = buildReplanProposal(
        activities: [_act('a', start: 1, end: 3, status: 'green')],
        dependencies: const [],
        month0Date: _m0,
        today: _today,
        extensions: {'a': const ReplanExtension(months: 2)},
      );
      expect(p.changes, isEmpty);
    });

    test('changes come back predecessors first, plan order otherwise', () {
      // Plan order c, b, a; arrows a → b → c. All slipped.
      final p = _run(
        [
          _act('c', start: 1, end: 1),
          _act('b', start: 1, end: 1),
          _act('a', start: 1, end: 1),
        ],
        [_dep('a', 'b'), _dep('b', 'c')],
      );
      expect(p.changes.map((c) => c.id), ['a', 'b', 'c']);
    });
  });

  group('overrides', () {
    test('a hand-set span wins, pins the row and still pushes successors',
        () {
      final p = buildReplanProposal(
        activities: [_act('a', start: 1, end: 3), _act('b', start: 7, end: 7)],
        dependencies: [_dep('a', 'b')],
        month0Date: _m0,
        today: _today,
        overrides: {'a': const ReplanOverride(startMonth: 6, endMonth: 9)},
      );
      final a = p.changeFor('a')!;
      expect(a.pinned, isTrue);
      expect((a.toStartMonth, a.toEndMonth), (6, 9));
      expect(a.reasons.last, contains('Set by you on review: Dec 2026 – Mar 2027'));
      expect(p.changeFor('b')!.toStartMonth, 9, reason: 'pushed by the new end');
    });

    test('a pinned row is never pushed; a contradiction is reported', () {
      final p = buildReplanProposal(
        activities: [_act('a', start: 1, end: 3), _act('b', start: 1, end: 2)],
        dependencies: [_dep('a', 'b')],
        month0Date: _m0,
        today: _today,
        overrides: {'b': const ReplanOverride(startMonth: 4, endMonth: 5)},
      );
      // a slips to Oct–Dec (4–6); b pinned at 4–5 contradicts it.
      expect(p.changeFor('b')!.toStartMonth, 4);
      expect(p.warnings.single.message,
          contains('The span you set for b starts before a'));
    });

    test('a dated override derives its months', () {
      final p = buildReplanProposal(
        activities: [
          _act('a', start: 1, end: 2, startDate: '2026-07-01', endDate: '2026-08-15'),
        ],
        dependencies: const [],
        month0Date: _m0,
        today: _today,
        overrides: {
          'a': const ReplanOverride(startDate: '2026-11-02', endDate: '2027-01-20'),
        },
      );
      final a = p.changes.single;
      expect(a.toStartDate, '2026-11-02');
      expect((a.toStartMonth, a.toEndMonth), (5, 7));
    });
  });

  group('warnings', () {
    test('a move past the hard deadline is flagged', () {
      final p = _run(
        [_act('a', start: 1, end: 6)],
        const [],
        '2026-12-31',
      );
      // a → Oct 2026–Mar 2027 (4–9), deadline is month 6.
      expect(p.warnings.single.message, contains('past the hard deadline'));
      expect(p.warnings.single.message, contains('31 Dec 2026'));
    });

    test('a pushed milestone is the headline', () {
      final p = _run(
        [
          _act('a', start: 1, end: 3),
          _act('go-live', start: 5, type: 'milestone'),
        ],
        [_dep('a', 'go-live')],
      );
      final m = p.changeFor('go-live')!;
      expect(m.isSinglePoint, isTrue);
      expect(m.toStartMonth, 6);
      expect(p.warnings.single.message, contains('go-live is a milestone'));
    });
  });

  group('labels and notes', () {
    final m0 = DateTime(2026, 6, 1);
    test('spans read as humans write them', () {
      expect(
          replanSpanLabel(startMonth: 1, endMonth: 3, startDate: null,
              endDate: null, month0: m0),
          'Jul–Sep 2026');
      expect(
          replanSpanLabel(startMonth: 5, endMonth: 8, startDate: null,
              endDate: null, month0: m0),
          'Nov 2026 – Feb 2027');
      expect(
          replanSpanLabel(startMonth: 4, endMonth: 4, startDate: null,
              endDate: null, month0: m0),
          'Oct 2026');
      expect(
          replanSpanLabel(startMonth: null, endMonth: null,
              startDate: '2026-10-05', endDate: '2026-11-15', month0: m0),
          '5 Oct 2026 – 15 Nov 2026');
    });

    test('the history note says was, now and why', () {
      final p = _run([_act('a', start: 1, end: 3)]);
      final note = replanNote(p.changes.single, m0, today: _today);
      expect(note, startsWith('Re-planned 2026-10-05: was Jul–Sep 2026, now Oct–Dec 2026.'));
      expect(note, contains('before this month'));
      final withAi = replanNote(p.changes.single, m0, today: _today,
          aiView: 'AI view (medium confidence): Scope grew.');
      expect(withAi, endsWith('AI view (medium confidence): Scope grew.'));
    });
  });

  group('apply', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.memory();
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P'));
      await db.programmeGanttDao
          .upsertWorkPackage(const TimelineWorkPackagesCompanion(
        id: Value('wp'), projectId: Value('p1'), name: Value('WP'),
        sortOrder: Value(0),
      ));
      await db.programmeGanttDao
          .upsertActivity(const TimelineActivitiesCompanion(
        id: Value('a'), workPackageId: Value('wp'), projectId: Value('p1'),
        name: Value('Build'), startMonth: Value(1), endMonth: Value(3),
        notes: Value('Existing note'), sortOrder: Value(0),
      ));
    });
    tearDown(() => db.close());

    test('writes the new span and appends the note', () async {
      await db.programmeGanttDao.applyReplan([
        const ReplanWrite(
          id: 'a', startMonth: 4, endMonth: 6,
          startDate: null, endDate: null,
          note: 'Re-planned 2026-10-05: was Jul–Sep 2026, now Oct–Dec 2026.',
        ),
      ]);
      final a = (await db.programmeGanttDao.getActivityById('a'))!;
      expect(a.startMonth, 4);
      expect(a.endMonth, 6);
      expect(a.notes, 'Existing note\nRe-planned 2026-10-05: was Jul–Sep 2026, now Oct–Dec 2026.');
    });
  });
}
