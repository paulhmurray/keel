part of '../database.dart';

@DriftAccessor(tables: [ActionCategories])
class ActionCategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$ActionCategoriesDaoMixin {
  ActionCategoriesDao(super.db);

  static const _presets = [
    ('Governance Forum',   '#8B5CF6', 0),
    ('Steering Committee', '#6366F1', 1),
    ('Status Report',      '#3B82F6', 2),
    ('Papers Due',         '#F97316', 3),
    ('Board Report',       '#EF4444', 4),
    ('Review Meeting',     '#14B8A6', 5),
    ('Admin',              '#6B7280', 6),
  ];

  Stream<List<ActionCategory>> watchForProject(String projectId) {
    return (select(actionCategories)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<List<ActionCategory>> getForProject(String projectId) {
    return (select(actionCategories)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<void> seedPresetsIfEmpty(String projectId) async {
    final existing = await getForProject(projectId);
    if (existing.isNotEmpty) return;
    for (final (name, color, order) in _presets) {
      await into(actionCategories).insert(ActionCategoriesCompanion(
        id: Value(const Uuid().v4()),
        projectId: Value(projectId),
        name: Value(name),
        color: Value(color),
        isPreset: const Value(true),
        sortOrder: Value(order),
      ));
    }
  }

  Future<void> upsert(ActionCategoriesCompanion entry) {
    return into(actionCategories).insertOnConflictUpdate(entry);
  }

  Future<void> deleteCategory(String id) {
    return (delete(actionCategories)..where((t) => t.id.equals(id))).go();
  }
}
