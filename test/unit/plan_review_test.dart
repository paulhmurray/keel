import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/plan/plan_review.dart';

/// Plan review: graph facts first, then the model's suggestions checked
/// against real ids. Month 0 is June 2026.
const _m0 = '2026-06-01';
final _month0 = DateTime(2026, 6, 1);

TimelineActivity _act(String id, String name,
        {int? start, int? end, String wp = 'wp1', String type = 'activity',
        String status = 'not_started', int order = 0, String? parent,
        String? source}) =>
    TimelineActivity(
      id: id, workPackageId: wp, projectId: 'p1', name: name,
      activityType: type, status: status, startMonth: start,
      endMonth: end ?? start, parentActivityId: parent, sortOrder: order,
      sourceProjectId: source, isCritical: false, isBaseline: false,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

TimelineDependency _dep(String from, String to,
        {String type = 'finish_to_start', String? external}) =>
    TimelineDependency(
      id: 'd-$from-$to', projectId: 'p1',
      fromActivityId: external != null ? '' : from, toActivityId: to,
      dependencyType: external != null ? 'external' : type,
      externalLabel: external, createdAt: DateTime(2026),
    );

TimelineWorkPackage _wp(String id, String name) => TimelineWorkPackage(
      id: id, projectId: 'p1', name: name, colourTheme: 'blue', sortOrder: 0,
      ragStatus: 'green', createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

void main() {
  group('checks', () {
    test('a backwards arrow, an orphan milestone and a packageless end are found',
        () {
      final findings = checkPlan(
        activities: [
          _act('a', 'Design', start: 1, end: 3),
          _act('b', 'Build', start: 2, end: 4),
          _act('m', 'Go-live', start: 6, type: 'milestone'),
          _act('c', 'Train users', start: 5, wp: 'wp2'),
          _act('t', 'A task', start: 2, parent: 'b'),
          _act('x', 'Theirs', start: 2, source: 'other'),
        ],
        dependencies: [_dep('a', 'b')],
        workPackages: [_wp('wp1', 'Build'), _wp('wp2', 'Adoption')],
        month0Date: _m0,
        hardDeadlineDate: '2026-12-31',
      );
      final codes = findings.map((f) => f.code).toList();
      expect(codes.first, 'backwards_arrow', reason: 'warnings sort first');
      expect(findings.first.message, contains('Build (Aug 2026–Oct 2026) starts before Design'));
      expect(codes, contains('orphan_point'));
      expect(codes, contains('wp_no_point'));
      expect(findings.firstWhere((f) => f.code == 'wp_no_point').message,
          contains('"Adoption"'));
      expect(codes, contains('deadline_not_on_plan'));
      expect(codes, contains('isolated'));
      expect(findings.firstWhere((f) => f.code == 'isolated').activityIds, ['c'],
          reason: 'tasks and cascaded rows are not judged');
    });

    test('a plan with no arrows gets one note, not one per row', () {
      final findings = checkPlan(
        activities: [_act('a', 'A', start: 1), _act('b', 'B', start: 2)],
        dependencies: const [],
        workPackages: [_wp('wp1', 'W')],
        month0Date: _m0,
      );
      expect(findings.map((f) => f.code), isNot(contains('isolated')));
      expect(findings.map((f) => f.code), contains('no_arrows'));
    });

    test('start-to-start and finish-to-finish use their own anchors; '
        'external arrows feed milestones', () {
      final ok = checkPlan(
        activities: [
          _act('a', 'A', start: 1, end: 3),
          _act('b', 'B', start: 1, end: 3),
          _act('m', 'M', start: 4, type: 'gate'),
        ],
        dependencies: [
          _dep('a', 'b', type: 'start_to_start'),
          _dep('', 'm', external: 'Vendor sign-off'),
        ],
        workPackages: [_wp('wp1', 'W')],
        month0Date: _m0,
      );
      expect(ok.map((f) => f.code), isNot(contains('backwards_arrow')));
      expect(ok.map((f) => f.code), isNot(contains('orphan_point')));
    });

    test('an empty plan says so and nothing else', () {
      final f = checkPlan(
          activities: const [], dependencies: const [],
          workPackages: [_wp('wp1', 'W')], month0Date: _m0);
      expect(f.single.code, 'empty');
    });
  });

  group('AI review', () {
    final wps = [_wp('wp1', 'Build')];
    final acts = [
      _act('a', 'Design', start: 1, end: 2, order: 0),
      _act('b', 'Build', start: 3, end: 5, order: 1),
    ];
    final deps = [_dep('a', 'b')];

    test('the prompt carries the WBS in order with dependencies', () {
      final p = planReviewPrompt(
        activities: acts, dependencies: deps, workPackages: wps,
        month0: _month0,
        findings: const [
          PlanFinding(severity: FindingSeverity.info, code: 'x', message: 'Known thing.'),
        ],
      );
      expect(p.user, contains('## Build (id wp1)'));
      expect(p.user, contains('a | activity | Design | Jul 2026–Aug 2026 | not started | '));
      expect(p.user, contains('b | activity | Build | Sep 2026–Nov 2026 | not started | a'));
      expect(p.user, contains('Already known (do not repeat):\n- Known thing.'));
      expect(p.system, contains('never invent ids'));
    });

    test('suggestions are validated: ids must exist, duplicates of arrows drop',
        () {
      final s = parsePlanSuggestions(
        '''
        {"suggestions": [
          {"kind": "reorder", "first_id": "b", "then_id": "a", "message": "Build before design? No."},
          {"kind": "reorder", "first_id": "a", "then_id": "b", "message": "already arrowed"},
          {"kind": "reorder", "first_id": "zz", "then_id": "a", "message": "unknown"},
          {"kind": "missing", "work_package_id": "wp1", "name": "Data migration dry run please do it twice over", "after_id": "b", "before_id": null, "message": "Nothing rehearses the cut-over."},
          {"kind": "point", "work_package_id": "wp1", "name": "Go/no-go", "type": "gate", "after_id": "b", "message": "No decision point before go-live."},
          {"kind": "point", "work_package_id": "nope", "name": "x", "message": "bad wp"},
          {"kind": "weird", "message": "ignored"}
        ]}
        ''',
        activityIds: {'a', 'b'}, workPackageIds: {'wp1'}, dependencies: deps,
      );
      expect(s.length, 3);
      expect(s[0].kind, SuggestionKind.reorder);
      expect((s[0].afterId, s[0].beforeId), ('b', 'a'));
      expect(s[1].kind, SuggestionKind.missing);
      expect(s[1].name, 'Data migration dry run please do it twice');
      expect(s[1].type, 'activity');
      expect(s[2].kind, SuggestionKind.point);
      expect(s[2].type, 'gate');
      expect(parsePlanSuggestions('nope', activityIds: {}, workPackageIds: {}, dependencies: const []),
          isEmpty);
    });

    test('a new row lands after what it follows, else before what it precedes',
        () {
      final byId = {for (final a in acts) a.id: a};
      expect(
          suggestedMonth(
              const PlanSuggestion(kind: SuggestionKind.missing, message: 'm', afterId: 'b'),
              byId),
          5);
      expect(
          suggestedMonth(
              const PlanSuggestion(kind: SuggestionKind.missing, message: 'm', beforeId: 'b'),
              byId),
          3);
      expect(
          suggestedMonth(const PlanSuggestion(kind: SuggestionKind.missing, message: 'm'), byId),
          isNull);
    });
  });
}
