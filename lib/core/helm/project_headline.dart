/// The two things a project manager wants at the top of the day for the
/// project they have open: the risk most in need of attention and the
/// next date on the plan. Pure so the rail and the board share one rule.
library;

import '../database/database.dart';
import '../status/risk_ranking.dart';

/// The top escalated open risk for [projectId] by the shared ranking, or
/// the top open risk when none is escalated.
Risk? projectTopRisk(Iterable<HelmRiskItem> risks, String projectId,
    {DateTime? today}) {
  final mine = risks
      .where((r) => r.risk.projectId == projectId)
      .map((r) => r.risk)
      .toList();
  if (mine.isEmpty) return null;
  final escalated = mine.where((r) => r.steerco || r.escalatedAt != null).toList();
  final ranked = rankRisks(escalated.isNotEmpty ? escalated : mine, today: today);
  return ranked.firstOrNull;
}

/// The next open milestone, gate or hard deadline for [projectId] on or
/// after [todayIso], or null.
HelmActivityItem? projectNextMilestone(
    Iterable<HelmActivityItem> activities, String projectId, String todayIso) {
  HelmActivityItem? best;
  for (final a in activities) {
    final act = a.activity;
    if (act.projectId != projectId || act.status == 'complete') continue;
    if (act.activityType != 'milestone' &&
        act.activityType != 'gate' &&
        act.activityType != 'hard_deadline') {
      continue;
    }
    final d = act.startDate ?? act.endDate;
    if (d == null || d.compareTo(todayIso) < 0) continue;
    final bestDate = best?.activity.startDate ?? best?.activity.endDate;
    if (bestDate == null || d.compareTo(bestDate) < 0) best = a;
  }
  return best;
}

String milestoneKindLabel(String activityType) => switch (activityType) {
      'gate' => 'gate',
      'hard_deadline' => 'deadline',
      _ => 'milestone',
    };
