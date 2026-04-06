part of '../database.dart';

@DriftAccessor(tables: [JournalEntries, JournalEntryLinks])
class JournalDao extends DatabaseAccessor<AppDatabase> with _$JournalDaoMixin {
  JournalDao(super.db);

  Stream<List<JournalEntry>> watchEntriesForProject(String projectId) {
    return (select(journalEntries)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<JournalEntry>> getEntriesForProject(String projectId) {
    return (select(journalEntries)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<JournalEntry?> getEntryById(String id) {
    return (select(journalEntries)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertEntry(JournalEntriesCompanion entry) {
    return into(journalEntries).insert(entry);
  }

  Future<bool> updateEntry(JournalEntriesCompanion entry) {
    return update(journalEntries).replace(entry);
  }

  Future<int> deleteEntry(String id) {
    return (delete(journalEntries)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertEntry(JournalEntriesCompanion entry) {
    return into(journalEntries).insertOnConflictUpdate(entry);
  }

  Stream<List<JournalEntry>> watchRecentEntriesForProject(String projectId, {int limit = 3}) {
    return (select(journalEntries)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .watch();
  }

  Future<List<JournalEntryLink>> getLinksForEntry(String entryId) {
    return (select(journalEntryLinks)..where((t) => t.entryId.equals(entryId))).get();
  }

  Future<List<JournalEntryLink>> getLinksForItem(String itemId) {
    return (select(journalEntryLinks)..where((t) => t.itemId.equals(itemId))).get();
  }

  Future<void> insertLink(JournalEntryLinksCompanion link) {
    return into(journalEntryLinks).insert(link);
  }

  Future<void> deleteLinksForEntry(String entryId) {
    return (delete(journalEntryLinks)..where((t) => t.entryId.equals(entryId))).go();
  }

  Stream<int> watchEntryCountForProject(String projectId) {
    return (selectOnly(journalEntries)
          ..addColumns([journalEntries.id.count()])
          ..where(journalEntries.projectId.equals(projectId)))
        .map((row) => row.read(journalEntries.id.count()) ?? 0)
        .watchSingle();
  }
}
