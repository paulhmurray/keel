part of '../database.dart';

@DriftAccessor(tables: [StatusReports])
class ReportsDao extends DatabaseAccessor<AppDatabase> with _$ReportsDaoMixin {
  ReportsDao(super.db);

  Stream<List<StatusReport>> watchReportsForProject(String projectId) {
    return (select(statusReports)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<StatusReport>> getReportsForProject(String projectId) {
    return (select(statusReports)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<StatusReport?> getReportById(String id) {
    return (select(statusReports)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertReport(StatusReportsCompanion entry) {
    return into(statusReports).insert(entry);
  }

  Future<bool> updateReport(StatusReportsCompanion entry) {
    return update(statusReports).replace(entry);
  }

  Future<int> deleteReport(String id) {
    return (delete(statusReports)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertReport(StatusReportsCompanion entry) {
    return into(statusReports).insertOnConflictUpdate(entry);
  }
}
