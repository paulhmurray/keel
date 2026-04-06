part of '../database.dart';

@DriftAccessor(tables: [ContextEntries, Documents])
class ContextDao extends DatabaseAccessor<AppDatabase> with _$ContextDaoMixin {
  ContextDao(super.db);

  // ---- ContextEntries ----

  Stream<List<ContextEntry>> watchEntriesForProject(String projectId) {
    return (select(contextEntries)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<ContextEntry>> getEntriesForProject(String projectId) {
    return (select(contextEntries)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<ContextEntry?> getEntryById(String id) {
    return (select(contextEntries)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertEntry(ContextEntriesCompanion entry) {
    return into(contextEntries).insert(entry);
  }

  Future<bool> updateEntry(ContextEntriesCompanion entry) {
    return update(contextEntries).replace(entry);
  }

  Future<int> deleteEntry(String id) {
    return (delete(contextEntries)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertEntry(ContextEntriesCompanion entry) {
    return into(contextEntries).insertOnConflictUpdate(entry);
  }

  // ---- Documents ----

  Stream<List<Document>> watchDocumentsForProject(String projectId) {
    return (select(documents)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<Document>> getDocumentsForProject(String projectId) {
    return (select(documents)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<Document?> getDocumentById(String id) {
    return (select(documents)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertDocument(DocumentsCompanion entry) {
    return into(documents).insert(entry);
  }

  Future<bool> updateDocument(DocumentsCompanion entry) {
    return update(documents).replace(entry);
  }

  Future<int> deleteDocument(String id) {
    return (delete(documents)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertDocument(DocumentsCompanion entry) {
    return into(documents).insertOnConflictUpdate(entry);
  }
}
