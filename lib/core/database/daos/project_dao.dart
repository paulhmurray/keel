part of '../database.dart';

@DriftAccessor(tables: [Projects])
class ProjectDao extends DatabaseAccessor<AppDatabase> with _$ProjectDaoMixin {
  ProjectDao(super.db);

  // Watch all projects
  Stream<List<Project>> watchAllProjects() => select(projects).watch();

  // Get all projects (one-shot)
  Future<List<Project>> getAllProjects() => select(projects).get();

  // Get a single project by id
  Future<Project?> getProjectById(String id) {
    return (select(projects)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  // Insert a new project
  Future<void> insertProject(ProjectsCompanion entry) {
    return into(projects).insert(entry);
  }

  // Update an existing project
  Future<bool> updateProject(ProjectsCompanion entry) {
    return update(projects).replace(entry);
  }

  // Delete a project by id
  Future<int> deleteProject(String id) {
    return (delete(projects)..where((t) => t.id.equals(id))).go();
  }

  // Upsert a project
  Future<void> upsertProject(ProjectsCompanion entry) {
    return into(projects).insertOnConflictUpdate(entry);
  }
}
