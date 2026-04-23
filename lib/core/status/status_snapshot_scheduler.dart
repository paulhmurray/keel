import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../database/database.dart';
import 'status_calculator.dart';

/// Called once on app start. Creates a weekly snapshot if:
/// - Today is Monday (or we missed last Monday), and
/// - No snapshot exists for the most recent Monday.
class StatusSnapshotScheduler {
  static Future<void> maybeCreateSnapshot(
      AppDatabase db, String projectId) async {
    final lastMonday = _lastMonday(DateTime.now());
    final existing = await db.statusSnapshotDao.getMostRecent(projectId);

    // Already have a snapshot for this Monday (or more recent)
    if (existing != null &&
        !existing.weekEnding.isBefore(lastMonday)) {
      return;
    }

    await _createSnapshot(db, projectId, lastMonday);
  }

  /// Manually create a snapshot for right now (mid-week option).
  static Future<void> createNow(AppDatabase db, String projectId) async {
    await _createSnapshot(db, projectId, DateTime.now());
  }

  static Future<void> _createSnapshot(
      AppDatabase db, String projectId, DateTime weekEnding) async {
    final wps = await db.programmeGanttDao.getWorkPackages(projectId);
    final actions = await db.actionsDao.getActionsForProject(projectId);
    final decisions = await db.decisionsDao.getDecisionsForProject(projectId);
    final risks = await db.raidDao.getRisksForProject(projectId);

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final overdueActions = actions
        .where((a) =>
            a.status == 'open' &&
            a.dueDate != null &&
            a.dueDate!.compareTo(today) < 0)
        .length;
    final openActions = actions.where((a) => a.status == 'open').length;
    final pendingDecisions =
        decisions.where((d) => d.status == 'pending').length;
    final openRisks = risks.where((r) => r.status == 'open').length;

    final programmeRag = StatusCalculator.computeProgrammeRag(wps);
    final wsRag = StatusCalculator.encodeWorkstreamRag(wps);

    await db.statusSnapshotDao.insert(StatusSnapshotsCompanion(
      id:                     Value(const Uuid().v4()),
      projectId:              Value(projectId),
      weekEnding:             Value(weekEnding),
      programmeRag:           Value(programmeRag.value),
      workstreamRag:          Value(wsRag),
      overdueActionsCount:    Value(overdueActions),
      openActionsCount:       Value(openActions),
      pendingDecisionsCount:  Value(pendingDecisions),
      openRisksCount:         Value(openRisks),
      createdAt:              Value(DateTime.now()),
    ));
  }

  /// Returns the most recent Monday at midnight.
  static DateTime _lastMonday(DateTime now) {
    final daysBack = (now.weekday - DateTime.monday) % 7;
    final monday = now.subtract(Duration(days: daysBack));
    return DateTime(monday.year, monday.month, monday.day);
  }
}
