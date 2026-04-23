part of '../database.dart';

@DriftAccessor(tables: [TeamRoles])
class TeamRoleDao extends DatabaseAccessor<AppDatabase>
    with _$TeamRoleDaoMixin {
  TeamRoleDao(super.db);

  Stream<List<TeamRole>> watchForProject(String projectId) =>
      (select(teamRoles)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  Future<List<TeamRole>> getForProject(String projectId) =>
      (select(teamRoles)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  Future<void> upsert(TeamRolesCompanion entry) =>
      into(teamRoles).insertOnConflictUpdate(entry);

  Future<void> updateRole(TeamRolesCompanion entry) =>
      (update(teamRoles)..where((t) => t.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteRole(String id) =>
      (delete(teamRoles)..where((t) => t.id.equals(id))).go();
}
