import '../database/database.dart';
import '../status/status_calculator.dart' show StatusCalculator, Rag;
import 'programme_context.dart';

/// Assembles ProgrammeContext from live DB data.
/// Caller is responsible for caching if needed.
class ProgrammeContextService {
  final AppDatabase db;

  ProgrammeContextService(this.db);

  Future<ProgrammeContext> getContext(String projectId) async {
    final today = DateTime.now();
    final todayIso =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // Project
    final project = await db.projectDao.getProjectById(projectId);

    // Charter
    final charter = await db.projectCharterDao.getForProject(projectId);

    // Workpackages → compute RAG
    final wps = await db.programmeGanttDao.getWorkPackages(projectId);
    final programmeRag = wps.isEmpty
        ? 'not_started'
        : StatusCalculator.computeProgrammeRag(wps).name;

    // Previous snapshot for trend
    final snapshot = await db.statusSnapshotDao.getMostRecent(projectId);

    // Playbook
    String? stageName;
    String? stageStatus;
    int stagesDone = 0;
    int stagesTotal = 0;
    final pp = await db.playbookDao.getProjectPlaybook(projectId);
    if (pp != null) {
      final progresses = await db.playbookDao
          .getProgressForProjectPlaybook(pp.id);
      stagesTotal = progresses.length;
      stagesDone = progresses.where((p) => p.status == 'complete').length;
      final inProgress = progresses
          .where((p) => p.status == 'in_progress')
          .firstOrNull;
      if (inProgress != null) {
        final stage = await db.playbookDao.getStageById(inProgress.stageId);
        stageName = stage?.name;
        stageStatus = inProgress.status;
      }
    }

    // Actions
    final actions = await db.actionsDao.getActionsForProject(projectId);
    final openActions = actions.where((a) => a.status == 'open').toList();
    final overdueActions = openActions
        .where((a) =>
            a.dueDate != null &&
            a.dueDate!.isNotEmpty &&
            a.dueDate!.compareTo(todayIso) < 0)
        .toList();

    // Decisions
    final decisions =
        await db.decisionsDao.getDecisionsForProject(projectId);
    final pendingDecisions =
        decisions.where((d) => d.status == 'pending').toList();

    // Risks
    final risks = await db.raidDao.getRisksForProject(projectId);
    final openRisks = risks.where((r) => r.status == 'open').toList()
      ..sort((a, b) => _score(b) - _score(a));

    // Dependencies
    final deps = await db.raidDao.getDependenciesForProject(projectId);
    final atRiskDeps =
        deps.where((d) => d.status == 'at_risk').length;

    // Workstream summaries
    final wsSummaries = wps
        .map((wp) => '${wp.name}: ${wp.ragStatus}')
        .toList();

    return ProgrammeContext(
      projectId: projectId,
      projectName: project?.name ?? 'Programme',
      vision: charter?.vision,
      objectives: charter?.objectives,
      scopeIn: charter?.scopeIn,
      deliveryApproach: charter?.deliveryApproach,
      programmeRag: programmeRag,
      previousRag: snapshot?.programmeRag,
      currentStageName: stageName,
      playbookStageStatus: stageStatus,
      playbookStagesDone: stagesDone,
      playbookStagesTotal: stagesTotal,
      overdueActionsCount: overdueActions.length,
      openActionsCount: openActions.length,
      pendingDecisionsCount: pendingDecisions.length,
      openRisksCount: openRisks.length,
      atRiskDependenciesCount: atRiskDeps,
      topRiskDescriptions: openRisks
          .take(3)
          .map((r) =>
              '${r.ref ?? ''} ${r.description} [${r.likelihood}/${r.impact}]'
                  .trim())
          .toList(),
      pendingDecisionDescriptions: pendingDecisions
          .take(3)
          .map((d) =>
              '${d.ref ?? ''} ${d.description}${d.dueDate != null ? ' (due ${d.dueDate})' : ''}'
                  .trim())
          .toList(),
      overdueActionDescriptions: overdueActions
          .take(3)
          .map((a) =>
              '${a.ref ?? ''} ${a.description}${a.owner != null ? ' (${a.owner})' : ''}'
                  .trim())
          .toList(),
      workstreamSummaries: wsSummaries,
      assembledAt: DateTime.now(),
    );
  }

  int _score(dynamic r) {
    int s(String v) {
      switch (v.toLowerCase()) {
        case 'high': return 3;
        case 'medium': return 2;
        default: return 1;
      }
    }
    return s(r.likelihood) * s(r.impact);
  }

  /// Formats context as a structured prompt string.
  String toPromptString(ProgrammeContext ctx) {
    final sb = StringBuffer();
    sb.writeln('PROGRAMME CONTEXT');
    sb.writeln();
    sb.writeln('Project: ${ctx.projectName}');
    sb.writeln('Programme RAG: ${ctx.programmeRag.toUpperCase()}'
        '${ctx.previousRag != null ? ' (was ${ctx.previousRag!.toUpperCase()} last snapshot)' : ''}');
    sb.writeln();

    if (ctx.vision != null && ctx.vision!.isNotEmpty) {
      sb.writeln('CHARTER');
      sb.writeln('Vision: ${ctx.vision}');
      if (ctx.objectives?.isNotEmpty == true)
        sb.writeln('Objectives: ${ctx.objectives}');
      if (ctx.scopeIn?.isNotEmpty == true)
        sb.writeln('Scope: ${ctx.scopeIn}');
      if (ctx.deliveryApproach?.isNotEmpty == true)
        sb.writeln('Delivery approach: ${ctx.deliveryApproach}');
      sb.writeln();
    }

    if (ctx.currentStageName != null) {
      sb.writeln(
          'PLAYBOOK: Stage "${ctx.currentStageName}" (${ctx.playbookStageStatus}) '
          '— ${ctx.playbookStagesDone}/${ctx.playbookStagesTotal} stages complete');
      sb.writeln();
    }

    if (ctx.workstreamSummaries.isNotEmpty) {
      sb.writeln('WORKSTREAMS');
      for (final ws in ctx.workstreamSummaries) {
        sb.writeln('  $ws');
      }
      sb.writeln();
    }

    sb.writeln('COUNTS');
    sb.writeln('  Overdue actions: ${ctx.overdueActionsCount}');
    sb.writeln('  Open actions: ${ctx.openActionsCount}');
    sb.writeln('  Pending decisions: ${ctx.pendingDecisionsCount}');
    sb.writeln('  Open risks: ${ctx.openRisksCount}');
    sb.writeln('  At-risk dependencies: ${ctx.atRiskDependenciesCount}');
    sb.writeln();

    if (ctx.topRiskDescriptions.isNotEmpty) {
      sb.writeln('TOP RISKS');
      for (int i = 0; i < ctx.topRiskDescriptions.length; i++) {
        sb.writeln('  ${i + 1}. ${ctx.topRiskDescriptions[i]}');
      }
      sb.writeln();
    }

    if (ctx.pendingDecisionDescriptions.isNotEmpty) {
      sb.writeln('PENDING DECISIONS');
      for (final d in ctx.pendingDecisionDescriptions) {
        sb.writeln('  - $d');
      }
      sb.writeln();
    }

    if (ctx.overdueActionDescriptions.isNotEmpty) {
      sb.writeln('OVERDUE ACTIONS');
      for (final a in ctx.overdueActionDescriptions) {
        sb.writeln('  - $a');
      }
      sb.writeln();
    }

    sb.writeln('END OF PROGRAMME CONTEXT');
    return sb.toString();
  }
}
