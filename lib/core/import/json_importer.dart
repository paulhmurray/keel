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
          lead: Value(wm['lead'] as String?),
          status: Value(wm['status'] as String? ?? 'green'),
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
}
