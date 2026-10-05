import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/plan/replan.dart';
import 'package:keel/core/plan/replan_assist.dart';
import 'package:drift/drift.dart' show Value;

/// The AI overlay never does date maths: the prompt asks for extra
/// months or days only, and the parser clamps whatever comes back.
void main() {
  final m0 = DateTime(2026, 6, 1);

  ReplanChange change({bool dated = false}) => ReplanChange(
        activity: TimelineActivity(
          id: 'a',
          workPackageId: 'wp',
          projectId: 'p1',
          name: 'Build adapter',
          activityType: 'activity',
          status: 'not_started',
          startMonth: 1,
          endMonth: 3,
          notes: 'Scope grew after the vendor workshop.',
          isCritical: true,
          isBaseline: false,
          sortOrder: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        fromStartMonth: 1, fromEndMonth: 3,
        fromStartDate: dated ? '2026-07-01' : null,
        fromEndDate: dated ? '2026-09-30' : null,
        toStartMonth: 4, toEndMonth: 6,
        toStartDate: dated ? '2026-10-05' : null,
        toEndDate: dated ? '2027-01-03' : null,
        slipped: true,
        pushedBy: const [],
        reasons: const ['Start was Jul 2026, before this month, and work has not started.'],
        isSinglePoint: false,
        isCritical: true,
      );

  group('prompt', () {
    test('carries the context and asks for months on a month-level row', () {
      final p = replanAssistPrompt(
        change: change(),
        month0: m0,
        workPackageName: 'Integration',
        predecessors: ['Sign contract (finish → start)'],
        successors: ['SIT (finish → start)'],
        linkedItems: ['R3 Vendor slips — open'],
        openActions: 2,
        projectContext: 'PROJECT CONTEXT',
      );
      expect(p.system, startsWith('PROJECT CONTEXT'));
      expect(p.system, contains('Do not change the start'));
      expect(p.user, contains('Activity: Build adapter'));
      expect(p.user, contains('Work package: Integration'));
      expect(p.user, contains('Planned: Jul–Sep 2026'));
      expect(p.user, contains('Proposed by the engine: Oct–Dec 2026'));
      expect(p.user, contains('Depends on: Sign contract'));
      expect(p.user, contains('Gates: SIT'));
      expect(p.user, contains('Linked risks and issues: R3 Vendor slips'));
      expect(p.user, contains('Open actions under it: 2'));
      expect(p.user, contains('"extra_months": <integer 0..6'));
      expect(p.user, isNot(contains('extra_days')));
    });

    test('asks for days on a dated row and omits empty lines', () {
      final p = replanAssistPrompt(
        change: change(dated: true),
        month0: m0,
        workPackageName: null,
        predecessors: const [],
        successors: const [],
        linkedItems: const [],
        openActions: 0,
      );
      expect(p.system, isNot(contains('---')));
      expect(p.user, contains('"extra_days": <integer 0..180'));
      expect(p.user, isNot(contains('Work package:')));
      expect(p.user, isNot(contains('Depends on:')));
      expect(p.user, isNot(contains('Open actions')));
    });
  });

  group('parse', () {
    test('a clean object', () {
      final a = parseReplanAdvice(
        '{"extra_months": 1, "confidence": "medium", '
        '"rationale": "The vendor workshop widened scope.", '
        '"watch": ["Vendor contract", "SIT entry"]}',
        dated: false,
      )!;
      expect(a.extension.months, 1);
      expect(a.extension.days, 0);
      expect(a.agrees, isFalse);
      expect(a.confidence, 'medium');
      expect(a.rationale, 'The vendor workshop widened scope.');
      expect(a.watch, ['Vendor contract', 'SIT entry']);
    });

    test('fences, prose and a trailing note are tolerated', () {
      final a = parseReplanAdvice(
        'Sure, here is my view:\n```json\n{"extra_months": 0, '
        '"confidence": "high", "rationale": "Holds.", "watch": []}\n```\nHope that helps.',
        dated: false,
      )!;
      expect(a.agrees, isTrue);
      expect(a.confidence, 'high');
    });

    test('out-of-range and wrong-unit values are clamped, never trusted', () {
      final big = parseReplanAdvice(
          '{"extra_months": 18, "confidence": "high", "rationale": "x"}',
          dated: false)!;
      expect(big.extension.months, kReplanMaxExtraMonths);
      final neg = parseReplanAdvice(
          '{"extra_days": -5, "confidence": "shrug", "rationale": "x", "watch": "no"}',
          dated: true)!;
      expect(neg.extension.days, 0);
      expect(neg.confidence, 'low');
      expect(neg.watch, isEmpty);
      final wrongUnit = parseReplanAdvice(
          '{"extra_months": 2, "confidence": "high", "rationale": "x"}',
          dated: true)!;
      expect(wrongUnit.extension.isZero, isTrue,
          reason: 'months are meaningless on a dated row');
      final capped = parseReplanAdvice(
          '{"extra_months": 1, "rationale": "x", "watch": ["a","b","c","d"]}',
          dated: false)!;
      expect(capped.watch.length, 3);
    });

    test('no object means no advice', () {
      expect(parseReplanAdvice('I cannot say.', dated: false), isNull);
      expect(parseReplanAdvice('{"broken": ', dated: false), isNull);
      expect(parseReplanAdvice('[1,2]', dated: false), isNull);
    });
  });

  group('sub-tasks', () {
    test('the prompt asks for ordered, weighted tasks and no dates', () {
      final p = replanSubtaskPrompt(
        change: change(),
        month0: m0,
        workPackageName: 'Integration',
        linkedItems: const ['R3 Vendor slips — open'],
      );
      expect(p.system, contains('break the activity into its delivery steps'));
      expect(p.user, contains('Window: Oct–Dec 2026'));
      expect(p.user, contains('3 to 6 sequential tasks'));
      expect(p.user, contains('"weight": <1..5>'));
    });

    test('the parser keeps order, clamps weights, drops blanks and caps', () {
      final tasks = parseReplanSubtasks(
        '```json\n{"tasks": [{"name": "Design", "weight": 9}, {"name": "", "weight": 2}, '
        '{"name": "Build", "weight": 0}, {"name": "Test", "weight": "3"}, '
        '{"name": "e"}, {"name": "f"}, {"name": "g"}, {"name": "h"}]}\n```',
      );
      expect(tasks.map((t) => t.name), ['Design', 'Build', 'Test', 'e', 'f', 'g']);
      expect(tasks.map((t) => t.weight), [5, 1, 3, 1, 1, 1]);
      expect(parseReplanSubtasks('nope'), isEmpty);
      expect(parseReplanSubtasks('{"tasks": "x"}'), isEmpty);
    });

    test('a month window is split by weight, back to back, covering all', () {
      final spans = partitionSpan(
        startMonth: 4, endMonth: 9, startDate: null, endDate: null,
        weights: [1, 2, 3], month0: m0,
      );
      // Six months, weights 1:2:3 → 1, 2, 3 months.
      expect(spans.map((s) => (s.startMonth, s.endMonth)),
          [(4, 4), (5, 6), (7, 9)]);
      expect(spans.every((s) => s.startDate == null), isTrue);
    });

    test('more tasks than months overlap rather than vanish', () {
      final spans = partitionSpan(
        startMonth: 4, endMonth: 5, startDate: null, endDate: null,
        weights: [1, 1, 1, 1], month0: m0,
      );
      expect(spans.length, 4);
      expect(spans.first.startMonth, 4);
      expect(spans.last.endMonth, 5);
      expect(spans.every((s) => s.startMonth! <= s.endMonth!), isTrue);
    });

    test('a dated window is split by days and months follow', () {
      final spans = partitionSpan(
        startMonth: 4, endMonth: 5,
        startDate: '2026-10-05', endDate: '2026-11-13', // 40 days
        weights: [1, 1], month0: m0,
      );
      expect(spans[0].startDate, '2026-10-05');
      expect(spans[0].endDate, '2026-10-24');
      expect(spans[1].startDate, '2026-10-25');
      expect(spans[1].endDate, '2026-11-13');
      expect(spans[0].endMonth, 4);
      expect(spans[1].endMonth, 5);
    });

    test('addPlannedTasks writes ordered tasks with their own spans', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P'));
      await db.programmeGanttDao.upsertWorkPackage(const TimelineWorkPackagesCompanion(
        id: Value('wp'), projectId: Value('p1'), name: Value('WP'), sortOrder: Value(0),
      ));
      await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
        id: Value('a'), workPackageId: Value('wp'), projectId: Value('p1'),
        name: Value('Build'), startMonth: Value(4), endMonth: Value(6), sortOrder: Value(0),
      ));
      final ids = await db.programmeGanttDao.addPlannedTasks('a', const [
        PlannedTask(id: 't1', name: 'Design', startMonth: 4, endMonth: 4),
        PlannedTask(id: 't2', name: 'Build', startMonth: 5, endMonth: 6),
      ]);
      expect(ids, ['t1', 't2']);
      final tasks = await db.programmeGanttDao.getTasksForActivity('a');
      expect(tasks.map((t) => t.name), ['Design', 'Build']);
      expect(tasks.map((t) => t.sortOrder), [0, 1]);
      expect(tasks.last.startMonth, 5);
      expect(tasks.last.workPackageId, 'wp');
      final parent = (await db.programmeGanttDao.getActivityById('a'))!;
      expect((parent.startMonth, parent.endMonth), (4, 6),
          reason: 'the parent window is a commitment and never moves');
    });
  });
}
