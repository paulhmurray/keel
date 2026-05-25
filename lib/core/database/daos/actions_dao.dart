part of '../database.dart';

@DriftAccessor(tables: [ProjectActions])
class ActionsDao extends DatabaseAccessor<AppDatabase> with _$ActionsDaoMixin {
  ActionsDao(super.db);

  Stream<List<ProjectAction>> watchActionsForProject(String projectId) {
    return (select(projectActions)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<ProjectAction>> getActionsForProject(String projectId) {
    return (select(projectActions)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Stream<List<ProjectAction>> watchOverdueActionsForProject(String projectId) {
    // Overdue = open and dueDate in the past (stored as text ISO date, compare as string)
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return (select(projectActions)
          ..where((t) =>
              t.projectId.equals(projectId) &
              t.status.equals('open') &
              t.dueDate.isSmallerThanValue(today))
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .watch();
  }

  Stream<List<ProjectAction>> watchActionsForOwner(
      String projectId, String ownerName) {
    return (select(projectActions)
          ..where((t) =>
              t.projectId.equals(projectId) & t.owner.equals(ownerName))
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .watch();
  }

  Future<ProjectAction?> getActionById(String id) {
    return (select(projectActions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertAction(ProjectActionsCompanion entry) {
    return into(projectActions).insert(entry);
  }

  Future<bool> updateAction(ProjectActionsCompanion entry) {
    return update(projectActions).replace(entry);
  }

  Future<int> deleteAction(String id) {
    return (delete(projectActions)..where((t) => t.id.equals(id))).go();
  }

  /// Deletes a parent action and re-parents any of its children to top-level
  /// (parentActionId = null). Performed in a single transaction.
  Future<void> deleteParentAndOrphanChildren(String parentId) async {
    await transaction(() async {
      await (update(projectActions)
            ..where((t) => t.parentActionId.equals(parentId)))
          .write(ProjectActionsCompanion(
        parentActionId: const Value(null),
        updatedAt: Value(DateTime.now()),
      ));
      await (delete(projectActions)..where((t) => t.id.equals(parentId))).go();
    });
  }

  /// Updates only the parent of a given action — used by drag-to-reparent.
  Future<void> setParent(String childId, String? parentId) {
    return (update(projectActions)..where((t) => t.id.equals(childId)))
        .write(ProjectActionsCompanion(
      parentActionId: Value(parentId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> upsertAction(ProjectActionsCompanion entry) {
    return into(projectActions).insertOnConflictUpdate(entry);
  }

  Future<void> deleteByRecurrenceGroup(String groupId) {
    return (delete(projectActions)
          ..where((t) => t.recurrenceGroupId.equals(groupId)))
        .go();
  }

  Future<List<ProjectAction>> getActionsForActivity(String activityId) {
    return (select(projectActions)
          ..where((t) => t.planActivityId.equals(activityId))
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .get();
  }

  /// Returns a map of activityId → (count of open actions, worst urgency).
  /// urgency: 'overdue' > 'soon' (due within 7 days) > 'ok'
  Future<Map<String, ({int count, String urgency})>> getLinkedActionSummary(
      String projectId) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final soon = DateTime.now()
        .add(const Duration(days: 7))
        .toIso8601String()
        .substring(0, 10);

    final rows = await (select(projectActions)
          ..where((t) =>
              t.projectId.equals(projectId) &
              t.planActivityId.isNotNull() &
              t.status.isNotIn(['closed'])))
        .get();

    final result = <String, ({int count, String urgency})>{};
    for (final a in rows) {
      final actId = a.planActivityId!;
      String urgency = 'ok';
      if (a.dueDate != null) {
        if (a.dueDate!.compareTo(today) < 0) {
          urgency = 'overdue';
        } else if (a.dueDate!.compareTo(soon) <= 0) {
          urgency = 'soon';
        }
      }
      final existing = result[actId];
      if (existing == null) {
        result[actId] = (count: 1, urgency: urgency);
      } else {
        final worst = _worstUrgency(existing.urgency, urgency);
        result[actId] = (count: existing.count + 1, urgency: worst);
      }
    }
    return result;
  }

  static String _worstUrgency(String a, String b) {
    const order = ['ok', 'soon', 'overdue'];
    return order.indexOf(a) >= order.indexOf(b) ? a : b;
  }
}
