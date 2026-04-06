part of '../database.dart';

@DriftAccessor(tables: [InboxItems])
class InboxDao extends DatabaseAccessor<AppDatabase> with _$InboxDaoMixin {
  InboxDao(super.db);

  Stream<List<InboxItem>> watchInboxForProject(String projectId) {
    return (select(inboxItems)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<InboxItem>> getInboxForProject(String projectId) {
    return (select(inboxItems)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Stream<List<InboxItem>> watchUnprocessedForProject(String projectId) {
    return (select(inboxItems)
          ..where((t) =>
              t.projectId.equals(projectId) &
              t.status.equals('unprocessed'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<InboxItem?> getInboxItemById(String id) {
    return (select(inboxItems)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertInboxItem(InboxItemsCompanion entry) {
    return into(inboxItems).insert(entry);
  }

  Future<bool> updateInboxItem(InboxItemsCompanion entry) {
    return update(inboxItems).replace(entry);
  }

  Future<int> deleteInboxItem(String id) {
    return (delete(inboxItems)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertInboxItem(InboxItemsCompanion entry) {
    return into(inboxItems).insertOnConflictUpdate(entry);
  }
}
