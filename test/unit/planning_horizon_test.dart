import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/helm/planning_horizon.dart';

// Thursday 24 Sep 2026. Week = Mon 21 … Sun 27; next week Mon 28 … Sun 4 Oct.
final _today = DateTime(2026, 9, 24);
final _t = DateTime(2026, 1, 1);

({ProjectAction action, String projectName}) _action(String id, String? due,
        {String status = 'open', String priority = 'medium'}) =>
    (
      action: ProjectAction(
        id: id,
        projectId: 'p1',
        ref: id.toUpperCase(),
        description: 'Action $id',
        dueDate: due,
        status: status,
        priority: priority,
        source: 'manual',
        isParent: false,
        createdAt: _t,
        updatedAt: _t,
      ),
      projectName: 'TAC',
    );

({Decision decision, String projectName}) _decision(String id, String? due,
        {String status = 'pending'}) =>
    (
      decision: Decision(
        id: id,
        projectId: 'p1',
        ref: id.toUpperCase(),
        description: 'Decide $id',
        status: status,
        dueDate: due,
        source: 'manual',
        createdAt: _t,
        updatedAt: _t,
      ),
      projectName: 'TAC',
    );

({ProgramDependency dependency, String projectName}) _dep(String id, String? due,
        {String status = 'open'}) =>
    (
      dependency: ProgramDependency(
        id: id,
        projectId: 'p1',
        ref: id.toUpperCase(),
        description: 'Dep $id',
        dependencyType: 'inbound',
        status: status,
        dueDate: due,
        source: 'manual',
        createdAt: _t,
        updatedAt: _t,
      ),
      projectName: 'TAC',
    );

({Risk risk, String projectName}) _risk(String id,
        {String? due, String? review, bool steerco = false, String status = 'open'}) =>
    (
      risk: Risk(
        id: id,
        projectId: 'p1',
        ref: id.toUpperCase(),
        title: 'Risk $id',
        description: 'long',
        likelihood: 'likely',
        impact: 'major',
        strategy: 'treat',
        steerco: steerco,
        dueDate: due,
        nextReviewAt: review,
        status: status,
        source: 'manual',
        createdAt: _t,
        updatedAt: _t,
      ),
      projectName: 'TAC',
    );

({Issue issue, String projectName}) _issue(String id, String? due) => (
      issue: Issue(
        id: id,
        projectId: 'p1',
        ref: id.toUpperCase(),
        description: 'Issue $id',
        escalationRequired: false,
        priority: 'high',
        status: 'open',
        dueDate: due,
        source: 'manual',
        createdAt: _t,
        updatedAt: _t,
      ),
      projectName: 'TAC',
    );

({TimelineActivity activity, String projectName, String? wpCode}) _act(
        String id,
        {String? start,
        String? end,
        String type = 'activity',
        String status = 'not_started'}) =>
    (
      activity: TimelineActivity(
        id: id,
        workPackageId: 'wp',
        projectId: 'p1',
        name: 'Act $id',
        activityType: type,
        startDate: start,
        endDate: end,
        status: status,
        isCritical: false,
        isBaseline: false,
        sortOrder: 0,
        createdAt: _t,
        updatedAt: _t,
      ),
      projectName: 'TAC',
      wpCode: 'WP1',
    );

PlanningHorizon _build({
  List<({ProjectAction action, String projectName})> actions = const [],
  List<({Decision decision, String projectName})> decisions = const [],
  List<({ProgramDependency dependency, String projectName})> deps = const [],
  List<({Risk risk, String projectName})> risks = const [],
  List<({Issue issue, String projectName})> issues = const [],
  List<({TimelineActivity activity, String projectName, String? wpCode})>
      acts = const [],
}) =>
    buildPlanningHorizon(
      today: _today,
      actions: actions,
      decisions: decisions,
      dependencies: deps,
      risks: risks,
      issues: issues,
      activities: acts,
    );

void main() {
  test('buckets actions into behind, today, rest of week and next week', () {
    final h = _build(actions: [
      _action('a1', '2026-09-22'), // Tue — behind
      _action('a2', '2026-09-24'), // today
      _action('a3', '2026-09-25'), // Fri
      _action('a4', '2026-09-27'), // Sun — still this week
      _action('a5', '2026-09-28'), // next Mon
      _action('a6', '2026-10-04'), // next Sun
      _action('a7', '2026-10-05'), // beyond horizon
      _action('a8', null), // undated → not planning material
      _action('a9', '2026-09-24', status: 'closed'),
    ]);
    expect(h.overdue.map((i) => i.id), ['a1']);
    expect(h.today.map((i) => i.id), ['a2']);
    expect(h.restOfWeek.map((d) => d.iso), ['2026-09-25', '2026-09-27']);
    expect(h.restOfWeek.first.items.single.id, 'a3');
    expect(h.nextWeek.map((i) => i.id), ['a5', 'a6']);
  });

  test('every register contributes, with its own date kind', () {
    final h = _build(
      decisions: [_decision('dc1', '2026-09-24')],
      deps: [_dep('d1', '2026-09-24')],
      risks: [_risk('r1', due: '2026-09-24', review: '2026-09-25', steerco: true)],
      issues: [_issue('i1', '2026-09-24')],
      acts: [
        _act('m1', start: '2026-09-24', type: 'milestone'),
        _act('x1', start: '2026-09-24', end: '2026-09-25'),
      ],
    );
    final kinds = {for (final i in h.today) i.dateKind};
    expect(kinds, {
      'Decision needed',
      'Dependency needed by',
      'Risk treatment due',
      'Issue due',
      'Milestone',
      'Activity starts',
    });
    final fri = h.restOfWeek.single;
    expect(fri.items.map((i) => i.dateKind).toSet(),
        {'Risk review', 'Activity ends'});
    // Only actions carry a linked action id for the block.
    expect(h.today.every((i) => i.linkedActionId == null), isTrue);
  });

  test('within a day, priority then kind then label', () {
    final h = _build(
      actions: [
        _action('a-low', '2026-09-24'),
        _action('a-crit', '2026-09-24', priority: 'critical'),
      ],
      decisions: [_decision('dc', '2026-09-24')],
      risks: [_risk('r-steerco', due: '2026-09-24', steerco: true)],
    );
    // critical action (3) and SteerCo high risk (3) tie on priority; kind
    // order puts the action first; then decision (2); then the low action.
    expect(h.today.map((i) => i.id), ['a-crit', 'r-steerco', 'dc', 'a-low']);
  });

  test('an activity that already started is not "behind"; a passed end is',
      () {
    final h = _build(acts: [
      _act('x1', start: '2026-09-01', end: '2026-09-20'),
      _act('x2', start: '2026-09-01', end: '2026-10-20'),
    ]);
    expect(h.overdue.map((i) => '${i.id}/${i.kind.name}'), ['x1/activityEnd']);
    expect(h.today, isEmpty);
  });

  test('settled items are excluded', () {
    final h = _build(
      decisions: [_decision('dc', '2026-09-24', status: 'deferred')],
      deps: [_dep('d', '2026-09-24', status: 'resolved')],
      risks: [_risk('r', due: '2026-09-24', status: 'accepted')],
      acts: [_act('m', start: '2026-09-24', type: 'gate', status: 'complete')],
    );
    expect(h.isEmpty, isTrue);
  });

  test('an accepted risk is still reviewed, and a closed one is not', () {
    final h = _build(risks: [
      _risk('r-acc', due: '2026-09-24', status: 'accepted', review: '2026-09-24'),
      _risk('r-closed', status: 'closed', review: '2026-09-24'),
    ]);
    expect(h.today.map((i) => '${i.id}/${i.kind.name}'), ['r-acc/riskReview']);
  });

  group('risks parked until a later review', () {
    PlanningItem? review(PlanningHorizon h) => [
          ...h.overdue,
          ...h.today,
          for (final d in h.restOfWeek) ...d.items,
          ...h.nextWeek,
        ].where((i) => i.kind == PlanningKind.riskReview).firstOrNull;

    test('a review next week is not offered at all', () {
      final h = _build(risks: [_risk('r1', review: '2026-09-28')]);
      expect(review(h), isNull);
      expect(h.nextWeek, isEmpty);
    });

    test('a review later this week is offered on its day', () {
      final h = _build(risks: [_risk('r1', review: '2026-09-25')]);
      expect(h.restOfWeek.single.iso, '2026-09-25');
      expect(review(h)!.id, 'r1');
    });

    test('a review on Sunday still counts as this week', () {
      final h = _build(risks: [_risk('r1', review: '2026-09-27')]);
      expect(h.restOfWeek.single.iso, '2026-09-27');
    });

    test('an overdue review is behind', () {
      final h = _build(risks: [_risk('r1', review: '2026-09-23')]);
      expect(h.overdue.single.kind, PlanningKind.riskReview);
    });

    test('a dated treatment is a commitment even when the review is parked',
        () {
      final h = _build(
          risks: [_risk('r1', due: '2026-09-29', review: '2026-10-15')]);
      expect(h.nextWeek.single.kind, PlanningKind.riskTreatment);
      expect(review(h), isNull);
    });

    test('predicate boundaries', () {
      expect(parkedUntilReview(null, _today), isFalse);
      expect(parkedUntilReview('', _today), isFalse);
      expect(parkedUntilReview('2026-09-27', _today), isFalse); // Sunday
      expect(parkedUntilReview('2026-09-28', _today), isTrue); // next Monday
      expect(parkedUntilReview('2026-09-01', _today), isFalse); // overdue
      // Anchored on the week, not on today: from Sunday, Monday is parked.
      expect(parkedUntilReview('2026-09-28', DateTime(2026, 9, 27)), isTrue);
      // With a time component in the stored value.
      expect(parkedUntilReview('2026-10-05T09:00:00', _today), isTrue);
    });
  });

  group('overdue risk reviews roll up into a review session per project', () {
    ({Risk risk, String projectName}) other(String id, String review) => (
          risk: _risk(id, review: review).risk.copyWith(projectId: 'p2'),
          projectName: 'OTHER',
        );

    test('two or more overdue reviews become one row, dated as the oldest', () {
      final h = _build(risks: [
        _risk('r1', review: '2026-09-10'),
        _risk('r2', review: '2026-09-01'),
        _risk('r3', review: '2026-09-20'),
        other('x1', '2026-09-15'),
      ]);
      final sessions =
          h.overdue.where((i) => i.kind == PlanningKind.riskReviewSession).toList();
      expect(sessions, hasLength(1));
      final s = sessions.single;
      expect(s.projectId, 'p1');
      expect(s.projectName, 'TAC');
      expect(s.count, 3);
      expect(s.label, '3 risk reviews overdue');
      expect(s.dateKind, 'Review session');
      expect(s.dueIso, '2026-09-01');
      expect(s.id, 'review:p1');
      // p2's single overdue review stays a row of its own.
      final singles =
          h.overdue.where((i) => i.kind == PlanningKind.riskReview).toList();
      expect(singles.map((i) => i.id), ['x1']);
      expect(h.overdue.first.id, 'review:p1', reason: 'sorted by its oldest date');
    });

    test('reviews due this week are not rolled up; treatments never are', () {
      final h = _build(risks: [
        _risk('r1', review: '2026-09-10', due: '2026-09-11'),
        _risk('r2', review: '2026-09-12', due: '2026-09-12'),
        _risk('r3', review: '2026-09-25'),
      ]);
      expect(h.overdue.where((i) => i.kind == PlanningKind.riskReviewSession),
          hasLength(1));
      expect(h.overdue.where((i) => i.kind == PlanningKind.riskTreatment),
          hasLength(2));
      expect(h.overdue.where((i) => i.kind == PlanningKind.riskReview), isEmpty);
      expect(h.restOfWeek.single.items.single.kind, PlanningKind.riskReview);
    });

    test('a cascaded copy contributes no review row and does not inflate the count',
        () {
      final copy = (
        risk: _risk('c1', review: '2026-09-01', due: '2026-09-02')
            .risk
            .copyWith(sourceProjectId: const Value('src')),
        projectName: 'TAC',
      );
      final h = _build(risks: [
        copy,
        _risk('r1', review: '2026-09-10'),
        _risk('r2', review: '2026-09-11'),
      ]);
      final s = h.overdue.singleWhere((i) => i.kind == PlanningKind.riskReviewSession);
      expect(s.count, 2);
      expect(s.dueIso, '2026-09-10');
      expect(h.overdue.where((i) => i.kind == PlanningKind.riskReview), isEmpty);
      // Its treatment date is still a dated commitment and still shows.
      expect(h.overdue.where((i) => i.kind == PlanningKind.riskTreatment).single.id,
          'c1');
    });

    test('the roll-up helper leaves a list without overdue reviews alone', () {
      final a = _build(actions: [_action('a1', '2026-09-01')]).overdue;
      expect(identical(rollUpOverdueReviews(a), a), isTrue);
    });
  });

  test('day labels', () {
    expect(planningDayLabel(DateTime(2026, 9, 25)), 'Fri 25 Sep');
    expect(planningDayLabel(DateTime(2026, 10, 4)), 'Sun 4 Oct');
  });
}
