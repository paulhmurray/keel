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
    final workstreamLinks = await db.workstreamsDao.getLinksForProject(projectId);
    final workstreamActivities = await db.workstreamActivitiesDao.getForProject(projectId);
    final governance = await db.programmeDao.getGovernanceForProject(projectId);
    final risks = await db.raidDao.getRisksForProject(projectId);
    final assumptions = await db.raidDao.getAssumptionsForProject(projectId);
    final issues = await db.raidDao.getIssuesForProject(projectId);
    final raidLinks = await db.raidDao.getLinksForProject(projectId);
    final deps = await db.raidDao.getDependenciesForProject(projectId);
    final decisions = await db.decisionsDao.getDecisionsForProject(projectId);
    final persons = await db.peopleDao.getPersonsForProject(projectId);
    final stakeholders = await db.peopleDao.getStakeholdersForProject(projectId);
    final colleagues = await db.peopleDao.getColleaguesForProject(projectId);
    final stakeholderRoles = await db.stakeholderRoleDao.getForProject(projectId);
    final teamRoles = await db.teamRoleDao.getForProject(projectId);
    final milestones = await db.milestonesDao.getForProject(projectId);
    final actionCategories = await db.actionCategoriesDao.getForProject(projectId);
    final actions = await db.actionsDao.getActionsForProject(projectId);
    final actionComments = await db.actionCommentsDao.getForProject(projectId);
    final contextEntries = await db.contextDao.getEntriesForProject(projectId);
    final glossaryEntries = await db.glossaryDao.getForProject(projectId);
    final documents = await db.contextDao.getDocumentsForProject(projectId);
    final reports = await db.reportsDao.getReportsForProject(projectId);
    final statusSnapshots = await db.statusSnapshotDao.getForProject(projectId);
    final charter = await db.projectCharterDao.getForProject(projectId);
    final overviewState = await db.programmeOverviewStateDao.getForProject(projectId);
    final journalEntries = await db.journalDao.getEntriesForProject(projectId);
    final journalSeriesList =
        await db.journalSeriesDao.getForProject(projectId);
    // Timeline / Gantt
    final timelineWorkPackages = await db.programmeGanttDao.getWorkPackages(projectId);
    final timelineActivities = await db.programmeGanttDao.getActivitiesForProject(projectId);
    final timelineDependencies = await db.programmeGanttDao.getDependencies(projectId);
    final programmeHeader = await db.programmeGanttDao.getHeader(projectId);
    final projectScope = await db.programmeGanttDao.getScope(projectId);
    final integrationDomains = await db.programmeGanttDao.getDomains(projectId);
    final prioritisationSources = await db.programmeGanttDao.getSources(projectId);
    // Canvas — cards, their sequencing arrows, and template instances
    // (SWOT, Wardley map, etc.). Private to the project; part of the
    // owner's own cross-machine sync, not the programme cascade.
    final canvasCards = await db.canvasCardsDao.getCardsForProject(projectId);
    final canvasSequences =
        await db.canvasCardsDao.getSequencesForProject(projectId);
    final canvasTemplates =
        await db.canvasTemplatesDao.getTemplatesForProject(projectId);
    // Helm day plans — GLOBAL (the user's day spans every project), so
    // the full set rides in every project's blob. Import is guarded
    // per-day by updatedAt on the importing side.
    final dayPlans = await db.dayPlanDao.getAllPlans();
    final dayPlanBlocks = await db.dayPlanDao.getAllBlocks();
    final weekPlans = await db.weekPlanDao.getAllPlans();
    final weekPlanObjectives = await db.weekPlanDao.getAllObjectives();
    final quarterPlans = await db.quarterPlanDao.getAllPlans();
    final quarterGoals = await db.quarterPlanDao.getAllGoals();
    // Programme links owned by this entity — carries the connection to
    // linked projects/programmes AND the per-link encryption secret, so
    // the owner's portfolio reconnects on a new machine. The secret rides
    // INSIDE this already-E2E-encrypted blob, so the server never sees it.
    final programmeLinks =
        await db.programmeLinksDao.getLinksForEntity(projectId);
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
      // DB schema version of the exporting client. Newer fields gated on this
      // value let older readers ignore data they don't understand.
      'schema_version': 25,
      'exported_at': DateTime.now().toIso8601String(),
      'project': {
        'id': project.id,
        'name': project.name,
        'description': project.description,
        'start_date': project.startDate,
        'status': project.status,
        // Entity type — without this a programme re-imports as a plain
        // project on another machine.
        'kind': project.kind,
        'parent_programme_id': project.parentProgrammeId,
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
        'workstream_links': workstreamLinks
            .map((l) => {
                  'id': l.id,
                  'from_id': l.fromId,
                  'to_id': l.toId,
                  'created_at': l.createdAt.toIso8601String(),
                })
            .toList(),
        'workstream_activities': workstreamActivities
            .map((a) => {
                  'id': a.id,
                  'workstream_id': a.workstreamId,
                  'name': a.name,
                  'start_date': a.startDate,
                  'end_date': a.endDate,
                  'owner_id': a.ownerId,
                  'status': a.status,
                  'notes': a.notes,
                  'sort_order': a.sortOrder,
                  'created_at': a.createdAt.toIso8601String(),
                  'updated_at': a.updatedAt.toIso8601String(),
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
                  'likelihood_rationale': r.likelihoodRationale,
                  'impact_rationale': r.impactRationale,
                  'mitigation': r.mitigation,
                  'owner': r.owner,
                  'status': r.status,
                  'source': r.source,
                  'source_note': r.sourceNote,
                  'escalated_at': r.escalatedAt?.toIso8601String(),
                  'source_project_id': r.sourceProjectId,
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
                  'escalated_at': a.escalatedAt?.toIso8601String(),
                  'source_project_id': a.sourceProjectId,
                  'created_at': a.createdAt.toIso8601String(),
                  'updated_at': a.updatedAt.toIso8601String(),
                })
            .toList(),
        'issues': issues
            .map((i) => {
                  'id': i.id,
                  'ref': i.ref,
                  'title': i.title,
                  'description': i.description,
                  'impact_statement': i.impactStatement,
                  'escalation_required': i.escalationRequired,
                  'owner': i.owner,
                  'due_date': i.dueDate,
                  'priority': i.priority,
                  'status': i.status,
                  'resolution': i.resolution,
                  'source': i.source,
                  'source_note': i.sourceNote,
                  'escalated_at': i.escalatedAt?.toIso8601String(),
                  'source_project_id': i.sourceProjectId,
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
                  'escalated_at': d.escalatedAt?.toIso8601String(),
                  'source_project_id': d.sourceProjectId,
                  'created_at': d.createdAt.toIso8601String(),
                  'updated_at': d.updatedAt.toIso8601String(),
                })
            .toList(),
        'item_links': raidLinks
            .map((l) => {
                  'id': l.id,
                  'from_type': l.fromType,
                  'from_id': l.fromId,
                  'to_type': l.toType,
                  'to_id': l.toId,
                  'created_at': l.createdAt.toIso8601String(),
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
                'escalated_at': d.escalatedAt?.toIso8601String(),
                'source_project_id': d.sourceProjectId,
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
                  'is_stakeholder': p.isStakeholder,
                  'source_project_id': p.sourceProjectId,
                  'source_project_name': p.sourceProjectName,
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
        'stakeholder_roles': stakeholderRoles
            .map((r) => {
                  'id': r.id,
                  'role_name': r.roleName,
                  'role_type': r.roleType,
                  'person_id': r.personId,
                  'is_scaffold': r.isScaffold,
                  'is_applicable': r.isApplicable,
                  'sort_order': r.sortOrder,
                  'notes': r.notes,
                  'functional_area': r.functionalArea,
                  'integration_relevance': r.integrationRelevance,
                  'priority': r.priority,
                  'engagement_status': r.engagementStatus,
                  'gap_flag': r.gapFlag,
                  'gap_description': r.gapDescription,
                  'created_at': r.createdAt.toIso8601String(),
                  'updated_at': r.updatedAt.toIso8601String(),
                })
            .toList(),
        'team_roles': teamRoles
            .map((r) => {
                  'id': r.id,
                  'role_name': r.roleName,
                  'team_group': r.teamGroup,
                  'person_id': r.personId,
                  'is_scaffold': r.isScaffold,
                  'is_applicable': r.isApplicable,
                  'sort_order': r.sortOrder,
                  'notes': r.notes,
                  'created_at': r.createdAt.toIso8601String(),
                  'updated_at': r.updatedAt.toIso8601String(),
                })
            .toList(),
        'milestones': milestones
            .map((m) => {
                  'id': m.id,
                  'name': m.name,
                  'date': m.date,
                  'owner_id': m.ownerId,
                  'status': m.status,
                  'is_hard_deadline': m.isHardDeadline,
                  'notes': m.notes,
                  'workstream_id': m.workstreamId,
                  'created_at': m.createdAt.toIso8601String(),
                  'updated_at': m.updatedAt.toIso8601String(),
                })
            .toList(),
      },
      'action_categories': actionCategories
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'color': c.color,
                'is_preset': c.isPreset,
                'sort_order': c.sortOrder,
              })
          .toList(),
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
                'escalated_at': a.escalatedAt?.toIso8601String(),
                'source_project_id': a.sourceProjectId,
                'outcome': a.outcome,
                'category_id': a.categoryId,
                'recurrence_group_id': a.recurrenceGroupId,
                'linked_action_id': a.linkedActionId,
                'plan_activity_id': a.planActivityId,
                'parent_action_id': a.parentActionId,
                'is_parent': a.isParent,
                'created_at': a.createdAt.toIso8601String(),
                'updated_at': a.updatedAt.toIso8601String(),
              })
          .toList(),
      'action_comments': actionComments
          .map((c) => {
                'id': c.id,
                'action_id': c.actionId,
                'content': c.content,
                'is_completion': c.isCompletion,
                'author_name': c.authorName,
                'created_at': c.createdAt.toIso8601String(),
                'updated_at': c.updatedAt.toIso8601String(),
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
      'glossary': glossaryEntries
          .map((g) => {
                'id': g.id,
                'type': g.type,
                'name': g.name,
                'acronym': g.acronym,
                'description': g.description,
                'owner': g.owner,
                'environment': g.environment,
                'status': g.status,
                'created_at': g.createdAt.toIso8601String(),
                'updated_at': g.updatedAt.toIso8601String(),
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
                  'last_parsed_body': e.lastParsedBody,
                  'confirmed_at': e.confirmedAt?.toIso8601String(),
                  'is_favourite': e.isFavourite,
                  'series_id': e.seriesId,
                  'created_at': e.createdAt.toIso8601String(),
                  'updated_at': e.updatedAt.toIso8601String(),
                })
            .toList(),
        'links': journalLinks,
        'series': journalSeriesList
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'description': s.description,
                  'cadence_hint': s.cadenceHint,
                  'color': s.color,
                  'sort_order': s.sortOrder,
                  'created_at': s.createdAt.toIso8601String(),
                  'updated_at': s.updatedAt.toIso8601String(),
                })
            .toList(),
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
                'source_project_id': r.sourceProjectId,
                'created_at': r.createdAt.toIso8601String(),
                'updated_at': r.updatedAt.toIso8601String(),
              })
          .toList(),
      'status_snapshots': statusSnapshots
          .map((s) => {
                'id': s.id,
                'week_ending': s.weekEnding.toIso8601String(),
                'programme_rag': s.programmeRag,
                'workstream_rag': s.workstreamRag,
                'overdue_actions_count': s.overdueActionsCount,
                'open_actions_count': s.openActionsCount,
                'pending_decisions_count': s.pendingDecisionsCount,
                'open_risks_count': s.openRisksCount,
                'created_at': s.createdAt.toIso8601String(),
              })
          .toList(),
      'charter': charter == null
          ? null
          : {
              'id': charter.id,
              'vision': charter.vision,
              'objectives': charter.objectives,
              'scope_in': charter.scopeIn,
              'scope_out': charter.scopeOut,
              'delivery_approach': charter.deliveryApproach,
              'success_criteria': charter.successCriteria,
              'key_constraints': charter.keyConstraints,
              'assumptions': charter.assumptions,
              'source_project_id': charter.sourceProjectId,
              'source_project_name': charter.sourceProjectName,
              'created_at': charter.createdAt.toIso8601String(),
              'updated_at': charter.updatedAt.toIso8601String(),
            },
      'overview_state': overviewState == null
          ? null
          : {
              'id': overviewState.id,
              'cached_rag': overviewState.cachedRag,
              'cached_narrative': overviewState.cachedNarrative,
              'narrative_generated_at':
                  overviewState.narrativeGeneratedAt?.toIso8601String(),
              'narrative_manual_override': overviewState.narrativeManualOverride,
              'rag_manual_override': overviewState.ragManualOverride,
              'created_at': overviewState.createdAt.toIso8601String(),
              'updated_at': overviewState.updatedAt.toIso8601String(),
            },
      'timeline': {
        'header': programmeHeader == null
            ? null
            : {
                'id': programmeHeader.id,
                'title': programmeHeader.title,
                'subtitle': programmeHeader.subtitle,
                'hard_deadline': programmeHeader.hardDeadline,
                'in_scope': programmeHeader.inScope,
                'out_of_scope': programmeHeader.outOfScope,
                'month_labels': programmeHeader.monthLabels,
                'month0_date': programmeHeader.month0Date,
                'created_at': programmeHeader.createdAt.toIso8601String(),
                'updated_at': programmeHeader.updatedAt.toIso8601String(),
              },
        'scope': projectScope == null
            ? null
            : {
                'id': projectScope.id,
                'in_scope_items': projectScope.inScopeItems,
                'out_of_scope': projectScope.outOfScope,
                'created_at': projectScope.createdAt.toIso8601String(),
                'updated_at': projectScope.updatedAt.toIso8601String(),
              },
        'work_packages': timelineWorkPackages
            .map((wp) => {
                  'id': wp.id,
                  'name': wp.name,
                  'short_code': wp.shortCode,
                  'description': wp.description,
                  'colour_theme': wp.colourTheme,
                  'sort_order': wp.sortOrder,
                  'rag_status': wp.ragStatus,
                  'source_project_id': wp.sourceProjectId,
                  'created_at': wp.createdAt.toIso8601String(),
                  'updated_at': wp.updatedAt.toIso8601String(),
                })
            .toList(),
        'activities': timelineActivities
            .map((a) => {
                  'id': a.id,
                  'work_package_id': a.workPackageId,
                  'name': a.name,
                  'owner': a.owner,
                  'owner_id': a.ownerId,
                  'activity_type': a.activityType,
                  'parent_activity_id': a.parentActivityId,
                  'start_month': a.startMonth,
                  'end_month': a.endMonth,
                  'start_date': a.startDate,
                  'end_date': a.endDate,
                  'likely_month': a.likelyMonth,
                  'safe_month': a.safeMonth,
                  'variance_raid_type': a.varianceRaidType,
                  'variance_raid_id': a.varianceRaidId,
                  'variance_raid_links': a.varianceRaidLinksJson,
                  'status': a.status,
                  'is_critical': a.isCritical,
                  'is_baseline': a.isBaseline,
                  'baseline_start': a.baselineStart,
                  'baseline_end': a.baselineEnd,
                  'cell_label': a.cellLabel,
                  'notes': a.notes,
                  'contributors': a.contributors,
                  'contributor_ids': a.contributorIds,
                  'sort_order': a.sortOrder,
                  'created_at': a.createdAt.toIso8601String(),
                  'updated_at': a.updatedAt.toIso8601String(),
                })
            .toList(),
        'dependencies': timelineDependencies
            .map((d) => {
                  'id': d.id,
                  'from_activity_id': d.fromActivityId,
                  'to_activity_id': d.toActivityId,
                  'dependency_type': d.dependencyType,
                  // Missing until Sep 2026 — its absence made every
                  // sync round-trip strip external deps' labels,
                  // leaving corrupt type='external' label=null rows.
                  'external_label': d.externalLabel,
                  'notes': d.notes,
                  'created_at': d.createdAt.toIso8601String(),
                })
            .toList(),
        'integration_domains': integrationDomains
            .map((d) => {
                  'id': d.id,
                  'priority': d.priority,
                  'domain': d.domain,
                  'likely_systems': d.likelySystems,
                  'priority_signal': d.prioritySignal,
                  'status': d.status,
                  'sort_order': d.sortOrder,
                  'created_at': d.createdAt.toIso8601String(),
                  'updated_at': d.updatedAt.toIso8601String(),
                })
            .toList(),
        'prioritisation_sources': prioritisationSources
            .map((s) => {
                  'id': s.id,
                  'source_name': s.sourceName,
                  'input_type': s.inputType,
                  'owner': s.owner,
                  'mechanism': s.mechanism,
                  'weight': s.weight,
                  'sort_order': s.sortOrder,
                  'created_at': s.createdAt.toIso8601String(),
                  'updated_at': s.updatedAt.toIso8601String(),
                })
            .toList(),
      },
    };

    // Canvas — cards + sequences + template instances.
    data['canvas'] = {
      'cards': canvasCards
          .map((c) => {
                'id': c.id,
                'title': c.title,
                'body': c.body,
                'band': c.band,
                'position_x': c.positionX,
                'position_y': c.positionY,
                'colour': c.colour,
                'size': c.size,
                'start_date': c.startDate,
                'end_date': c.endDate,
                'effort_days': c.effortDays,
                'tags': c.tags,
                'linked_item_type': c.linkedItemType,
                'linked_item_id': c.linkedItemId,
                'promoted_at': c.promotedAt?.toIso8601String(),
                'promoted_to_type': c.promotedToType,
                'promoted_to_id': c.promotedToId,
                'created_at': c.createdAt.toIso8601String(),
                'updated_at': c.updatedAt.toIso8601String(),
              })
          .toList(),
      'sequences': canvasSequences
          .map((s) => {
                'id': s.id,
                'from_card_id': s.fromCardId,
                'to_card_id': s.toCardId,
                'created_at': s.createdAt.toIso8601String(),
              })
          .toList(),
      'templates': canvasTemplates
          .map((t) => {
                'id': t.id,
                'template_type': t.templateType,
                'name': t.name,
                'content': t.content,
                'created_at': t.createdAt.toIso8601String(),
                'updated_at': t.updatedAt.toIso8601String(),
              })
          .toList(),
    };

    // Programme links (connection + encryption secret) owned by this entity.
    data['programme_links'] = programmeLinks
        .map((l) => {
              'id': l.id,
              'owner_entity_id': l.ownerEntityId,
              'owner_kind': l.ownerKind,
              'partner_kind': l.partnerKind,
              'partner_name': l.partnerName,
              'partner_local_id': l.partnerLocalId,
              'code': l.code,
              'link_secret': l.linkSecret,
              'status': l.status,
              'generated_here': l.generatedHere,
              'created_at': l.createdAt.toIso8601String(),
            })
        .toList();

    // Finance — categories, versioned budgets with integer-minor-unit
    // lines, and the audit trail. The audit log travels in the payload
    // so history survives a machine move; import must never re-audit.
    final costCategories = await db.financeDao.getCategories(projectId);
    final budgets = await db.financeDao.getBudgets(projectId);
    final budgetLines = <BudgetLine>[
      for (final b in budgets) ...await db.financeDao.getLines(b.id),
    ];
    final forecastSnapshots = await db.financeDao.getSnapshots(projectId);
    final forecastLines = <ForecastLine>[
      for (final s in forecastSnapshots)
        ...await db.financeDao.getForecastLines(s.id),
    ];
    final actualLines = await db.financeDao.getActuals(projectId);
    final financeAudit = await db.financeDao.getAuditLog(projectId);
    data['finance'] = {
      'cost_categories': costCategories
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'sort_order': c.sortOrder,
                'created_at': c.createdAt.toIso8601String(),
                'updated_at': c.updatedAt.toIso8601String(),
              })
          .toList(),
      'budgets': budgets
          .map((b) => {
                'id': b.id,
                'name': b.name,
                'status': b.status,
                'approved_by': b.approvedBy,
                'approved_at': b.approvedAt?.toIso8601String(),
                'currency': b.currency,
                'funding_source': b.fundingSource,
                'notes': b.notes,
                'variance_tolerance_bp': b.varianceToleranceBp,
                'created_at': b.createdAt.toIso8601String(),
                'updated_at': b.updatedAt.toIso8601String(),
              })
          .toList(),
      'budget_lines': budgetLines
          .map((l) => {
                'id': l.id,
                'budget_id': l.budgetId,
                'cost_category_id': l.costCategoryId,
                'workstream_id': l.workstreamId,
                'financial_year': l.financialYear,
                'amount_minor': l.amountMinor,
                'notes': l.notes,
                'created_at': l.createdAt.toIso8601String(),
                'updated_at': l.updatedAt.toIso8601String(),
              })
          .toList(),
      'forecast_snapshots': forecastSnapshots
          .map((s) => {
                'id': s.id,
                'period': s.period,
                'status': s.status,
                'submitted_at': s.submittedAt?.toIso8601String(),
                'created_at': s.createdAt.toIso8601String(),
                'updated_at': s.updatedAt.toIso8601String(),
              })
          .toList(),
      'forecast_lines': forecastLines
          .map((l) => {
                'id': l.id,
                'snapshot_id': l.snapshotId,
                'cost_category_id': l.costCategoryId,
                'workstream_id': l.workstreamId,
                'financial_year': l.financialYear,
                'amount_minor': l.amountMinor,
                'notes': l.notes,
                'created_at': l.createdAt.toIso8601String(),
                'updated_at': l.updatedAt.toIso8601String(),
              })
          .toList(),
      'actual_lines': actualLines
          .map((l) => {
                'id': l.id,
                'period': l.period,
                'cost_category_id': l.costCategoryId,
                'workstream_id': l.workstreamId,
                'amount_minor': l.amountMinor,
                'source': l.source,
                'source_ref': l.sourceRef,
                'entered_by': l.enteredBy,
                'notes': l.notes,
                'created_at': l.createdAt.toIso8601String(),
                'updated_at': l.updatedAt.toIso8601String(),
              })
          .toList(),
      'audit_log': financeAudit
          .map((a) => {
                'id': a.id,
                'entity_type': a.entityType,
                'entity_id': a.entityId,
                'field': a.field,
                'old_value': a.oldValue,
                'new_value': a.newValue,
                'changed_by': a.changedBy,
                'changed_at': a.changedAt.toIso8601String(),
              })
          .toList(),
    };

    // Helm day plans — see the comment where they're gathered above.
    data['day_plans'] = {
      'plans': dayPlans
          .map((p) => {
                'id': p.id,
                'plan_date': p.planDate,
                'current_revision': p.currentRevision,
                'revision_starts_json': p.revisionStartsJson,
                'created_at': p.createdAt.toIso8601String(),
                'updated_at': p.updatedAt.toIso8601String(),
              })
          .toList(),
      'blocks': dayPlanBlocks
          .map((b) => {
                'id': b.id,
                'day_plan_id': b.dayPlanId,
                'revision': b.revision,
                'start_minute': b.startMinute,
                'end_minute': b.endMinute,
                'kind': b.kind,
                'label': b.label,
                'project_id': b.projectId,
                'linked_action_id': b.linkedActionId,
                'objective_id': b.objectiveId,
                'done': b.done,
                'created_at': b.createdAt.toIso8601String(),
                'updated_at': b.updatedAt.toIso8601String(),
              })
          .toList(),
    };

    // Helm weekly layer — same global ride-in-every-blob rules.
    data['week_plans'] = {
      'plans': weekPlans
          .map((p) => {
                'id': p.id,
                'week_start_date': p.weekStartDate,
                'day_missions_json': p.dayMissionsJson,
                'created_at': p.createdAt.toIso8601String(),
                'updated_at': p.updatedAt.toIso8601String(),
              })
          .toList(),
      'objectives': weekPlanObjectives
          .map((o) => {
                'id': o.id,
                'week_plan_id': o.weekPlanId,
                'sort_order': o.sortOrder,
                'label': o.label,
                'project_id': o.projectId,
                'linked_action_id': o.linkedActionId,
                'goal_id': o.goalId,
                'target_blocks': o.targetBlocks,
                'done': o.done,
                'created_at': o.createdAt.toIso8601String(),
                'updated_at': o.updatedAt.toIso8601String(),
              })
          .toList(),
    };

    // Helm quarterly layer — same global ride-in-every-blob rules.
    data['quarter_plans'] = {
      'plans': quarterPlans
          .map((p) => {
                'id': p.id,
                'quarter_start_date': p.quarterStartDate,
                'month_missions_json': p.monthMissionsJson,
                'created_at': p.createdAt.toIso8601String(),
                'updated_at': p.updatedAt.toIso8601String(),
              })
          .toList(),
      'goals': quarterGoals
          .map((g) => {
                'id': g.id,
                'quarter_plan_id': g.quarterPlanId,
                'sort_order': g.sortOrder,
                'label': g.label,
                'why': g.why,
                'project_id': g.projectId,
                'linked_action_id': g.linkedActionId,
                'target_objectives': g.targetObjectives,
                'done': g.done,
                'created_at': g.createdAt.toIso8601String(),
                'updated_at': g.updatedAt.toIso8601String(),
              })
          .toList(),
    };

    // Playbook — optional; only exported when a playbook is attached
    final projectPlaybook =
        await db.playbookDao.getProjectPlaybook(projectId);
    if (projectPlaybook != null) {
      final playbook =
          await db.playbookDao.getPlaybookById(projectPlaybook.playbookId);
      final org = playbook != null
          ? await db.playbookDao.getOrganisationById(playbook.organisationId)
          : null;
      final stages = playbook != null
          ? await db.playbookDao.getStagesForPlaybook(playbook.id)
          : <PlaybookStage>[];
      final allTemplates = <Map<String, dynamic>>[];
      for (final stage in stages) {
        final templates =
            await db.playbookDao.getTemplatesForStage(stage.id);
        for (final t in templates) {
          allTemplates.add({
            'id': t.id,
            'stage_id': t.stageId,
            'name': t.name,
            'filename': t.filename,
            'file_path': t.filePath,
            'file_type': t.fileType,
            'fill_strategy': t.fillStrategy,
            'field_hints': t.fieldHints,
            'uploaded_at': t.uploadedAt.toIso8601String(),
          });
        }
      }
      final progresses = await db.playbookDao
          .getProgressForProjectPlaybook(projectPlaybook.id);
      data['playbook'] = {
        'organisation': org == null
            ? null
            : {
                'id': org.id,
                'name': org.name,
                'short_name': org.shortName,
                'notes': org.notes,
                'created_at': org.createdAt.toIso8601String(),
                'updated_at': org.updatedAt.toIso8601String(),
              },
        'playbook': playbook == null
            ? null
            : {
                'id': playbook.id,
                'organisation_id': playbook.organisationId,
                'name': playbook.name,
                'description': playbook.description,
                'version': playbook.version,
                'created_at': playbook.createdAt.toIso8601String(),
                'updated_at': playbook.updatedAt.toIso8601String(),
              },
        'stages': stages
            .map((s) => {
                  'id': s.id,
                  'playbook_id': s.playbookId,
                  'name': s.name,
                  'description': s.description,
                  'sort_order': s.sortOrder,
                  'approver_role': s.approverRole,
                  'gate_condition': s.gateCondition,
                  'notes': s.notes,
                  'created_at': s.createdAt.toIso8601String(),
                  'updated_at': s.updatedAt.toIso8601String(),
                })
            .toList(),
        'templates': allTemplates,
        'project_playbook': {
          'id': projectPlaybook.id,
          'project_id': projectPlaybook.projectId,
          'playbook_id': projectPlaybook.playbookId,
          'current_stage_id': projectPlaybook.currentStageId,
          'attached_at': projectPlaybook.attachedAt.toIso8601String(),
        },
        'stage_progresses': progresses
            .map((p) => {
                  'id': p.id,
                  'project_playbook_id': p.projectPlaybookId,
                  'stage_id': p.stageId,
                  'status': p.status,
                  'gate_met': p.gateMet,
                  'approved_by': p.approvedBy,
                  'approved_at': p.approvedAt?.toIso8601String(),
                  'approval_notes': p.approvalNotes,
                  'evidence_filename': p.evidenceFilename,
                  'evidence_file_path': p.evidenceFilePath,
                  'evidence_uploaded_at':
                      p.evidenceUploadedAt?.toIso8601String(),
                  'checklist': p.checklist,
                  'generated_doc_path': p.generatedDocPath,
                  'generated_at': p.generatedAt?.toIso8601String(),
                  'journal_entry_id': p.journalEntryId,
                  'notes': p.notes,
                  'created_at': p.createdAt.toIso8601String(),
                  'updated_at': p.updatedAt.toIso8601String(),
                })
            .toList(),
      };
    }

    return data;
  }

}
