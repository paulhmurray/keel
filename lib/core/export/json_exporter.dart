import 'dart:convert';
import '../database/database.dart';
import '../platform/web_download.dart';

class JsonExporter {
  /// Exports [projectId] data to a JSON string without writing to disk.
  /// Used internally by sync (encryption) and by [exportProject].
  static Future<String> exportProjectToString({
    required String projectId,
    required AppDatabase db,
  }) async {
    final data = await _buildExportData(projectId: projectId, db: db);
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  static Future<String> exportProject({
    required String projectId,
    required AppDatabase db,
  }) async {
    final project = await db.projectDao.getProjectById(projectId);
    if (project == null) throw Exception('Project not found');
    final data = await _buildExportData(projectId: projectId, db: db);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final slug =
        project.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final filename = 'keel_export_${slug}_$date.json';
    return saveTextAndOpen(filename, jsonStr);
  }

  static Future<Map<String, dynamic>> _buildExportData({
    required String projectId,
    required AppDatabase db,
  }) async {
    // Gather all data
    final project = await db.projectDao.getProjectById(projectId);
    if (project == null) throw Exception('Project not found');
    final overview = await db.programmeDao.getOverviewForProject(projectId);
    final workstreams = await db.programmeDao.getWorkstreamsForProject(projectId);
    final governance = await db.programmeDao.getGovernanceForProject(projectId);
    final risks = await db.raidDao.getRisksForProject(projectId);
    final assumptions = await db.raidDao.getAssumptionsForProject(projectId);
    final issues = await db.raidDao.getIssuesForProject(projectId);
    final deps = await db.raidDao.getDependenciesForProject(projectId);
    final decisions = await db.decisionsDao.getDecisionsForProject(projectId);
    final persons = await db.peopleDao.getPersonsForProject(projectId);
    final stakeholders = await db.peopleDao.getStakeholdersForProject(projectId);
    final colleagues = await db.peopleDao.getColleaguesForProject(projectId);
    final actions = await db.actionsDao.getActionsForProject(projectId);
    final contextEntries = await db.contextDao.getEntriesForProject(projectId);
    final documents = await db.contextDao.getDocumentsForProject(projectId);
    final reports = await db.reportsDao.getReportsForProject(projectId);
    final journalEntries = await db.journalDao.getEntriesForProject(projectId);
    // gather journal links for all entries
    final journalLinks = <Map<String, dynamic>>[];
    for (final entry in journalEntries) {
      final links = await db.journalDao.getLinksForEntry(entry.id);
      for (final link in links) {
        journalLinks.add({
          'id': link.id,
          'entry_id': link.entryId,
          'item_type': link.itemType,
          'item_id': link.itemId,
          'link_type': link.linkType,
          'created_at': link.createdAt.toIso8601String(),
        });
      }
    }

    final data = <String, dynamic>{
      'keel_version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'project': {
        'id': project.id,
        'name': project.name,
        'description': project.description,
        'start_date': project.startDate,
        'status': project.status,
        'created_at': project.createdAt.toIso8601String(),
        'updated_at': project.updatedAt.toIso8601String(),
      },
      'programme': {
        'overview': overview == null
            ? null
            : {
                'id': overview.id,
                'vision': overview.vision,
                'objectives': overview.objectives,
                'scope': overview.scope,
                'out_of_scope': overview.outOfScope,
                'key_milestones': overview.keyMilestones,
                'budget': overview.budget,
                'sponsor': overview.sponsor,
                'programme_manager': overview.programmeManager,
              },
        'workstreams': workstreams
            .map((w) => {
                  'id': w.id,
                  'name': w.name,
                  'lane': w.lane,
                  'lead': w.lead,
                  'status': w.status,
                  'start_date': w.startDate,
                  'end_date': w.endDate,
                  'notes': w.notes,
                  'sort_order': w.sortOrder,
                })
            .toList(),
        'governance': governance
            .map((g) => {
                  'id': g.id,
                  'meeting_name': g.meetingName,
                  'frequency': g.frequency,
                  'chair': g.chair,
                  'my_role': g.myRole,
                  'notes': g.notes,
                })
            .toList(),
      },
      'raid': {
        'risks': risks
            .map((r) => {
                  'id': r.id,
                  'ref': r.ref,
                  'description': r.description,
                  'likelihood': r.likelihood,
                  'impact': r.impact,
                  'mitigation': r.mitigation,
                  'owner': r.owner,
                  'status': r.status,
                  'source': r.source,
                  'source_note': r.sourceNote,
                  'created_at': r.createdAt.toIso8601String(),
                  'updated_at': r.updatedAt.toIso8601String(),
                })
            .toList(),
        'assumptions': assumptions
            .map((a) => {
                  'id': a.id,
                  'ref': a.ref,
                  'description': a.description,
                  'owner': a.owner,
                  'status': a.status,
                  'validated_by': a.validatedBy,
                  'validated_at': a.validatedAt?.toIso8601String(),
                  'source': a.source,
                  'source_note': a.sourceNote,
                  'created_at': a.createdAt.toIso8601String(),
                  'updated_at': a.updatedAt.toIso8601String(),
                })
            .toList(),
        'issues': issues
            .map((i) => {
                  'id': i.id,
                  'ref': i.ref,
                  'description': i.description,
                  'owner': i.owner,
                  'due_date': i.dueDate,
                  'priority': i.priority,
                  'status': i.status,
                  'resolution': i.resolution,
                  'source': i.source,
                  'source_note': i.sourceNote,
                  'created_at': i.createdAt.toIso8601String(),
                  'updated_at': i.updatedAt.toIso8601String(),
                })
            .toList(),
        'dependencies': deps
            .map((d) => {
                  'id': d.id,
                  'ref': d.ref,
                  'description': d.description,
                  'dependency_type': d.dependencyType,
                  'owner': d.owner,
                  'status': d.status,
                  'due_date': d.dueDate,
                  'source': d.source,
                  'source_note': d.sourceNote,
                  'created_at': d.createdAt.toIso8601String(),
                  'updated_at': d.updatedAt.toIso8601String(),
                })
            .toList(),
      },
      'decisions': decisions
          .map((d) => {
                'id': d.id,
                'ref': d.ref,
                'description': d.description,
                'status': d.status,
                'decision_maker': d.decisionMaker,
                'due_date': d.dueDate,
                'rationale': d.rationale,
                'outcome': d.outcome,
                'source': d.source,
                'source_note': d.sourceNote,
                'created_at': d.createdAt.toIso8601String(),
                'updated_at': d.updatedAt.toIso8601String(),
              })
          .toList(),
      'people': {
        'persons': persons
            .map((p) => {
                  'id': p.id,
                  'name': p.name,
                  'email': p.email,
                  'role': p.role,
                  'organisation': p.organisation,
                  'phone': p.phone,
                  'teams_handle': p.teamsHandle,
                  'person_type': p.personType,
                  'created_at': p.createdAt.toIso8601String(),
                  'updated_at': p.updatedAt.toIso8601String(),
                })
            .toList(),
        'stakeholder_profiles': stakeholders
            .map((s) => {
                  'id': s.id,
                  'person_id': s.personId,
                  'influence': s.influence,
                  'interest': s.interest,
                  'stance': s.stance,
                  'engagement_strategy': s.engagementStrategy,
                  'notes': s.notes,
                })
            .toList(),
        'colleague_profiles': colleagues
            .map((c) => {
                  'id': c.id,
                  'person_id': c.personId,
                  'working_style': c.workingStyle,
                  'preferences': c.preferences,
                  'notes': c.notes,
                  'team': c.team,
                  'direct_report': c.directReport,
                })
            .toList(),
      },
      'actions': actions
          .map((a) => {
                'id': a.id,
                'ref': a.ref,
                'description': a.description,
                'owner': a.owner,
                'due_date': a.dueDate,
                'status': a.status,
                'priority': a.priority,
                'source': a.source,
                'source_note': a.sourceNote,
                'created_at': a.createdAt.toIso8601String(),
                'updated_at': a.updatedAt.toIso8601String(),
              })
          .toList(),
      'context': contextEntries
          .map((c) => {
                'id': c.id,
                'title': c.title,
                'content': c.content,
                'entry_type': c.entryType,
                'tags': c.tags,
                'source': c.source,
                'created_at': c.createdAt.toIso8601String(),
                'updated_at': c.updatedAt.toIso8601String(),
              })
          .toList(),
      'documents': documents
          .map((d) => {
                'id': d.id,
                'title': d.title,
                'content': d.content,
                'file_path': d.filePath,
                'document_type': d.documentType,
                'tags': d.tags,
                'created_at': d.createdAt.toIso8601String(),
                'updated_at': d.updatedAt.toIso8601String(),
              })
          .toList(),
      'journal': {
        'entries': journalEntries
            .map((e) => {
                  'id': e.id,
                  'title': e.title,
                  'body': e.body,
                  'entry_date': e.entryDate,
                  'meeting_context': e.meetingContext,
                  'parsed': e.parsed,
                  'confirmed_at': e.confirmedAt?.toIso8601String(),
                  'created_at': e.createdAt.toIso8601String(),
                  'updated_at': e.updatedAt.toIso8601String(),
                })
            .toList(),
        'links': journalLinks,
      },
      'reports': reports
          .map((r) => {
                'id': r.id,
                'title': r.title,
                'period': r.period,
                'overall_rag': r.overallRag,
                'summary': r.summary,
                'accomplishments': r.accomplishments,
                'next_steps': r.nextSteps,
                'risks_highlighted': r.risksHighlighted,
                'created_at': r.createdAt.toIso8601String(),
                'updated_at': r.updatedAt.toIso8601String(),
              })
          .toList(),
    };

    return data;
  }

}
