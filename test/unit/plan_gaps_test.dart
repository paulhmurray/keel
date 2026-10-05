import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/plan/plan_gaps.dart';

/// Register items the plan has forgotten: which ones count, where the
/// engine puts them, and how the model's answer is checked.
///
/// Month 0 is June 2026 throughout.
const _m0 = '2026-06-01';
final _month0 = DateTime(2026, 6, 1);

TimelineActivity _act(String id, String name,
        {int? start, int? end, String wp = 'wp1', String type = 'activity',
        String status = 'not_started', String? parent, String? links,
        String? source}) =>
    TimelineActivity(
      id: id, workPackageId: wp, projectId: 'p1', name: name,
      activityType: type, status: status, startMonth: start,
      endMonth: end ?? start, parentActivityId: parent,
      varianceRaidLinksJson: links, sourceProjectId: source,
      isCritical: false, isBaseline: false, sortOrder: 0,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

TimelineWorkPackage _wp(String id, String name) => TimelineWorkPackage(
      id: id, projectId: 'p1', name: name, colourTheme: 'blue', sortOrder: 0,
      ragStatus: 'green', createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

ProjectAction _action(String id,
        {String? due, String status = 'open', String? plan, bool parent = false,
        String? source}) =>
    ProjectAction(
      id: id, projectId: 'p1', ref: id.toUpperCase(), description: 'Do $id',
      dueDate: due, status: status, priority: 'medium', source: 'manual',
      planActivityId: plan, isParent: parent, sourceProjectId: source,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

Decision _decision(String id, {String? due, String status = 'pending', String? plan}) =>
    Decision(
      id: id, projectId: 'p1', ref: id.toUpperCase(), description: 'Decide $id',
      status: status, dueDate: due, planActivityId: plan, source: 'manual',
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

ProgramDependency _dep(String id,
        {String? due, String type = 'inbound', String status = 'open', String? plan}) =>
    ProgramDependency(
      id: id, projectId: 'p1', ref: id.toUpperCase(), description: 'Need $id',
      dependencyType: type, status: status, dueDate: due, planActivityId: plan,
      source: 'manual', createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

Risk _risk(String id,
        {String? due, String likelihood = 'possible', String impact = 'moderate',
        String status = 'open'}) =>
    Risk(
      id: id, projectId: 'p1', ref: id.toUpperCase(), description: 'Risk $id',
      likelihood: likelihood, impact: impact, strategy: 'treat', steerco: false,
      status: status, dueDate: due, source: 'manual',
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

void main() {
  group('collect', () {
    test('only open, dated, unlinked, local items count', () {
      final gaps = collectPlanGaps(
        actions: [
          _action('a1', due: '2026-10-10'),
          _action('a2', due: '2026-10-10', plan: 'x'),
          _action('a3'),
          _action('a4', due: '2026-10-10', status: 'closed'),
          _action('a5', due: '2026-10-10', parent: true),
          _action('a6', due: '2026-10-10', source: 'other'),
        ],
        decisions: [
          _decision('d1', due: '2026-11-01'),
          _decision('d2', due: '2026-11-01', status: 'decided'),
          _decision('d3'),
        ],
        dependencies: [
          _dep('p1', due: '2026-12-01'),
          _dep('p2', due: '2026-12-01', type: 'outbound'),
          _dep('p3', due: '2026-12-01', status: 'closed'),
        ],
        risks: [
          _risk('r1', due: '2026-09-15'),
          _risk('r2', likelihood: 'likely', impact: 'major'),
          _risk('r3'),
          _risk('r4', due: '2026-09-15', status: 'closed'),
          _risk('r5', due: '2026-09-15'),
        ],
        activities: [
          _act('x', 'Linked', start: 4, links: '[{"type":"risk","id":"r5"}]'),
        ],
        month0Date: _m0,
      );
      expect(gaps.map((g) => g.id), ['a1', 'd1', 'p1', 'r1', 'r2']);
      expect(gaps.first.dueMonth, 4);
      expect(gaps.first.display, 'A1 · Do a1');
      expect(gaps.last.dueMonth, isNull, reason: 'high-rated, undated');
      expect(gaps.last.status, contains('likely/major'));
    });
  });

  group('deterministic placement', () {
    final wps = [_wp('wp1', 'Build'), _wp('wp2', 'Test')];
    final acts = [
      _act('early', 'Design', start: 1, end: 2),
      _act('cover', 'Build adapter', start: 3, end: 5),
      _act('later', 'SIT', start: 7, end: 8),
      _act('done', 'Done', start: 4, end: 4, status: 'complete'),
      _act('ms', 'Go-live', start: 4, type: 'milestone'),
      _act('task', 'A task', start: 4, parent: 'cover'),
      _act('foreign', 'Theirs', start: 4, source: 'other'),
    ];

    test('the activity whose window holds the due month wins', () {
      final gap = const PlanGap(
          kind: GapKind.action, id: 'a', title: 'x', status: 'open',
          dueIso: '2026-10-10', dueMonth: 4);
      final p = placeGapDeterministically(gap,
          activities: acts, workPackages: wps, month0: _month0)!;
      expect(p.activityId, 'cover',
          reason: 'complete, milestone, task and cascaded rows are skipped');
      expect(p.rationale, contains('Sep 2026–Nov 2026'));
      expect(p.isNew, isFalse);
    });

    test('nothing covering the month: nearest in time', () {
      final gap = const PlanGap(
          kind: GapKind.action, id: 'a', title: 'x', status: 'open',
          dueIso: '2027-03-10', dueMonth: 9);
      final p = placeGapDeterministically(gap,
          activities: acts, workPackages: wps, month0: _month0)!;
      expect(p.activityId, 'later');
    });

    test('an empty plan proposes a new row in the first work package', () {
      final gap = const PlanGap(
          kind: GapKind.decision, id: 'd', ref: 'DC1', title: 'Pick vendor',
          status: 'pending', dueIso: '2026-10-10', dueMonth: 4);
      final p = placeGapDeterministically(gap,
          activities: const [], workPackages: wps, month0: _month0)!;
      expect(p.isNew, isTrue);
      expect(p.newWorkPackageId, 'wp1');
      expect(p.newName, 'DC1 · Pick vendor');
      expect(p.newMonth, 4);
      expect(
          placeGapDeterministically(gap,
              activities: const [], workPackages: const [], month0: _month0),
          isNull);
    });
  });

  group('AI placement', () {
    final wps = [_wp('wp1', 'Build')];
    final acts = [_act('cover', 'Build adapter', start: 3, end: 5)];
    final gap = const PlanGap(
        kind: GapKind.dependency, id: 'p', ref: 'D1', title: 'Vendor keys',
        detail: 'from Acme', status: 'open', dueIso: '2026-10-10', dueMonth: 4);

    test('the prompt lists the plan and says what the link means', () {
      final p = gapAssistPrompt(
        gap: gap, activities: acts, workPackages: wps, month0: _month0,
        engine: const GapPlacement(activityId: 'cover', rationale: 'covers it'),
      );
      expect(p.user, contains('Item: Dependency: D1 · Vendor keys'));
      expect(p.user, contains('Due: 2026-10-10 (Oct 2026)'));
      expect(p.user, contains('cover | Build | Build adapter | Sep 2026–Nov 2026'));
      expect(p.user, contains('wp1 | Build'));
      expect(p.user, contains("The engine's guess: cover (covers it)"));
      expect(p.user, contains('cannot start until this lands'));
      expect(p.system, contains('never invent ids'));
    });

    test('a known id is accepted; an unknown one is rejected', () {
      final ok = parseGapPlacement(
        '{"activity_id": "cover", "new_activity": null, "rationale": "Same work."}',
        activityIds: {'cover'}, workPackageIds: {'wp1'}, month0: _month0,
      )!;
      expect(ok.activityId, 'cover');
      expect(ok.source, 'ai');
      expect(ok.rationale, 'Same work.');
      expect(
          parseGapPlacement('{"activity_id": "made-up", "rationale": "x"}',
              activityIds: {'cover'}, workPackageIds: {'wp1'}, month0: _month0),
          isNull);
    });

    test('a new activity needs a real work package; the month is derived', () {
      final nw = parseGapPlacement(
        '```json\n{"activity_id": null, "new_activity": {"work_package_id": "wp1", '
        '"name": "Receive vendor API keys and validate them end to end", '
        '"month": "2026-11"}, "rationale": "Nothing covers it."}\n```',
        activityIds: {'cover'}, workPackageIds: {'wp1'}, month0: _month0,
      )!;
      expect(nw.isNew, isTrue);
      expect(nw.newWorkPackageId, 'wp1');
      expect(nw.newName, 'Receive vendor API keys and validate them end',
          reason: 'capped at eight words');
      expect(nw.newMonth, 5);
      expect(
          parseGapPlacement(
              '{"new_activity": {"work_package_id": "nope", "name": "x", "month": "2026-11"}}',
              activityIds: {}, workPackageIds: {'wp1'}, month0: _month0),
          isNull);
      expect(parseGapPlacement('no json', activityIds: {}, workPackageIds: {}, month0: _month0),
          isNull);
    });
  });
}
