import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../database/database.dart';
import '_json_importer_io.dart' if (dart.library.html) '_json_importer_web.dart';

class ImportResult {
  final String projectName;
  final int risks,
      assumptions,
      issues,
      dependencies,
      decisions,
      persons,
      actions,
      journalEntries,
      contextEntries;

  const ImportResult({
    required this.projectName,
    required this.risks,
    required this.assumptions,
    required this.issues,
    required this.dependencies,
    required this.decisions,
    required this.persons,
    required this.actions,
    required this.journalEntries,
    required this.contextEntries,
  });
}

class JsonImporter {
  /// Reads a JSON file and imports it. Returns a summary of what was imported.
  /// Not supported on web — use [importFromString] instead.
  static Future<ImportResult> importFromFile(
      String filePath, AppDatabase db) async {
    if (kIsWeb) throw UnsupportedError('importFromFile not supported on web. Use importFromString.');
    final content = await readFileAsString(filePath);
    final data = json.decode(content) as Map<String, dynamic>;
    return _import(data, db);
  }

  static Future<ImportResult> importFromString(
      String jsonStr, AppDatabase db) async {
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    return _import(data, db);
  }

  static Future<ImportResult> _import(
      Map<String, dynamic> data, AppDatabase db) async {
    // Project
    final projectData = data['project'] as Map<String, dynamic>;
    final projectId = projectData['id'] as String;

    // Clear all synced tables for this project before importing.
    // This ensures deletions made on the source device are reflected here —
    // upsert-only would leave deleted records in place.
    await _clearSyncedTables(db, projectId);

    await db.projectDao.upsertProject(ProjectsCompanion(
      id: Value(projectId),
      name: Value(projectData['name'] as String),
      description: Value(projectData['description'] as String?),
      startDate: Value(projectData['start_date'] as String?),
      status: Value(projectData['status'] as String? ?? 'active'),
    ));

    // Programme overview
    final progData = data['programme'] as Map<String, dynamic>?;
    if (progData != null) {
      final ov = progData['overview'] as Map<String, dynamic>?;
      if (ov != null) {
        await db.programmeDao.upsertOverview(ProgrammeOverviewsCompanion(
          id: Value(ov['id'] as String),
          projectId: Value(projectId),
          vision: Value(ov['vision'] as String?),
          objectives: Value(ov['objectives'] as String?),
          scope: Value(ov['scope'] as String?),
          outOfScope: Value(ov['out_of_scope'] as String?),
          keyMilestones: Value(ov['key_milestones'] as String?),
          budget: Value(ov['budget'] as String?),
          sponsor: Value(ov['sponsor'] as String?),
          programmeManager: Value(ov['programme_manager'] as String?),
        ));
      }
      for (final w in (progData['workstreams'] as List? ?? [])) {
        final wm = w as Map<String, dynamic>;
        await db.programmeDao.upsertWorkstream(WorkstreamsCompanion(
          id: Value(wm['id'] as String),
          projectId: Value(projectId),
          name: Value(wm['name'] as String),
          lane: Value(wm['lane'] as String? ?? 'General'),
          lead: Value(wm['lead'] as String?),
          status: Value(wm['status'] as String? ?? 'not_started'),
          startDate: Value(wm['start_date'] as String?),
          endDate: Value(wm['end_date'] as String?),
          notes: Value(wm['notes'] as String?),
          sortOrder: Value(wm['sort_order'] as int? ?? 0),
        ));
      }
      for (final g in (progData['governance'] as List? ?? [])) {
        final gm = g as Map<String, dynamic>;
        await db.programmeDao.upsertGovernance(GovernanceCadencesCompanion(
          id: Value(gm['id'] as String),
          projectId: Value(projectId),
          meetingName: Value(gm['meeting_name'] as String),
          frequency: Value(gm['frequency'] as String?),
          chair: Value(gm['chair'] as String?),
          myRole: Value(gm['my_role'] as String?),
          notes: Value(gm['notes'] as String?),
        ));
      }
    }

    // RAID
    final raidData = data['raid'] as Map<String, dynamic>?;
    int riskCount = 0, assumCount = 0, issueCount = 0, depCount = 0;
    if (raidData != null) {
      for (final r in (raidData['risks'] as List? ?? [])) {
        final rm = r as Map<String, dynamic>;
        await db.raidDao.upsertRisk(RisksCompanion(
          id: Value(rm['id'] as String),
          projectId: Value(projectId),
          ref: Value(rm['ref'] as String?),
          description: Value(rm['description'] as String),
          likelihood: Value(rm['likelihood'] as String? ?? 'medium'),
          impact: Value(rm['impact'] as String? ?? 'medium'),
          mitigation: Value(rm['mitigation'] as String?),
          owner: Value(rm['owner'] as String?),
          status: Value(rm['status'] as String? ?? 'open'),
          source: Value(rm['source'] as String? ?? 'manual'),
          sourceNote: Value(rm['source_note'] as String?),
        ));
        riskCount++;
      }
      for (final a in (raidData['assumptions'] as List? ?? [])) {
        final am = a as Map<String, dynamic>;
        await db.raidDao.upsertAssumption(AssumptionsCompanion(
          id: Value(am['id'] as String),
          projectId: Value(projectId),
          ref: Value(am['ref'] as String?),
          description: Value(am['description'] as String),
          owner: Value(am['owner'] as String?),
          status: Value(am['status'] as String? ?? 'open'),
          validatedBy: Value(am['validated_by'] as String?),
          validatedAt: Value(am['validated_at'] != null
              ? DateTime.tryParse(am['validated_at'] as String)
              : null),
          source: Value(am['source'] as String? ?? 'manual'),
          sourceNote: Value(am['source_note'] as String?),
        ));
        assumCount++;
      }
      for (final i in (raidData['issues'] as List? ?? [])) {
        final im = i as Map<String, dynamic>;
        await db.raidDao.upsertIssue(IssuesCompanion(
          id: Value(im['id'] as String),
          projectId: Value(projectId),
          ref: Value(im['ref'] as String?),
          description: Value(im['description'] as String),
          owner: Value(im['owner'] as String?),
          dueDate: Value(im['due_date'] as String?),
          priority: Value(im['priority'] as String? ?? 'medium'),
          status: Value(im['status'] as String? ?? 'open'),
          resolution: Value(im['resolution'] as String?),
          source: Value(im['source'] as String? ?? 'manual'),
          sourceNote: Value(im['source_note'] as String?),
        ));
        issueCount++;
      }
      for (final d in (raidData['dependencies'] as List? ?? [])) {
        final dm = d as Map<String, dynamic>;
        await db.raidDao.upsertDependency(ProgramDependenciesCompanion(
          id: Value(dm['id'] as String),
          projectId: Value(projectId),
          ref: Value(dm['ref'] as String?),
          description: Value(dm['description'] as String),
          dependencyType: Value(dm['dependency_type'] as String? ?? 'inbound'),
          owner: Value(dm['owner'] as String?),
          status: Value(dm['status'] as String? ?? 'open'),
          dueDate: Value(dm['due_date'] as String?),
          source: Value(dm['source'] as String? ?? 'manual'),
          sourceNote: Value(dm['source_note'] as String?),
        ));
        depCount++;
      }
    }

    // Decisions
    int decisionCount = 0;
    for (final d in (data['decisions'] as List? ?? [])) {
      final dm = d as Map<String, dynamic>;
      await db.decisionsDao.upsertDecision(DecisionsCompanion(
        id: Value(dm['id'] as String),
        projectId: Value(projectId),
        ref: Value(dm['ref'] as String?),
        description: Value(dm['description'] as String),
        status: Value(dm['status'] as String? ?? 'pending'),
        decisionMaker: Value(dm['decision_maker'] as String?),
        dueDate: Value(dm['due_date'] as String?),
        rationale: Value(dm['rationale'] as String?),
        outcome: Value(dm['outcome'] as String?),
        source: Value(dm['source'] as String? ?? 'manual'),
        sourceNote: Value(dm['source_note'] as String?),
      ));
      decisionCount++;
    }

    // People — persons first, then profiles
    int personCount = 0;
    final peopleData = data['people'] as Map<String, dynamic>?;
    if (peopleData != null) {
      for (final p in (peopleData['persons'] as List? ?? [])) {
        final pm = p as Map<String, dynamic>;
        await db.peopleDao.upsertPerson(PersonsCompanion(
          id: Value(pm['id'] as String),
          projectId: Value(projectId),
          name: Value(pm['name'] as String),
          email: Value(pm['email'] as String?),
          role: Value(pm['role'] as String?),
          organisation: Value(pm['organisation'] as String?),
          phone: Value(pm['phone'] as String?),
          teamsHandle: Value(pm['teams_handle'] as String?),
          personType: Value(pm['person_type'] as String? ?? 'stakeholder'),
        ));
        personCount++;
      }
      for (final s in (peopleData['stakeholder_profiles'] as List? ?? [])) {
        final sm = s as Map<String, dynamic>;
        await db.peopleDao.upsertStakeholder(StakeholderProfilesCompanion(
          id: Value(sm['id'] as String),
          projectId: Value(projectId),
          personId: Value(sm['person_id'] as String),
          influence: Value(sm['influence'] as String?),
          interest: Value(sm['interest'] as String?),
          stance: Value(sm['stance'] as String?),
          engagementStrategy: Value(sm['engagement_strategy'] as String?),
          notes: Value(sm['notes'] as String?),
        ));
      }
      for (final c in (peopleData['colleague_profiles'] as List? ?? [])) {
        final cm = c as Map<String, dynamic>;
        await db.peopleDao.upsertColleague(ColleagueProfilesCompanion(
          id: Value(cm['id'] as String),
          projectId: Value(projectId),
          personId: Value(cm['person_id'] as String),
          workingStyle: Value(cm['working_style'] as String?),
          preferences: Value(cm['preferences'] as String?),
          notes: Value(cm['notes'] as String?),
          team: Value(cm['team'] as String?),
          directReport: Value(cm['direct_report'] as bool? ?? false),
        ));
      }
    }

    // Actions
    int actionCount = 0;
    for (final a in (data['actions'] as List? ?? [])) {
      final am = a as Map<String, dynamic>;
      await db.actionsDao.upsertAction(ProjectActionsCompanion(
        id: Value(am['id'] as String),
        projectId: Value(projectId),
        ref: Value(am['ref'] as String?),
        description: Value(am['description'] as String),
        owner: Value(am['owner'] as String?),
        dueDate: Value(am['due_date'] as String?),
        status: Value(am['status'] as String? ?? 'open'),
        priority: Value(am['priority'] as String? ?? 'medium'),
        source: Value(am['source'] as String? ?? 'manual'),
        sourceNote: Value(am['source_note'] as String?),
      ));
      actionCount++;
    }

    // Context entries
    int contextCount = 0;
    for (final c in (data['context'] as List? ?? [])) {
      final cm = c as Map<String, dynamic>;
      await db.contextDao.upsertEntry(ContextEntriesCompanion(
        id: Value(cm['id'] as String),
        projectId: Value(projectId),
        title: Value(cm['title'] as String),
        content: Value(cm['content'] as String),
        entryType: Value(cm['entry_type'] as String? ?? 'observation'),
        tags: Value(cm['tags'] as String?),
        source: Value(cm['source'] as String? ?? 'manual'),
      ));
      contextCount++;
    }

    // Documents
    final docList = data['documents'];
    // Support both old format ({metadata: [...]}) and new flat list
    final rawDocs = docList is Map
        ? (docList['metadata'] as List? ?? [])
        : (docList as List? ?? []);
    for (final d in rawDocs) {
      final dm = d as Map<String, dynamic>;
      await db.contextDao.upsertDocument(DocumentsCompanion(
        id: Value(dm['id'] as String),
        projectId: Value(projectId),
        title: Value(dm['title'] as String),
        content: Value(dm['content'] as String?),
        filePath: Value(dm['file_path'] as String?),
        documentType: Value(dm['document_type'] as String?),
        tags: Value(dm['tags'] as String?),
      ));
    }

    // Journal entries + links
    int journalCount = 0;
    final journalData = data['journal'] as Map<String, dynamic>?;
    if (journalData != null) {
      for (final e in (journalData['entries'] as List? ?? [])) {
        final em = e as Map<String, dynamic>;
        await db.journalDao.upsertEntry(JournalEntriesCompanion(
          id: Value(em['id'] as String),
          projectId: Value(projectId),
          title: Value(em['title'] as String?),
          body: Value(em['body'] as String),
          entryDate: Value(em['entry_date'] as String),
          meetingContext: Value(em['meeting_context'] as String?),
          parsed: Value(em['parsed'] as bool? ?? false),
        ));
        journalCount++;
      }
      for (final l in (journalData['links'] as List? ?? [])) {
        final lm = l as Map<String, dynamic>;
        // Use insertOnConflictUpdate via raw insert to avoid duplicates
        try {
          await db.journalDao.insertLink(JournalEntryLinksCompanion(
            id: Value(lm['id'] as String),
            entryId: Value(lm['entry_id'] as String),
            itemType: Value(lm['item_type'] as String),
            itemId: Value(lm['item_id'] as String),
            linkType: Value(lm['link_type'] as String? ?? 'created'),
          ));
        } catch (_) {
          // ignore duplicate links
        }
      }
    }

    // Playbook
    final playbookSection = data['playbook'] as Map<String, dynamic>?;
    if (playbookSection != null) {
      final orgData = playbookSection['organisation'] as Map<String, dynamic>?;
      if (orgData != null) {
        await db.playbookDao.upsertOrganisation(OrganisationsCompanion(
          id: Value(orgData['id'] as String),
          name: Value(orgData['name'] as String),
          shortName: Value(orgData['short_name'] as String?),
          notes: Value(orgData['notes'] as String?),
        ));
      }
      final pbData = playbookSection['playbook'] as Map<String, dynamic>?;
      if (pbData != null) {
        await db.playbookDao.upsertPlaybook(PlaybooksCompanion(
          id: Value(pbData['id'] as String),
          organisationId: Value(pbData['organisation_id'] as String),
          name: Value(pbData['name'] as String),
          description: Value(pbData['description'] as String?),
          version: Value(pbData['version'] as String?),
        ));
      }
      for (final s in (playbookSection['stages'] as List? ?? [])) {
        final sm = s as Map<String, dynamic>;
        await db.playbookDao.upsertStage(PlaybookStagesCompanion(
          id: Value(sm['id'] as String),
          playbookId: Value(sm['playbook_id'] as String),
          name: Value(sm['name'] as String),
          description: Value(sm['description'] as String?),
          sortOrder: Value(sm['sort_order'] as int? ?? 0),
          approverRole: Value(sm['approver_role'] as String?),
          gateCondition: Value(sm['gate_condition'] as String?),
          notes: Value(sm['notes'] as String?),
        ));
      }
      for (final t in (playbookSection['templates'] as List? ?? [])) {
        final tm = t as Map<String, dynamic>;
        await db.playbookDao.upsertTemplate(StageTemplatesCompanion(
          id: Value(tm['id'] as String),
          stageId: Value(tm['stage_id'] as String),
          name: Value(tm['name'] as String),
          filename: Value(tm['filename'] as String),
          filePath: Value(tm['file_path'] as String),
          fileType: Value(tm['file_type'] as String? ?? 'other'),
          fillStrategy: Value(tm['fill_strategy'] as String? ?? 'companion'),
          fieldHints: Value(tm['field_hints'] as String?),
        ));
      }
      final ppData =
          playbookSection['project_playbook'] as Map<String, dynamic>?;
      if (ppData != null) {
        await db.playbookDao.upsertProjectPlaybook(ProjectPlaybooksCompanion(
          id: Value(ppData['id'] as String),
          projectId: Value(ppData['project_id'] as String),
          playbookId: Value(ppData['playbook_id'] as String),
          currentStageId: Value(ppData['current_stage_id'] as String?),
          attachedAt: Value(ppData['attached_at'] != null
              ? DateTime.parse(ppData['attached_at'] as String)
              : DateTime.now()),
        ));
        for (final sp
            in (playbookSection['stage_progresses'] as List? ?? [])) {
          final spm = sp as Map<String, dynamic>;
          await db.playbookDao.upsertProgress(ProjectStageProgressesCompanion(
            id: Value(spm['id'] as String),
            projectPlaybookId: Value(spm['project_playbook_id'] as String),
            stageId: Value(spm['stage_id'] as String),
            status: Value(spm['status'] as String? ?? 'not_started'),
            gateMet: Value(spm['gate_met'] as bool? ?? false),
            approvedBy: Value(spm['approved_by'] as String?),
            approvedAt: Value(spm['approved_at'] != null
                ? DateTime.tryParse(spm['approved_at'] as String)
                : null),
            approvalNotes: Value(spm['approval_notes'] as String?),
            evidenceFilename: Value(spm['evidence_filename'] as String?),
            evidenceFilePath: Value(spm['evidence_file_path'] as String?),
            evidenceUploadedAt: Value(spm['evidence_uploaded_at'] != null
                ? DateTime.tryParse(spm['evidence_uploaded_at'] as String)
                : null),
            checklist: Value(spm['checklist'] as String?),
            generatedDocPath: Value(spm['generated_doc_path'] as String?),
            generatedAt: Value(spm['generated_at'] != null
                ? DateTime.tryParse(spm['generated_at'] as String)
                : null),
            journalEntryId: Value(spm['journal_entry_id'] as String?),
            notes: Value(spm['notes'] as String?),
          ));
        }
      }
    }

    // Status reports
    for (final r in (data['reports'] as List? ?? [])) {
      final rm = r as Map<String, dynamic>;
      await db.reportsDao.upsertReport(StatusReportsCompanion(
        id: Value(rm['id'] as String),
        projectId: Value(projectId),
        title: Value(rm['title'] as String),
        period: Value(rm['period'] as String?),
        overallRag: Value(rm['overall_rag'] as String? ?? 'green'),
        summary: Value(rm['summary'] as String?),
        accomplishments: Value(rm['accomplishments'] as String?),
        nextSteps: Value(rm['next_steps'] as String?),
        risksHighlighted: Value(rm['risks_highlighted'] as String?),
      ));
    }

    return ImportResult(
      projectName: projectData['name'] as String,
      risks: riskCount,
      assumptions: assumCount,
      issues: issueCount,
      dependencies: depCount,
      decisions: decisionCount,
      persons: personCount,
      actions: actionCount,
      journalEntries: journalCount,
      contextEntries: contextCount,
    );
  }

  /// Deletes all rows for [projectId] from every table that the JSON export
  /// covers. Called before re-importing so that records deleted on the source
  /// device are removed here too (upsert-only would leave them in place).
  static Future<void> _clearSyncedTables(
      AppDatabase db, String projectId) async {
    final id = projectId;
    await (db.delete(db.programmeOverviews)
          ..where((t) => t.projectId.equals(id)))
        .go();
    await (db.delete(db.workstreams)..where((t) => t.projectId.equals(id)))
        .go();
    await (db.delete(db.governanceCadences)
          ..where((t) => t.projectId.equals(id)))
        .go();
    await (db.delete(db.risks)..where((t) => t.projectId.equals(id))).go();
    await (db.delete(db.assumptions)..where((t) => t.projectId.equals(id)))
        .go();
    await (db.delete(db.issues)..where((t) => t.projectId.equals(id))).go();
    await (db.delete(db.programDependencies)
          ..where((t) => t.projectId.equals(id)))
        .go();
    await (db.delete(db.decisions)..where((t) => t.projectId.equals(id)))
        .go();
    await (db.delete(db.projectActions)..where((t) => t.projectId.equals(id)))
        .go();
    await (db.delete(db.contextEntries)..where((t) => t.projectId.equals(id)))
        .go();
    await (db.delete(db.documents)..where((t) => t.projectId.equals(id)))
        .go();
    await (db.delete(db.statusReports)..where((t) => t.projectId.equals(id)))
        .go();
    // Journal links are keyed by entry_id, not project_id — delete them first
    final journalEntryIds = await (db.select(db.journalEntries)
          ..where((t) => t.projectId.equals(id)))
        .map((e) => e.id)
        .get();
    for (final eid in journalEntryIds) {
      await (db.delete(db.journalEntryLinks)
            ..where((t) => t.entryId.equals(eid)))
          .go();
    }
    await (db.delete(db.journalEntries)..where((t) => t.projectId.equals(id)))
        .go();
    // People — profiles first (FK to persons), then persons
    final personIds = await (db.select(db.persons)
          ..where((t) => t.projectId.equals(id)))
        .map((p) => p.id)
        .get();
    for (final pid in personIds) {
      await (db.delete(db.stakeholderProfiles)
            ..where((t) => t.personId.equals(pid)))
          .go();
      await (db.delete(db.colleagueProfiles)
            ..where((t) => t.personId.equals(pid)))
          .go();
    }
    await (db.delete(db.persons)..where((t) => t.projectId.equals(id))).go();
  }
}
