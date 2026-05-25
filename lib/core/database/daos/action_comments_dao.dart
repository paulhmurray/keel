part of '../database.dart';

@DriftAccessor(tables: [ActionComments])
class ActionCommentsDao extends DatabaseAccessor<AppDatabase>
    with _$ActionCommentsDaoMixin {
  ActionCommentsDao(super.db);

  Stream<List<ActionComment>> watchForAction(String actionId) {
    return (select(actionComments)
          ..where((t) => t.actionId.equals(actionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<List<ActionComment>> getForAction(String actionId) {
    return (select(actionComments)
          ..where((t) => t.actionId.equals(actionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// All comments for a project, joined via the parent action.
  Future<List<ActionComment>> getForProject(String projectId) async {
    final q = customSelect(
      'SELECT c.* FROM action_comments c '
      'JOIN project_actions a ON a.id = c.action_id '
      'WHERE a.project_id = ? '
      'ORDER BY c.created_at ASC',
      variables: [Variable<String>(projectId)],
      readsFrom: {actionComments, projectActions},
    );
    final rows = await q.get();
    return rows.map((r) => actionComments.map(r.data)).toList();
  }

  Future<void> upsertComment(ActionCommentsCompanion entry) {
    return into(actionComments).insertOnConflictUpdate(entry);
  }

  Future<int> deleteComment(String id) {
    return (delete(actionComments)..where((t) => t.id.equals(id))).go();
  }

  Future<int> deleteForAction(String actionId) {
    return (delete(actionComments)..where((t) => t.actionId.equals(actionId)))
        .go();
  }

  /// Deletes all comments belonging to actions owned by [projectId].
  /// Used by the JSON importer's pre-import clear so comments don't outlive
  /// their parent action rows.
  Future<int> deleteAllForProject(String projectId) {
    return customUpdate(
      'DELETE FROM action_comments WHERE action_id IN '
      '(SELECT id FROM project_actions WHERE project_id = ?)',
      variables: [Variable<String>(projectId)],
      updates: {actionComments},
    );
  }
}
