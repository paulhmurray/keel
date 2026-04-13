part of '../database.dart';

const _kDefaultChecklist = [
  {'label': 'Template reviewed and filled', 'checked': false},
  {'label': 'Submitted to approver', 'checked': false},
  {'label': 'Approval received', 'checked': false},
  {'label': 'Evidence document uploaded', 'checked': false},
];

@DriftAccessor(tables: [
  Organisations,
  Playbooks,
  PlaybookStages,
  StageTemplates,
  ProjectPlaybooks,
  ProjectStageProgresses,
])
class PlaybookDao extends DatabaseAccessor<AppDatabase>
    with _$PlaybookDaoMixin {
  PlaybookDao(super.db);

  // ---------------------------------------------------------------------------
  // Organisations
  // ---------------------------------------------------------------------------

  Stream<List<Organisation>> watchAllOrganisations() =>
      select(organisations).watch();

  Future<List<Organisation>> getAllOrganisations() =>
      select(organisations).get();

  Future<Organisation?> getOrganisationById(String id) =>
      (select(organisations)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertOrganisation(OrganisationsCompanion entry) =>
      into(organisations).insertOnConflictUpdate(entry);

  Future<void> deleteOrganisation(String id) =>
      (delete(organisations)..where((t) => t.id.equals(id))).go();

  // ---------------------------------------------------------------------------
  // Playbooks
  // ---------------------------------------------------------------------------

  Stream<List<Playbook>> watchPlaybooksForOrg(String orgId) =>
      (select(playbooks)..where((t) => t.organisationId.equals(orgId))).watch();

  Future<List<Playbook>> getPlaybooksForOrg(String orgId) =>
      (select(playbooks)..where((t) => t.organisationId.equals(orgId))).get();

  Future<Playbook?> getPlaybookById(String id) =>
      (select(playbooks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertPlaybook(PlaybooksCompanion entry) =>
      into(playbooks).insertOnConflictUpdate(entry);

  Future<void> deletePlaybook(String id) =>
      (delete(playbooks)..where((t) => t.id.equals(id))).go();

  // ---------------------------------------------------------------------------
  // PlaybookStages
  // ---------------------------------------------------------------------------

  Stream<List<PlaybookStage>> watchStagesForPlaybook(String playbookId) =>
      (select(playbookStages)
            ..where((t) => t.playbookId.equals(playbookId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  Future<List<PlaybookStage>> getStagesForPlaybook(String playbookId) =>
      (select(playbookStages)
            ..where((t) => t.playbookId.equals(playbookId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  Future<PlaybookStage?> getStageById(String id) =>
      (select(playbookStages)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertStage(PlaybookStagesCompanion entry) =>
      into(playbookStages).insertOnConflictUpdate(entry);

  Future<void> deleteStage(String id) =>
      (delete(playbookStages)..where((t) => t.id.equals(id))).go();

  Future<void> reorderStages(List<String> orderedIds) async {
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(playbookStages)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(PlaybookStagesCompanion(
          sortOrder: Value(i),
          updatedAt: Value(DateTime.now()),
        ));
      }
    });
  }

  // ---------------------------------------------------------------------------
  // StageTemplates
  // ---------------------------------------------------------------------------

  Future<List<StageTemplate>> getTemplatesForStage(String stageId) =>
      (select(stageTemplates)..where((t) => t.stageId.equals(stageId))).get();

  Future<void> upsertTemplate(StageTemplatesCompanion entry) =>
      into(stageTemplates).insertOnConflictUpdate(entry);

  Future<void> deleteTemplate(String id) =>
      (delete(stageTemplates)..where((t) => t.id.equals(id))).go();

  // ---------------------------------------------------------------------------
  // ProjectPlaybooks
  // ---------------------------------------------------------------------------

  Stream<ProjectPlaybook?> watchProjectPlaybook(String projectId) =>
      (select(projectPlaybooks)
            ..where((t) => t.projectId.equals(projectId)))
          .watchSingleOrNull();

  Future<ProjectPlaybook?> getProjectPlaybook(String projectId) =>
      (select(projectPlaybooks)
            ..where((t) => t.projectId.equals(projectId)))
          .getSingleOrNull();

  Future<void> upsertProjectPlaybook(ProjectPlaybooksCompanion entry) =>
      into(projectPlaybooks).insertOnConflictUpdate(entry);

  Future<void> detachPlaybook(String projectId) =>
      (delete(projectPlaybooks)
            ..where((t) => t.projectId.equals(projectId)))
          .go();

  // ---------------------------------------------------------------------------
  // ProjectStageProgresses
  // ---------------------------------------------------------------------------

  Stream<List<ProjectStageProgressesData>> watchProgressForProjectPlaybook(
          String projectPlaybookId) =>
      (select(projectStageProgresses)
            ..where((t) => t.projectPlaybookId.equals(projectPlaybookId)))
          .watch();

  Future<List<ProjectStageProgressesData>> getProgressForProjectPlaybook(
          String projectPlaybookId) =>
      (select(projectStageProgresses)
            ..where((t) => t.projectPlaybookId.equals(projectPlaybookId)))
          .get();

  Future<ProjectStageProgressesData?> getProgressForStage(
          String projectPlaybookId, String stageId) =>
      (select(projectStageProgresses)
            ..where((t) =>
                t.projectPlaybookId.equals(projectPlaybookId) &
                t.stageId.equals(stageId)))
          .getSingleOrNull();

  Future<void> upsertProgress(ProjectStageProgressesCompanion entry) =>
      into(projectStageProgresses).insertOnConflictUpdate(entry);

  // ---------------------------------------------------------------------------
  // Attach playbook to project (creates all progress records)
  // ---------------------------------------------------------------------------

  Future<void> attachPlaybookToProject({
    required String projectId,
    required String playbookId,
  }) async {
    const uuid = Uuid();
    final now = DateTime.now();

    await transaction(() async {
      // Remove any existing attachment
      await (delete(projectPlaybooks)
            ..where((t) => t.projectId.equals(projectId)))
          .go();

      final ppId = uuid.v4();
      await into(projectPlaybooks).insert(ProjectPlaybooksCompanion(
        id: Value(ppId),
        projectId: Value(projectId),
        playbookId: Value(playbookId),
        attachedAt: Value(now),
      ));

      final stages = await getStagesForPlaybook(playbookId);
      for (final stage in stages) {
        await into(projectStageProgresses).insert(
          ProjectStageProgressesCompanion(
            id: Value(uuid.v4()),
            projectPlaybookId: Value(ppId),
            stageId: Value(stage.id),
            status: const Value('not_started'),
            checklist: Value(_defaultChecklistJson()),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  static String _defaultChecklistJson() {
    return const JsonEncoder().convert(_kDefaultChecklist);
  }
}
