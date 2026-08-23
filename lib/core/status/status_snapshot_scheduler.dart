import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import 'status_calculator.dart';

/// Captures a frozen view of the live Status dashboard at a point in time.
///
/// Auto-snapshot fires on Status page load if no snapshot exists for the
/// current week. Manual snapshot fires from the "Snapshot" button and accepts
/// the user's current narrative. Either path can be replayed later from the
/// snapshot history view to re-render the dashboard as it was.
class StatusSnapshotScheduler {
  /// Called once on app start. Creates a weekly snapshot if today is on or
  /// after the most recent Monday and no snapshot exists for it.
  static Future<void> maybeCreateSnapshot(
      AppDatabase db, String projectId) async {
    final lastMonday = _lastMonday(DateTime.now());
    final existing = await db.statusSnapshotDao.getMostRecent(projectId);
    if (existing != null && !existing.weekEnding.isBefore(lastMonday)) {
      return;
    }
    await _createSnapshot(db, projectId, lastMonday, narrative: null);
  }

  /// Manually create a snapshot for right now. Captures the user's current
  /// narrative (if any) so the snapshot history can replay it.
  static Future<void> createNow(
    AppDatabase db,
    String projectId, {
    String? narrative,
  }) async {
    await _createSnapshot(db, projectId, DateTime.now(), narrative: narrative);
  }

  static Future<void> _createSnapshot(
    AppDatabase db,
    String projectId,
    DateTime weekEnding, {
    required String? narrative,
  }) async {
    final wps = await db.programmeGanttDao.getWorkPackages(projectId);
    final activities =
        await db.programmeGanttDao.getActivitiesForProject(projectId);
    final actions = await db.actionsDao.getActionsForProject(projectId);
    final decisions = await db.decisionsDao.getDecisionsForProject(projectId);
    final risks = await db.raidDao.getRisksForProject(projectId);
    final header = await db.programmeGanttDao.getHeader(projectId);

    // ── Counts (existing fields) ─────────────────────────────────────────────
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final overdueActions = actions
        .where((a) =>
            a.status == 'open' &&
            a.dueDate != null &&
            a.dueDate!.compareTo(today) < 0)
        .length;
    final openActions = actions.where((a) => a.status == 'open').length;
    final pendingDecisionsList = decisions
        .where((d) => d.status == 'pending')
        .toList()
      ..sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
    final openRisks = risks.where((r) => r.status == 'open').length;

    final programmeRag = StatusCalculator.computeProgrammeRag(wps);
    final wsRag = StatusCalculator.encodeWorkstreamRag(wps);

    // ── Rich-snapshot fields (v19) ───────────────────────────────────────────
    final monthLabels = _parseMonthLabels(header?.monthLabels);
    final upcoming = StatusCalculator.upcomingMilestones(
        activities, monthLabels, month0Date: header?.month0Date);
    final top = StatusCalculator.topRisks(risks, limit: 3);

    final workstreamHealthJson = jsonEncode([
      for (final wp in wps)
        {
          'id': wp.id,
          'name': wp.name,
          'rag': wp.ragStatus,
        },
    ]);

    final topRisksJson = jsonEncode([
      for (final r in top)
        {
          'id': r.id,
          'ref': r.ref,
          'description': r.description,
          'likelihood': r.likelihood,
          'impact': r.impact,
        },
    ]);

    final upcomingMilestonesJson = jsonEncode([
      for (final a in upcoming)
        {
          'id': a.id,
          'name': a.name,
          'owner': a.owner,
          'monthLabel': (a.startMonth != null &&
                  a.startMonth! >= 0 &&
                  a.startMonth! < monthLabels.length)
              ? monthLabels[a.startMonth!]
              : null,
        },
    ]);

    final pendingDecisionsJson = jsonEncode([
      for (final d in pendingDecisionsList)
        {
          'id': d.id,
          'ref': d.ref,
          'description': d.description,
          'dueDate': d.dueDate,
          'owner': d.decisionMaker,
        },
    ]);

    final playbookStageJson = await _capturePlaybookStage(db, projectId);

    await db.statusSnapshotDao.insert(StatusSnapshotsCompanion(
      id:                     Value(const Uuid().v4()),
      projectId:              Value(projectId),
      weekEnding:             Value(weekEnding),
      programmeRag:           Value(programmeRag.value),
      workstreamRag:          Value(wsRag),
      overdueActionsCount:    Value(overdueActions),
      openActionsCount:       Value(openActions),
      pendingDecisionsCount:  Value(pendingDecisionsList.length),
      openRisksCount:         Value(openRisks),
      createdAt:              Value(DateTime.now()),
      narrative:              Value(narrative),
      workstreamHealthJson:   Value(workstreamHealthJson),
      topRisksJson:           Value(topRisksJson),
      upcomingMilestonesJson: Value(upcomingMilestonesJson),
      pendingDecisionsJson:   Value(pendingDecisionsJson),
      playbookStageJson:      Value(playbookStageJson),
    ));
  }

  static Future<String?> _capturePlaybookStage(
      AppDatabase db, String projectId) async {
    final pp = await db.playbookDao.getProjectPlaybook(projectId);
    if (pp == null) return null;

    final progresses =
        await db.playbookDao.getProgressForProjectPlaybook(pp.id);
    final inProgress = progresses.where((p) => p.status == 'in_progress');
    final notStarted = progresses.where((p) => p.status == 'not_started');
    final target = inProgress.isNotEmpty
        ? inProgress.first
        : (notStarted.isNotEmpty ? notStarted.first : null);
    if (target == null) return null;

    final stage = await db.playbookDao.getStageById(target.stageId);
    if (stage == null) return null;

    return jsonEncode({
      'stageId': stage.id,
      'stageName': stage.name,
      'status': target.status,
    });
  }

  static List<String> _parseMonthLabels(String? raw) {
    if (raw == null || raw.isEmpty) return List.generate(24, (i) => 'M$i');
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return List.generate(24, (i) => 'M$i');
    }
  }

  /// Returns the most recent Monday at midnight.
  static DateTime _lastMonday(DateTime now) {
    final daysBack = (now.weekday - DateTime.monday) % 7;
    final monday = now.subtract(Duration(days: daysBack));
    return DateTime(monday.year, monday.month, monday.day);
  }
}
