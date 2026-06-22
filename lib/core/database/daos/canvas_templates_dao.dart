part of '../database.dart';

@DriftAccessor(tables: [CanvasTemplates])
class CanvasTemplatesDao extends DatabaseAccessor<AppDatabase>
    with _$CanvasTemplatesDaoMixin {
  CanvasTemplatesDao(super.db);

  /// Watches all template instances for [projectId], ordered by most-
  /// recently-edited first (matches the gallery's "Your Templates"
  /// sort).
  Stream<List<CanvasTemplate>> watchTemplatesForProject(String projectId) {
    return (select(canvasTemplates)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  Future<List<CanvasTemplate>> getTemplatesForProject(String projectId) {
    return (select(canvasTemplates)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<CanvasTemplate?> getTemplateById(String id) {
    return (select(canvasTemplates)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<CanvasTemplate?> watchTemplateById(String id) {
    return (select(canvasTemplates)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<void> insertTemplate(CanvasTemplatesCompanion entry) {
    return into(canvasTemplates).insert(entry);
  }

  /// Updates only the supplied fields on an existing template and
  /// bumps [updatedAt] automatically. Returns the number of rows
  /// changed (0 if the id didn't match anything).
  Future<int> patchTemplate(String id, CanvasTemplatesCompanion patch) {
    final withTimestamp = patch.copyWith(updatedAt: Value(DateTime.now()));
    return (update(canvasTemplates)..where((t) => t.id.equals(id)))
        .write(withTimestamp);
  }

  Future<int> deleteTemplate(String id) {
    return (delete(canvasTemplates)..where((t) => t.id.equals(id))).go();
  }
}
