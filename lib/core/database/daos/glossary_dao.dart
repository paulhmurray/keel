part of '../database.dart';

@DriftAccessor(tables: [GlossaryEntries])
class GlossaryDao extends DatabaseAccessor<AppDatabase>
    with _$GlossaryDaoMixin {
  GlossaryDao(super.db);

  Stream<List<GlossaryEntry>> watchForProject(String projectId) {
    return (select(glossaryEntries)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.type),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  Future<List<GlossaryEntry>> getForProject(String projectId) {
    return (select(glossaryEntries)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.type),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  Future<void> upsert(GlossaryEntriesCompanion entry) {
    return into(glossaryEntries).insertOnConflictUpdate(entry);
  }

  Future<void> deleteEntry(String id) {
    return (delete(glossaryEntries)..where((t) => t.id.equals(id))).go();
  }
}
