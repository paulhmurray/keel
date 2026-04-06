import 'dart:convert';

import '../database/database.dart';

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
        final type = p.personType == 'colleague' ? 'Colleague' : 'Stakeholder';
        buffer.write('- [$type] ${p.name}$role$org');
        if (p.email != null && p.email!.isNotEmpty) {
          buffer.write(' <${p.email}>');
        }
        // Fetch stakeholder profile for influence/stance
        if (p.personType == 'stakeholder') {
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
        .where((a) => a.status == 'open')
        .take(8)
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
                a.dueDate!.compareTo(todayIso) < 0
            ? ' ⚠ OVERDUE'
            : '';
        buffer.writeln('- $ref${a.description}$owner$due$overdue');
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

    buffer.writeln(
        'Use the above project context to give relevant, informed responses. '
        'When you are unsure about something, say so. '
        'Keep responses concise and actionable.');

    return buffer.toString();
  }

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

    final overview = await db.programmeDao.getOverviewForProject(projectId);
    if (overview != null) sections.add(('Programme overview', 0));

    final workstreams = await db.programmeDao.getWorkstreamsForProject(projectId);
    if (workstreams.isNotEmpty) sections.add(('Workstreams', workstreams.length));

    final people = await db.peopleDao.getPersonsForProject(projectId);
    if (people.isNotEmpty) sections.add(('People & stakeholders', people.length));

    final allRisks = await db.raidDao.getRisksForProject(projectId);
    final openRisks = allRisks.where((r) => r.status == 'open').length;
    if (openRisks > 0) sections.add(('Open risks (top 5)', openRisks.clamp(0, 5)));

    final allDecisions = await db.decisionsDao.getDecisionsForProject(projectId);
    final pendingDecisions = allDecisions.where((d) => d.status == 'pending').length;
    if (pendingDecisions > 0) sections.add(('Pending decisions', pendingDecisions.clamp(0, 5)));

    final allActions = await db.actionsDao.getActionsForProject(projectId);
    final openActions = allActions.where((a) => a.status == 'open').length;
    if (openActions > 0) sections.add(('Open actions', openActions.clamp(0, 8)));

    final entries = await db.contextDao.getEntriesForProject(projectId);
    if (entries.isNotEmpty) sections.add(('Context entries', entries.length.clamp(0, 10)));

    final docs = await db.contextDao.getDocumentsForProject(projectId);
    final docsWithContent = docs.where((d) => d.content != null && d.content!.isNotEmpty).length;
    if (docsWithContent > 0) sections.add(('Documents', docsWithContent.clamp(0, 5)));

    return sections;
  }
}
