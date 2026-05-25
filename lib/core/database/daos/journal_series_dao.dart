part of '../database.dart';

@DriftAccessor(tables: [JournalSeriesDefs, JournalEntries])
class JournalSeriesDao extends DatabaseAccessor<AppDatabase>
    with _$JournalSeriesDaoMixin {
  JournalSeriesDao(super.db);

  Stream<List<JournalSeries>> watchForProject(String projectId) {
    return (select(journalSeriesDefs)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  Future<List<JournalSeries>> getForProject(String projectId) {
    return (select(journalSeriesDefs)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  Future<JournalSeries?> getById(String id) {
    return (select(journalSeriesDefs)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsert(JournalSeriesDefsCompanion entry) {
    return into(journalSeriesDefs).insertOnConflictUpdate(entry);
  }

  /// Deletes the series and clears [JournalEntries.seriesId] from any entry
  /// that was tagged with it. Entries themselves are kept — they just lose
  /// their series tag.
  Future<void> deleteSeries(String id) async {
    await transaction(() async {
      await (update(journalEntries)..where((t) => t.seriesId.equals(id)))
          .write(const JournalEntriesCompanion(seriesId: Value(null)));
      await (delete(journalSeriesDefs)..where((t) => t.id.equals(id))).go();
    });
  }
}
