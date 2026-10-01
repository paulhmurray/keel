import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/helm/project_headline.dart';

void main() {
  final t0 = DateTime(2026, 9, 1);
  Risk risk(String id, String pid, String like, String imp,
          {bool steerco = false, DateTime? esc}) =>
      Risk(id: id, projectId: pid, description: id, likelihood: like, impact: imp,
          status: 'open', source: 'manual', steerco: steerco, escalatedAt: esc,
          strategy: 'treat', createdAt: t0, updatedAt: t0);
  TimelineActivity act(String id, String pid, String type, String? date,
          {String status = 'not_started'}) =>
      TimelineActivity(id: id, workPackageId: 'wp', projectId: pid, name: id,
          activityType: type, status: status, isCritical: false, isBaseline: false,
          sortOrder: 0, startDate: date, createdAt: t0, updatedAt: t0);

  test('top risk prefers escalated ones, then falls back to the highest score', () {
    final risks = <HelmRiskItem>[
      (risk: risk('big', 'p', 'almost certain', 'severe'), projectName: 'P'),
      (risk: risk('esc', 'p', 'possible', 'moderate', steerco: true), projectName: 'P'),
      (risk: risk('other', 'q', 'almost certain', 'severe', steerco: true), projectName: 'Q'),
    ];
    expect(projectTopRisk(risks, 'p')!.id, 'esc');
    expect(projectTopRisk(risks.where((r) => r.risk.id == 'big'), 'p')!.id, 'big');
    expect(projectTopRisk(risks, 'zzz'), isNull);
  });

  test('next milestone is the earliest open milestone/gate/deadline on or after today', () {
    final acts = <HelmActivityItem>[
      (activity: act('past', 'p', 'milestone', '2026-09-01'), projectName: 'P', wpCode: null),
      (activity: act('done', 'p', 'gate', '2026-10-01', status: 'complete'), projectName: 'P', wpCode: null),
      (activity: act('plain', 'p', 'activity', '2026-10-02'), projectName: 'P', wpCode: null),
      (activity: act('soon', 'p', 'hard_deadline', '2026-10-10'), projectName: 'P', wpCode: 'INT'),
      (activity: act('later', 'p', 'milestone', '2026-11-01'), projectName: 'P', wpCode: null),
      (activity: act('elsewhere', 'q', 'milestone', '2026-10-03'), projectName: 'Q', wpCode: null),
    ];
    final n = projectNextMilestone(acts, 'p', '2026-09-27');
    expect(n!.activity.id, 'soon');
    expect(milestoneKindLabel(n.activity.activityType), 'deadline');
    expect(projectNextMilestone(acts, 'p', '2026-12-01'), isNull);
  });
}
