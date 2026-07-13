import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/import/json_importer.dart';

/// Deletion propagation for the playbook attachment: a pull import must
/// clear the project's playbook attachment + stage progress before
/// re-importing, so a detach on the source machine is reflected here.
/// (The catalog — organisations/playbooks/stages/templates — is shared
/// across projects and must survive.)
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() => db.close());

  Map<String, dynamic> minimalExport(String projectId) => {
        'keel_version': '1.0',
        'exported_at': DateTime(2026, 7, 1).toIso8601String(),
        'project': {
          'id': projectId,
          'name': 'Proj',
          'description': null,
          'start_date': null,
          'status': 'active',
        },
      };

  Future<void> seedAttachedPlaybook(String projectId) async {
    await db.projectDao.upsertProject(ProjectsCompanion(
      id: Value(projectId),
      name: const Value('Proj'),
    ));
    await db.playbookDao.upsertOrganisation(const OrganisationsCompanion(
      id: Value('org-1'),
      name: Value('Org'),
    ));
    await db.playbookDao.upsertPlaybook(const PlaybooksCompanion(
      id: Value('pb-1'),
      organisationId: Value('org-1'),
      name: Value('Delivery Playbook'),
    ));
    await db.playbookDao.upsertStage(const PlaybookStagesCompanion(
      id: Value('st-1'),
      playbookId: Value('pb-1'),
      name: Value('Discovery'),
      sortOrder: Value(0),
    ));
    await db.playbookDao.upsertProjectPlaybook(ProjectPlaybooksCompanion(
      id: const Value('pp-1'),
      projectId: Value(projectId),
      playbookId: const Value('pb-1'),
    ));
    await db.playbookDao.upsertProgress(const ProjectStageProgressesCompanion(
      id: Value('prog-1'),
      projectPlaybookId: Value('pp-1'),
      stageId: Value('st-1'),
      status: Value('in_progress'),
    ));
  }

  test('import without playbook section clears attachment + progress', () async {
    await seedAttachedPlaybook('p-1');

    // Source machine detached the playbook → its export has no playbook
    // section. Importing that blob must remove the local attachment.
    await JsonImporter.importFromString(jsonEncode(minimalExport('p-1')), db);

    expect(await db.playbookDao.getProjectPlaybook('p-1'), isNull);
    final progress =
        await db.playbookDao.getProgressForProjectPlaybook('pp-1');
    expect(progress, isEmpty);

    // Shared catalog survives — other projects may still use it.
    expect(await db.playbookDao.getPlaybookById('pb-1'), isNotNull);
    expect(await db.playbookDao.getOrganisationById('org-1'), isNotNull);
  });

  test('import does not touch another project\'s playbook attachment',
      () async {
    await seedAttachedPlaybook('p-1');
    // Second project attached to the same catalog playbook.
    await db.projectDao.upsertProject(const ProjectsCompanion(
      id: Value('p-2'),
      name: Value('Other'),
    ));
    await db.playbookDao.upsertProjectPlaybook(const ProjectPlaybooksCompanion(
      id: Value('pp-2'),
      projectId: Value('p-2'),
      playbookId: Value('pb-1'),
    ));

    await JsonImporter.importFromString(jsonEncode(minimalExport('p-1')), db);

    expect(await db.playbookDao.getProjectPlaybook('p-1'), isNull);
    expect(await db.playbookDao.getProjectPlaybook('p-2'), isNotNull);
  });
}
