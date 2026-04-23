import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// Idempotent migration: for each project that has ProgrammeOverview content
/// but no ProjectCharter, creates a ProjectCharter row by copying:
///   vision          → vision
///   scope           → scope_in
///   programmeManager (team notes) → delivery_approach
///
/// Safe to re-run. Only inserts if no charter exists for the project.
class CharterMigration {
  final AppDatabase db;

  CharterMigration(this.db);

  /// Returns true if any projects were migrated.
  Future<bool> runIfNeeded() async {
    final projects = await db.projectDao.getAllProjects();
    var migrated = false;

    for (final project in projects) {
      final existing =
          await db.projectCharterDao.getForProject(project.id);
      if (existing != null) continue; // already has a charter

      final overview =
          await db.programmeDao.getOverviewForProject(project.id);
      if (overview == null) continue; // no overview data to copy

      final hasContent = (overview.vision?.isNotEmpty ?? false) ||
          (overview.scope?.isNotEmpty ?? false) ||
          (overview.programmeManager?.isNotEmpty ?? false);
      if (!hasContent) continue;

      await db.projectCharterDao.upsert(
        ProjectChartersCompanion(
          id: Value(const Uuid().v4()),
          projectId: Value(project.id),
          vision: Value(overview.vision?.isNotEmpty == true
              ? overview.vision
              : null),
          scopeIn: Value(overview.scope?.isNotEmpty == true
              ? overview.scope
              : null),
          deliveryApproach: Value(
              overview.programmeManager?.isNotEmpty == true
                  ? overview.programmeManager
                  : null),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      migrated = true;
    }

    return migrated;
  }
}
