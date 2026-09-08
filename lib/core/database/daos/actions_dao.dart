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

  /// Nests [childId] under [parentId], flagging the target as a group
  /// parent if it isn't one yet — used by drop-onto-card nesting.
  Future<void> nestUnder(String childId, String parentId) async {
    await transaction(() async {
      final now = DateTime.now();
      await (update(projectActions)..where((t) => t.id.equals(parentId)))
          .write(ProjectActionsCompanion(
        isParent: const Value(true),
        updatedAt: Value(now),
      ));
      await (update(projectActions)..where((t) => t.id.equals(childId)))
          .write(ProjectActionsCompanion(
        parentActionId: Value(parentId),
        updatedAt: Value(now),
      ));
    });
  }

  /// Sets only the group-parent flag.
  Future<void> setIsParent(String id, bool isParent) {
    return (update(projectActions)..where((t) => t.id.equals(id))).write(
      ProjectActionsCompanion(
        isParent: Value(isParent),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Sets just the status — used by the sub-task quick toggle in the
  /// parent action dialog.
  Future<void> setStatus(String id, String status) {
    return (update(projectActions)..where((t) => t.id.equals(id))).write(
      ProjectActionsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Closes every action in [ids] that isn't already closed — used by
  /// "Close group" to retire a parent and all its descendants at once.
  Future<void> closeActions(List<String> ids) {
    return (update(projectActions)
          ..where((t) => t.id.isIn(ids) & t.status.equals('closed').not()))
        .write(ProjectActionsCompanion(
      status: const Value('closed'),
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

  // ── Escalation (Phase C.6) ────────────────────────────────────────────

  Future<void> setActionEscalated(String id, bool escalated) {
    return (update(projectActions)..where((t) => t.id.equals(id))).write(
      ProjectActionsCompanion(
        escalatedAt: Value(escalated ? DateTime.now() : null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<ProjectAction>> getEscalatedActionsForProject(
          String projectId) =>
      (select(projectActions)
            ..where((t) =>
                t.projectId.equals(projectId) &
                t.escalatedAt.isNotNull() &
                t.sourceProjectId.isNull()))
          .get();

  /// Watches every overdue action that arrived from a linked project.
  /// "Overdue" = dueDate non-null AND dueDate < today's ISO date AND
  /// status != 'closed'. Used by the programme-side derived view to
  /// surface action items that have slipped past their due date
  /// across every linked PM's portfolio in one place.
  ///
  /// Date comparison is string-lexicographic on the ISO-8601 column
  /// since dueDate is stored as text — works correctly because every
  /// row uses YYYY-MM-DD which sorts the same way as the underlying
  /// calendar.
  Stream<List<ProjectAction>> watchOverdueCascadedActionsForProgramme(
      String programmeId) {
    final today = _todayIso();
    return (select(projectActions)
          ..where((t) =>
              t.projectId.equals(programmeId) &
              t.sourceProjectId.isNotNull() &
              t.dueDate.isNotNull() &
              t.dueDate.isSmallerThanValue(today) &
              t.status.equals('closed').not())
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .watch();
  }

  /// One-shot variant for tests / non-stream call sites.
  Future<List<ProjectAction>> getOverdueCascadedActionsForProgramme(
      String programmeId) {
    final today = _todayIso();
    return (select(projectActions)
          ..where((t) =>
              t.projectId.equals(programmeId) &
              t.sourceProjectId.isNotNull() &
              t.dueDate.isNotNull() &
              t.dueDate.isSmallerThanValue(today) &
              t.status.equals('closed').not())
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .get();
  }

  String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
