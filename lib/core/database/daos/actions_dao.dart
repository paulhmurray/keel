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

  Future<void> upsertAction(ProjectActionsCompanion entry) {
    return into(projectActions).insertOnConflictUpdate(entry);
  }
}
