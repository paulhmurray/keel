part of '../database.dart';

@DriftAccessor(tables: [StakeholderRoles])
class StakeholderRoleDao extends DatabaseAccessor<AppDatabase>
    with _$StakeholderRoleDaoMixin {
  StakeholderRoleDao(super.db);

  Stream<List<StakeholderRole>> watchForProject(String projectId) =>
      (select(stakeholderRoles)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  Future<List<StakeholderRole>> getForProject(String projectId) =>
      (select(stakeholderRoles)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  Future<void> upsert(StakeholderRolesCompanion entry) =>
      into(stakeholderRoles).insertOnConflictUpdate(entry);

  Future<void> updateRole(StakeholderRolesCompanion entry) =>
      (update(stakeholderRoles)..where((t) => t.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteRole(String id) =>
      (delete(stakeholderRoles)..where((t) => t.id.equals(id))).go();
}
