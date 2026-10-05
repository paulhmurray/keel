import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/plan/scenarios.dart';

/// One rule for B/C scenarios: points anchor on their month, activities
/// on their end, hard deadlines never vary.
TimelineActivity _act(String type, {int? start, int? end, int? likely, int? safe}) =>
    TimelineActivity(
      id: 'x', workPackageId: 'wp', projectId: 'p1', name: 'x',
      activityType: type, status: 'not_started', startMonth: start,
      endMonth: end ?? start, likelyMonth: likely, safeMonth: safe,
      isCritical: false, isBaseline: false, sortOrder: 0,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

void main() {
  test('which types vary', () {
    expect(scenariosApplyTo('milestone'), isTrue);
    expect(scenariosApplyTo('gate'), isTrue);
    expect(scenariosApplyTo('dependency_marker'), isTrue);
    expect(scenariosApplyTo('activity'), isTrue);
    expect(scenariosApplyTo('hard_deadline'), isFalse);
    expect(scenariosApplyTo('ongoing'), isFalse);
  });

  test('anchor: a point is its month, an activity is its end', () {
    expect(scenarioAnchorMonth(_act('milestone', start: 4)), 4);
    expect(scenarioAnchorMonth(_act('dependency_marker', start: 4)), 4);
    expect(scenarioAnchorMonth(_act('dependency_marker', start: 4, end: 6)), 6,
        reason: 'a marker can span months and varies on its landing');
    expect(scenarioAnchorMonth(_act('activity', start: 2, end: 5)), 5);
    expect(scenarioAnchorMonth(_act('activity', start: 2)), 2);
    expect(scenarioAnchorMonth(_act('hard_deadline', start: 4)), isNull);
    expect(scenarioAnchorMonth(_act('activity')), isNull);
  });

  test('range spans anchor and both scenarios, either side for points', () {
    expect(scenarioRange(_act('milestone', start: 4, likely: 3, safe: 6)),
        (lo: 3, hi: 6));
    expect(scenarioRange(_act('activity', start: 2, end: 5, likely: 6, safe: 8)),
        (lo: 5, hi: 8));
    expect(scenarioRange(_act('milestone', start: 4)), isNull);
    expect(scenarioRange(_act('hard_deadline', start: 4, likely: 5)), isNull);
  });

  test('labels and allowed months follow the anchor rule', () {
    expect(scenarioLabels('activity').likely, 'B — Likely end (optional)');
    expect(scenarioLabels('gate').safe, 'C — Safe (optional)');
    expect(scenarioLabels('dependency_marker').likely, 'B — Likely end (optional)');
    expect(scenarioMonthAllowed('activity', 4, 5), isFalse,
        reason: 'an earlier finish would hide under the bar');
    expect(scenarioMonthAllowed('activity', 5, 5), isTrue);
    expect(scenarioMonthAllowed('milestone', 2, 5), isTrue);
    expect(scenarioMonthAllowed('activity', 2, null), isTrue);
  });
}
