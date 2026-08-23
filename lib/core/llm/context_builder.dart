import 'dart:convert';

import '../database/database.dart';
import '../helm/day_plan_logic.dart';
import '../status/status_calculator.dart';

/// Builds a rich system prompt for the Claude panel, injecting relevant
/// project context so the LLM can give TPM-aware responses.
class ContextBuilder {
  final AppDatabase db;

  ContextBuilder(this.db);

  /// Builds a system prompt for [projectId] including:
  /// 1. Project metadata + programme overview
  /// 2. Workstream statuses
  /// 3. Key people / stakeholders
  /// 4. Top open risks (up to 5)
  /// 5. Pending decisions (up to 5)
  /// 6. Open & overdue actions (up to 8)
  /// 7. Recent context entries (up to 10)
  /// 8. Document summaries (up to 5)
  Future<String> buildSystemPrompt(String projectId) async {
    final buffer = StringBuffer();

    // --- Base persona ---
    buffer.writeln(
        'You are Keel, an expert AI assistant for Technical Programme Managers (TPMs). '
        'You help with programme planning, risk management, decision-making, '
        'stakeholder communication, and delivery governance. '
        'You are precise, concise, and action-oriented. '
        'You use programme management best practices (MSP, PRINCE2, Agile) where relevant.');
    buffer.writeln();

    // --- Project metadata ---
    final project = await db.projectDao.getProjectById(projectId);
    if (project != null) {
      buffer.writeln('## Current Project');
      buffer.writeln('Name: ${project.name}');
      if (project.description != null && project.description!.isNotEmpty) {
        buffer.writeln('Description: ${project.description}');
      }
      if (project.startDate != null && project.startDate!.isNotEmpty) {
        buffer.writeln('Start Date: ${project.startDate}');
      }
      buffer.writeln('Status: ${project.status}');
      buffer.writeln();
    }

    // --- Project charter ---
    final charter = await db.projectCharterDao.getForProject(projectId);
    if (charter != null) {
      buffer.writeln('## Project Charter');
      void charterField(String label, String? v) {
        if (v != null && v.isNotEmpty) buffer.writeln('$label: $v');
      }

      charterField('Vision', charter.vision);
      charterField('Objectives', charter.objectives);
      charterField('In scope', charter.scopeIn);
      charterField('Out of scope', charter.scopeOut);
      charterField('Delivery approach', charter.deliveryApproach);
      charterField('Success criteria', charter.successCriteria);
      charterField('Key constraints', charter.keyConstraints);
      charterField('Assumptions', charter.assumptions);
      buffer.writeln();
    }

    // --- Programme overview ---
    final overview = await db.programmeDao.getOverviewForProject(projectId);
    if (overview != null) {
      buffer.writeln('## Programme Overview');
      if (overview.vision != null && overview.vision!.isNotEmpty) {
        buffer.writeln('Vision: ${overview.vision}');
      }
      if (overview.objectives != null && overview.objectives!.isNotEmpty) {
        buffer.writeln('Objectives: ${overview.objectives}');
      }
      if (overview.scope != null && overview.scope!.isNotEmpty) {
        buffer.writeln('Scope: ${overview.scope}');
      }
      if (overview.sponsor != null && overview.sponsor!.isNotEmpty) {
        buffer.writeln('Sponsor: ${overview.sponsor}');
      }
      if (overview.programmeManager != null &&
          overview.programmeManager!.isNotEmpty) {
        buffer.writeln('Programme Manager: ${overview.programmeManager}');
      }
      buffer.writeln();
    }

    // --- Workstream statuses ---
    final workstreams =
        await db.programmeDao.getWorkstreamsForProject(projectId);
    if (workstreams.isNotEmpty) {
      buffer.writeln('## Workstream Status');
      for (final ws in workstreams) {
        final lead = ws.lead != null && ws.lead!.isNotEmpty
            ? ' (Lead: ${ws.lead})'
            : '';
        final notes = ws.notes != null && ws.notes!.isNotEmpty
            ? ' — ${ws.notes!.length > 100 ? '${ws.notes!.substring(0, 100)}…' : ws.notes}'
            : '';
        buffer.writeln('- ${ws.name} [${ws.status.toUpperCase()}]$lead$notes');
      }
      buffer.writeln();
    }

    // --- Delivery plan (programme Gantt) ---
    final header = await db.programmeGanttDao.getHeader(projectId);
    final wps = await db.programmeGanttDao.getWorkPackages(projectId);
    final planActs =
        await db.programmeGanttDao.getActivitiesForProject(projectId);
    final planDeps = await db.programmeGanttDao.getDependencies(projectId);

    List<String> monthLabels = [];
    if (header?.monthLabels != null) {
      try {
        monthLabels =
            (jsonDecode(header!.monthLabels!) as List).cast<String>();
      } catch (_) {}
    }
    String month(int? idx) => idx == null
        ? '?'
        : (idx >= 0 && idx < monthLabels.length
            ? monthLabels[idx]
            : 'M${idx < 0 ? '?' : idx}');

    if (wps.isNotEmpty) {
      buffer.writeln('## Delivery Plan');
      if (header?.title != null && header!.title!.isNotEmpty) {
        buffer.writeln('Plan: ${header.title}');
      }
      if (monthLabels.isNotEmpty) {
        buffer.writeln(
            'Timeline: ${monthLabels.first} → ${monthLabels.last}');
      }
      if (header?.hardDeadline != null && header!.hardDeadline!.isNotEmpty) {
        buffer.writeln('Hard deadline: ${header.hardDeadline}');
      }

      final actsByWp = <String, List<TimelineActivity>>{};
      for (final a in planActs) {
        actsByWp.putIfAbsent(a.workPackageId, () => []).add(a);
      }
      for (final wp in wps) {
        final code = wp.shortCode != null && wp.shortCode!.isNotEmpty
            ? '[${wp.shortCode}] '
            : '';
        final rag =
            wp.ragStatus.isNotEmpty ? ' [RAG: ${wp.ragStatus}]' : '';
        buffer.writeln('### $code${wp.name}$rag');
        final acts = (actsByWp[wp.id] ?? const [])
          ..sort((a, b) => (a.startMonth ?? 0).compareTo(b.startMonth ?? 0));
        for (final a in acts.take(15)) {
          final kind = switch (a.activityType) {
            'milestone' => '◆ Milestone',
            'gate' => '◈ Gate',
            'hard_deadline' => '⚠ Hard deadline',
            'dependency_marker' => '↳ Dependency',
            'ongoing' => 'Ongoing',
            _ => 'Activity',
          };
          final span = a.endMonth != null && a.endMonth != a.startMonth
              ? '${month(a.startMonth)} → ${month(a.endMonth)}'
              : month(a.startMonth);
          final owner = a.owner != null && a.owner!.isNotEmpty
              ? ' (Owner: ${a.owner})'
              : '';
          final critical = a.isCritical ? ' [CRITICAL PATH]' : '';
          buffer.writeln(
              '- $kind: ${a.name} — $span [${a.status}]$owner$critical');
        }
        if (acts.length > 15) {
          buffer.writeln('- …and ${acts.length - 15} more activities');
        }
      }

      // Dependencies between plan activities.
      if (planDeps.isNotEmpty) {
        final actName = {for (final a in planActs) a.id: a.name};
        buffer.writeln('### Plan Dependencies');
        for (final d in planDeps.take(12)) {
          final from = d.externalLabel?.isNotEmpty ?? false
              ? '${d.externalLabel} (external)'
              : actName[d.fromActivityId] ?? '?';
          final to = actName[d.toActivityId] ?? '?';
          buffer.writeln('- $from → $to (${d.dependencyType})');
        }
        if (planDeps.length > 12) {
          buffer.writeln('- …and ${planDeps.length - 12} more');
        }
      }

      // Milestones due inside the next three months.
      final upcoming = StatusCalculator.upcomingMilestones(
          planActs, monthLabels,
          month0Date: header?.month0Date);
      if (upcoming.isNotEmpty) {
        buffer.writeln('### Upcoming Milestones (next 3 months)');
        for (final m in upcoming) {
          buffer.writeln('- ${m.name} — ${month(m.startMonth)}');
        }
      }
      buffer.writeln();
    }

    // --- Key people & stakeholders ---
    final people = await db.peopleDao.getPersonsForProject(projectId);
    if (people.isNotEmpty) {
      buffer.writeln('## Key People');
      for (final p in people) {
        final role =
            p.role != null && p.role!.isNotEmpty ? ', ${p.role}' : '';
        final org = p.organisation != null && p.organisation!.isNotEmpty
            ? ' (${p.organisation})'
            : '';
        final category = switch (p.personType) {
          'exec' => 'Exec',
          'vendor' => 'Vendor',
          'colleague' => 'Colleague',
          _ => 'Colleague',
        };
        final type = p.isStakeholder ? '$category · Stakeholder' : category;
        buffer.write('- [$type] ${p.name}$role$org');
        if (p.email != null && p.email!.isNotEmpty) {
          buffer.write(' <${p.email}>');
        }
        // Fetch stakeholder profile for influence/stance
        if (p.isStakeholder) {
          final profile =
              await db.peopleDao.getStakeholderByPersonId(p.id);
          if (profile != null) {
            final influence = profile.influence != null &&
                    profile.influence!.isNotEmpty
                ? ' Influence: ${profile.influence}'
                : '';
            final stance =
                profile.stance != null && profile.stance!.isNotEmpty
                    ? ', Stance: ${profile.stance}'
                    : '';
            if (influence.isNotEmpty || stance.isNotEmpty) {
              buffer.write(' [$influence$stance]');
            }
          }
        }
        buffer.writeln();
      }
      buffer.writeln();
    }

    // --- Open risks (up to 5, highest impact first) ---
    final allRisks = await db.raidDao.getRisksForProject(projectId);
    final openRisks = allRisks
        .where((r) => r.status == 'open')
        .toList()
      ..sort((a, b) =>
          _riskScore(b.likelihood, b.impact) -
          _riskScore(a.likelihood, a.impact));
    final topRisks = openRisks.take(5).toList();
    if (topRisks.isNotEmpty) {
      buffer.writeln('## Top Open Risks');
      for (final risk in topRisks) {
        final ref = risk.ref != null ? '[${risk.ref}] ' : '';
        final owner = risk.owner != null && risk.owner!.isNotEmpty
            ? ' (Owner: ${risk.owner})'
            : '';
        buffer.writeln('- $ref${risk.description} '
            '[Likelihood: ${risk.likelihood}, Impact: ${risk.impact}]$owner');
        if (risk.mitigation != null && risk.mitigation!.isNotEmpty) {
          buffer.writeln('  Mitigation: ${risk.mitigation}');
        }
      }
      buffer.writeln();
    }

    // --- Latest status snapshot (programme health) ---
    final snapshot = await db.statusSnapshotDao.getMostRecent(projectId);
    if (snapshot != null) {
      final weekOf =
          snapshot.weekEnding.toIso8601String().substring(0, 10);
      buffer.writeln('## Latest Status Snapshot (week ending $weekOf)');
      buffer.writeln(
          'Programme RAG: ${snapshot.programmeRag.toUpperCase()}');
      buffer.writeln('Open risks: ${snapshot.openRisksCount} · '
          'Open actions: ${snapshot.openActionsCount} '
          '(${snapshot.overdueActionsCount} overdue) · '
          'Pending decisions: ${snapshot.pendingDecisionsCount}');
      final wsHealth = StatusCalculator.parseWorkstreamRag(
          snapshot.workstreamRag);
      if (wsHealth.isNotEmpty) {
        // Resolve WP ids to names where possible.
        final wpName = {for (final wp in wps) wp.id: wp.name};
        final parts = wsHealth.entries
            .map((e) => '${wpName[e.key] ?? e.key}: ${e.value}')
            .join(', ');
        buffer.writeln('Workstream RAG: $parts');
      }
      if (snapshot.narrative != null && snapshot.narrative!.isNotEmpty) {
        buffer.writeln('Narrative: ${snapshot.narrative}');
      }
      buffer.writeln();
    }

    // --- Assumptions (open/validated, up to 5) ---
    final allAssumptions =
        await db.raidDao.getAssumptionsForProject(projectId);
    final liveAssumptions = allAssumptions
        .where((a) => a.status == 'open' || a.status == 'validated')
        .take(5)
        .toList();
    if (liveAssumptions.isNotEmpty) {
      buffer.writeln('## Assumptions');
      for (final a in liveAssumptions) {
        final ref = a.ref != null ? '[${a.ref}] ' : '';
        final owner = a.owner != null && a.owner!.isNotEmpty
            ? ' (Owner: ${a.owner})'
            : '';
        buffer.writeln('- $ref${a.description} [${a.status}]$owner');
      }
      buffer.writeln();
    }

    // --- RAID dependencies (open, up to 6) ---
    final allRaidDeps =
        await db.raidDao.getDependenciesForProject(projectId);
    final openRaidDeps = allRaidDeps
        .where((d) => d.status != 'closed' && d.status != 'resolved')
        .take(6)
        .toList();
    if (openRaidDeps.isNotEmpty) {
      buffer.writeln('## External / Register Dependencies');
      for (final d in openRaidDeps) {
        final ref = d.ref != null ? '[${d.ref}] ' : '';
        final owner = d.owner != null && d.owner!.isNotEmpty
            ? ' (Owner: ${d.owner})'
            : '';
        final due = d.dueDate != null && d.dueDate!.isNotEmpty
            ? ' Due: ${d.dueDate}'
            : '';
        buffer.writeln(
            '- $ref${d.description} [${d.dependencyType}, ${d.status}]$owner$due');
      }
      buffer.writeln();
    }

    // --- Open issues (up to 6, escalation-required and priority first) ---
    final allIssues = await db.raidDao.getIssuesForProject(projectId);
    final openIssues = allIssues
        .where((i) => i.status == 'open' || i.status == 'in progress')
        .toList()
      ..sort((a, b) {
        if (a.escalationRequired != b.escalationRequired) {
          return a.escalationRequired ? -1 : 1;
        }
        return _priorityScore(b.priority) - _priorityScore(a.priority);
      });
    final topIssues = openIssues.take(6).toList();
    if (topIssues.isNotEmpty) {
      buffer.writeln('## Open Issues');
      for (final i in topIssues) {
        final ref = i.ref != null ? '[${i.ref}] ' : '';
        final owner = i.owner != null && i.owner!.isNotEmpty
            ? ' (Owner: ${i.owner})'
            : '';
        final esc = i.escalationRequired ? ' ⚠ ESCALATION REQUIRED' : '';
        buffer.writeln(
            '- $ref${i.title ?? i.description} [${i.priority}]$owner$esc');
        if (i.title != null && i.title!.isNotEmpty) {
          buffer.writeln('  ${i.description}');
        }
        if (i.impactStatement != null && i.impactStatement!.isNotEmpty) {
          buffer.writeln('  Impact if unresolved: ${i.impactStatement}');
        }
      }
      buffer.writeln();
    }

    // --- Pending decisions (up to 5) ---
    final allDecisions =
        await db.decisionsDao.getDecisionsForProject(projectId);
    final pendingDecisions =
        allDecisions.where((d) => d.status == 'pending').take(5).toList();
    if (pendingDecisions.isNotEmpty) {
      buffer.writeln('## Pending Decisions');
      for (final d in pendingDecisions) {
        final ref = d.ref != null ? '[${d.ref}] ' : '';
        final maker = d.decisionMaker != null && d.decisionMaker!.isNotEmpty
            ? ' (Decision Maker: ${d.decisionMaker})'
            : '';
        final due = d.dueDate != null && d.dueDate!.isNotEmpty
            ? ' Due: ${d.dueDate}'
            : '';
        buffer.writeln('- $ref${d.description}$maker$due');
      }
      buffer.writeln();
    }

    // --- Open & overdue actions (up to 8) ---
    final allActions =
        await db.actionsDao.getActionsForProject(projectId);
    final today = DateTime.now();
    final todayIso =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final openActions = allActions
        .where((a) =>
            a.status == 'open' ||
            a.status == 'in progress' ||
            a.status == 'blocked')
        .take(10)
        .toList();
    if (openActions.isNotEmpty) {
      buffer.writeln('## Open Actions');
      for (final a in openActions) {
        final ref = a.ref != null ? '[${a.ref}] ' : '';
        final owner = a.owner != null && a.owner!.isNotEmpty
            ? ' (Owner: ${a.owner})'
            : '';
        final due = a.dueDate != null && a.dueDate!.isNotEmpty
            ? ' Due: ${a.dueDate}'
            : '';
        final overdue = a.dueDate != null &&
                a.dueDate!.isNotEmpty &&
                a.dueDate!.compareTo(todayIso) < 0 &&
                a.status != 'closed'
            ? ' ⚠ OVERDUE'
            : '';
        final state = a.status == 'open' ? '' : ' [${a.status}]';
        buffer.writeln('- $ref${a.description}$state$owner$due$overdue');
      }
      buffer.writeln();
    }

    // --- Today's Helm day plan (global, spans every project) ---
    final dayPlan = await db.dayPlanDao.getPlanForDate(todayIso);
    if (dayPlan != null) {
      final dayBlocks = await db.dayPlanDao.getBlocksForPlan(dayPlan.id);
      final revStarts = parseRevisionStarts(dayPlan.revisionStartsJson);
      final schedule = effectiveSchedule(dayBlocks, revStarts);
      if (schedule.isNotEmpty) {
        buffer.writeln('## Today\'s Plan — Helm ($todayIso)');
        buffer.writeln(
            '(The PM\'s time-blocked plan for today. It is GLOBAL — it '
            'spans all their projects, not just this one.)');
        // Resolve project names once for attribution.
        final planProjectNames = <String, String>{};
        for (final b in schedule) {
          final pid = b.projectId;
          if (pid == null || planProjectNames.containsKey(pid)) continue;
          final p = await db.projectDao.getProjectById(pid);
          if (p != null) planProjectNames[pid] = p.name;
        }
        for (final b in schedule) {
          final projectTag = b.projectId != null &&
                  planProjectNames.containsKey(b.projectId)
              ? ' (Project: ${planProjectNames[b.projectId]})'
              : '';
          final done = b.done ? ' ✓ done' : '';
          buffer.writeln(
              '- ${formatMinute(b.startMinute)}–${formatMinute(b.endMinute)} '
              '[${b.kind}] ${b.label}$projectTag$done');
        }
        if (dayPlan.currentRevision > 0) {
          buffer.writeln(
              'The day has been re-planned ${dayPlan.currentRevision} '
              'time(s) (Cal Newport-style revision columns).');
        }
        buffer.writeln();
      }
    }

    // --- Recent journal entries (up to 5) ---
    final journalEntries =
        await db.journalDao.getEntriesForProject(projectId);
    final recentJournal = journalEntries.take(5).toList();
    if (recentJournal.isNotEmpty) {
      buffer.writeln('## Recent Journal Entries');
      buffer.writeln(
          '(The PM\'s working notes — meetings, observations, running '
          'commentary. Useful context; don\'t quote verbatim in '
          'stakeholder-facing output.)');
      for (final e in recentJournal) {
        final title = e.title != null && e.title!.isNotEmpty
            ? '${e.title} — '
            : '';
        buffer.writeln('### $title${e.entryDate}');
        final preview = e.body.length > 400
            ? '${e.body.substring(0, 400)}…'
            : e.body;
        buffer.writeln(preview);
      }
      buffer.writeln();
    }

    // --- Canvas (strategic thinking) ---
    // This Week: full content. Next 30 Days: top 10 titles. Horizon: top 5
    // titles. This is the PM's private thinking surface so we surface it
    // for narrative-style requests but never for stakeholder docs.
    final canvasCards =
        await db.canvasCardsDao.getCardsForProject(projectId);
    final thisWeek = canvasCards
        .where((c) => c.band == 'this_week')
        .toList();
    final next30 = canvasCards
        .where((c) => c.band == 'next_30_days')
        .toList();
    final horizon = canvasCards
        .where((c) => c.band == 'horizon')
        .toList();
    if (thisWeek.isNotEmpty || next30.isNotEmpty || horizon.isNotEmpty) {
      buffer.writeln('## Canvas — Strategic Thinking');
      buffer.writeln(
          '(The PM\'s private strategic thinking surface. Treat as '
          'context for your responses but never quote verbatim in '
          'stakeholder-facing output.)');
      if (thisWeek.isNotEmpty) {
        buffer.writeln('### This Week');
        for (final c in thisWeek) {
          final linked = c.linkedItemType != null
              ? ' [${c.linkedItemType}]'
              : '';
          buffer.writeln('- ${c.title}$linked');
          if (c.body != null && c.body!.isNotEmpty) {
            final preview = c.body!.length > 240
                ? '${c.body!.substring(0, 240)}…'
                : c.body!;
            buffer.writeln('  $preview');
          }
        }
      }
      if (next30.isNotEmpty) {
        buffer.writeln('### Next 30 Days');
        for (final c in next30.take(10)) {
          buffer.writeln('- ${c.title}');
        }
      }
      if (horizon.isNotEmpty) {
        buffer.writeln('### Horizon');
        for (final c in horizon.take(5)) {
          buffer.writeln('- ${c.title}');
        }
      }
      buffer.writeln();
    }

    // --- Recent context entries (up to 10) ---
    final entries = await db.contextDao.getEntriesForProject(projectId);
    final recentEntries = entries.take(10).toList();
    if (recentEntries.isNotEmpty) {
      buffer.writeln('## Recent Context & Observations');
      for (final e in recentEntries) {
        final typeLabel = _capitalise(e.entryType);
        buffer.writeln('[$typeLabel] ${e.title}');
        if (e.content.isNotEmpty) {
          final preview = e.content.length > 300
              ? '${e.content.substring(0, 300)}…'
              : e.content;
          buffer.writeln('  $preview');
        }
      }
      buffer.writeln();
    }

    // --- Document summaries (up to 5) ---
    final docs = await db.contextDao.getDocumentsForProject(projectId);
    final docsWithContent = docs
        .where((d) => d.content != null && d.content!.isNotEmpty)
        .take(5)
        .toList();
    if (docsWithContent.isNotEmpty) {
      buffer.writeln('## Relevant Documents');
      for (final d in docsWithContent) {
        final typeLabel = d.documentType != null && d.documentType!.isNotEmpty
            ? ' (${d.documentType})'
            : '';
        buffer.writeln('### ${d.title}$typeLabel');
        final summary = _extractSummaryFromTags(d.tags);
        if (summary != null && summary.isNotEmpty) {
          buffer.writeln('Summary: $summary');
        } else if (d.content != null) {
          final preview = d.content!.length > 400
              ? '${d.content!.substring(0, 400)}…'
              : d.content!;
          buffer.writeln(preview);
        }
      }
      buffer.writeln();
    }

    // --- Glossary (up to 15 terms/systems, so acronyms resolve) ---
    final glossary = await db.glossaryDao.getForProject(projectId);
    if (glossary.isNotEmpty) {
      buffer.writeln('## Glossary');
      for (final g in glossary.take(15)) {
        final acronym = g.acronym != null && g.acronym!.isNotEmpty
            ? ' (${g.acronym})'
            : '';
        final desc = g.description != null && g.description!.isNotEmpty
            ? ' — ${g.description}'
            : '';
        buffer.writeln('- ${g.name}$acronym$desc');
      }
      buffer.writeln();
    }

    buffer.writeln(
        'Use the above project context to give relevant, informed responses. '
        'When you are unsure about something, say so. '
        'Keep responses concise and actionable.');

    return buffer.toString();
  }

  int _priorityScore(String p) => switch (p.toLowerCase()) {
        'critical' => 4,
        'high' => 3,
        'medium' => 2,
        _ => 1,
      };

  int _riskScore(String likelihood, String impact) {
    int s(String v) {
      switch (v.toLowerCase()) {
        case 'high':
          return 3;
        case 'medium':
          return 2;
        default:
          return 1;
      }
    }

    return s(likelihood) * s(impact);
  }

  String _capitalise(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  String? _extractSummaryFromTags(String? tags) {
    if (tags == null || tags.isEmpty) return null;
    try {
      final decoded = jsonDecode(tags);
      if (decoded is Map<String, dynamic>) {
        return decoded['summary'] as String?;
      }
    } catch (_) {
      // Not JSON — ignore
    }
    return null;
  }

  /// Returns a summary of what would be injected, as (label, count) pairs.
  Future<List<(String, int)>> buildContextSummary(String projectId) async {
    final sections = <(String, int)>[];

    final project = await db.projectDao.getProjectById(projectId);
    if (project != null) sections.add(('Project: ${project.name}', 0));

    final charter = await db.projectCharterDao.getForProject(projectId);
    if (charter != null) sections.add(('Charter', 0));

    final overview = await db.programmeDao.getOverviewForProject(projectId);
    if (overview != null) sections.add(('Programme overview', 0));

    final snapshot = await db.statusSnapshotDao.getMostRecent(projectId);
    if (snapshot != null) sections.add(('Latest status snapshot', 0));

    final workstreams = await db.programmeDao.getWorkstreamsForProject(projectId);
    if (workstreams.isNotEmpty) sections.add(('Workstreams', workstreams.length));

    final wps = await db.programmeGanttDao.getWorkPackages(projectId);
    if (wps.isNotEmpty) {
      final acts =
          await db.programmeGanttDao.getActivitiesForProject(projectId);
      sections.add(('Delivery plan (${wps.length} WPs)', acts.length));
    }

    final people = await db.peopleDao.getPersonsForProject(projectId);
    if (people.isNotEmpty) sections.add(('People & stakeholders', people.length));

    final allRisks = await db.raidDao.getRisksForProject(projectId);
    final openRisks = allRisks.where((r) => r.status == 'open').length;
    if (openRisks > 0) sections.add(('Open risks (top 5)', openRisks.clamp(0, 5)));

    final allIssues = await db.raidDao.getIssuesForProject(projectId);
    final openIssues = allIssues
        .where((i) => i.status == 'open' || i.status == 'in progress')
        .length;
    if (openIssues > 0) {
      sections.add(('Open issues (top 6)', openIssues.clamp(0, 6)));
    }

    final assumptions = await db.raidDao.getAssumptionsForProject(projectId);
    final liveAssumptions = assumptions
        .where((a) => a.status == 'open' || a.status == 'validated')
        .length;
    if (liveAssumptions > 0) {
      sections.add(('Assumptions', liveAssumptions.clamp(0, 5)));
    }

    final raidDeps = await db.raidDao.getDependenciesForProject(projectId);
    final openDeps = raidDeps
        .where((d) => d.status != 'closed' && d.status != 'resolved')
        .length;
    if (openDeps > 0) {
      sections.add(('Register dependencies', openDeps.clamp(0, 6)));
    }

    final allDecisions = await db.decisionsDao.getDecisionsForProject(projectId);
    final pendingDecisions = allDecisions.where((d) => d.status == 'pending').length;
    if (pendingDecisions > 0) sections.add(('Pending decisions', pendingDecisions.clamp(0, 5)));

    final allActions = await db.actionsDao.getActionsForProject(projectId);
    final openActions = allActions
        .where((a) =>
            a.status == 'open' ||
            a.status == 'in progress' ||
            a.status == 'blocked')
        .length;
    if (openActions > 0) {
      sections.add(('Open actions', openActions.clamp(0, 10)));
    }

    final now = DateTime.now();
    final todayIso =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dayPlan = await db.dayPlanDao.getPlanForDate(todayIso);
    if (dayPlan != null) {
      final dayBlocks = await db.dayPlanDao.getBlocksForPlan(dayPlan.id);
      final schedule = effectiveSchedule(
          dayBlocks, parseRevisionStarts(dayPlan.revisionStartsJson));
      if (schedule.isNotEmpty) {
        sections.add(('Today\'s Helm plan', schedule.length));
      }
    }

    final journal = await db.journalDao.getEntriesForProject(projectId);
    if (journal.isNotEmpty) {
      sections.add(('Journal entries (recent)', journal.length.clamp(0, 5)));
    }

    final glossary = await db.glossaryDao.getForProject(projectId);
    if (glossary.isNotEmpty) {
      sections.add(('Glossary terms', glossary.length.clamp(0, 15)));
    }

    final canvasCards =
        await db.canvasCardsDao.getCardsForProject(projectId);
    if (canvasCards.isNotEmpty) {
      sections.add(('Canvas cards', canvasCards.length));
    }

    final entries = await db.contextDao.getEntriesForProject(projectId);
    if (entries.isNotEmpty) sections.add(('Context entries', entries.length.clamp(0, 10)));

    final docs = await db.contextDao.getDocumentsForProject(projectId);
    final docsWithContent = docs.where((d) => d.content != null && d.content!.isNotEmpty).length;
    if (docsWithContent > 0) sections.add(('Documents', docsWithContent.clamp(0, 5)));

    return sections;
  }
}
