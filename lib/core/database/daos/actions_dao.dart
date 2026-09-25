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

  /// Next `AC<n>` ref given the project's existing actions.
  static String nextRef(Iterable<ProjectAction> existing) {
    final nums = existing
        .where((a) => a.ref != null && a.ref!.startsWith('AC'))
        .map((a) => int.tryParse(a.ref!.substring(2)) ?? 0)
        .toList()
      ..sort();
    return 'AC${(nums.isEmpty ? 0 : nums.last) + 1}';
  }

  /// Quick-add from the parent's dialog: creates an open action named
  /// [description] (row id [id], caller supplies a uuid) nested under
  /// [parentId], inheriting the parent's category and plan link, and
  /// flags the parent as a group. Refuses (returns null) when the parent
  /// doesn't exist or is already a sub-task — the hierarchy is capped at
  /// parent → task → sub-task, so a sub-task can't grow children.
  Future<String?> addSubTask({
    required String id,
    required String parentId,
    required String description,
  }) async {
    final parent = await getActionById(parentId);
    if (parent == null) return null;
    if (parent.parentActionId != null) {
      final grandparent = await getActionById(parent.parentActionId!);
      if (grandparent != null && grandparent.parentActionId != null) {
        return null;
      }
    }
    final existing = await getActionsForProject(parent.projectId);
    final now = DateTime.now();
    await transaction(() async {
      await into(projectActions).insert(ProjectActionsCompanion(
        id: Value(id),
        projectId: Value(parent.projectId),
        ref: Value(nextRef(existing)),
        description: Value(description),
        status: const Value('open'),
        priority: const Value('medium'),
        source: const Value('manual'),
        categoryId: Value(parent.categoryId),
        planActivityId: Value(parent.planActivityId),
        parentActionId: Value(parentId),
        isParent: const Value(false),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      if (!parent.isParent) {
        await (update(projectActions)..where((t) => t.id.equals(parentId)))
            .write(ProjectActionsCompanion(
          isParent: const Value(true),
          updatedAt: Value(now),
        ));
      }
    });
    return id;
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
