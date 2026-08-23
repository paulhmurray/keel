import '../../shared/utils/money.dart';
import '../database/database.dart';
import '../finance/variance.dart';
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

    // Finance — approved budget + latest forecast/actuals (v2).
    final approvedBudget = await db.financeDao.getApprovedBudget(projectId);
    String? budgetTotal;
    String? approvalNote;
    String? forecastSummary;
    String? forecastToleranceNote;
    String? actualsSummary;
    var fySummaries = const <String>[];
    var categorySummaries = const <String>[];
    if (approvedBudget != null) {
      final totals = await db.financeDao.getTotals(approvedBudget.id);
      final categories = await db.financeDao.getCategories(projectId);
      final catNames = {for (final c in categories) c.id: c.name};
      final cur = approvedBudget.currency;
      budgetTotal = Money.formatMinorCompact(totals.totalMinor, cur);
      final at = approvedBudget.approvedAt;
      approvalNote = [
        if (at != null)
          'approved ${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}',
        if (approvedBudget.approvedBy != null)
          'by ${approvedBudget.approvedBy}',
      ].join(' ');
      final fys = totals.byFinancialYear.keys.toList()..sort();
      fySummaries = [
        for (final fy in fys)
          '$fy: ${Money.formatMinorCompact(totals.byFinancialYear[fy]!, cur)}',
      ];
      categorySummaries = [
        for (final e in totals.byCategoryId.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
          '${catNames[e.key] ?? 'Unknown'}: ${Money.formatMinorCompact(e.value, cur)}',
      ];

      final snapshots = await db.financeDao.getSnapshots(projectId);
      final snapshot =
          snapshots.where((s) => s.status == 'working').firstOrNull ??
              snapshots.firstOrNull;
      if (snapshot != null) {
        final ft = await db.financeDao.getForecastTotals(snapshot.id);
        final bp = VarianceRow.bpOf(
            ft.totalMinor - totals.totalMinor, totals.totalMinor);
        forecastSummary =
            '${Money.formatMinorCompact(ft.totalMinor, cur)} at completion '
            '(${snapshot.period} snapshot, variance ${Money.formatBp(bp)})';
        final tol = approvedBudget.varianceToleranceBp;
        if (bp != null) {
          final tolPct = Money.formatBp(tol).replaceAll('+', '');
          forecastToleranceNote = bp.abs() > tol
              ? 'BEYOND the ±$tolPct tolerance — flagged as a pressure'
              : 'within the ±$tolPct tolerance';
        }
      }
      final actuals = await db.financeDao.getActualsTotals(projectId);
      if (actuals.totalMinor != 0) {
        actualsSummary =
            '${Money.formatMinorCompact(actuals.totalMinor, cur)} actuals '
            'recorded to date';
      }
    }

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
      approvedBudgetName: approvedBudget?.name,
      approvedBudgetTotal: budgetTotal,
      budgetApprovalNote: approvalNote,
      budgetFySummaries: fySummaries,
      budgetCategorySummaries: categorySummaries,
      forecastSummary: forecastSummary,
      forecastToleranceNote: forecastToleranceNote,
      actualsSummary: actualsSummary,
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

    // Omitted entirely when no budget is approved.
    if (ctx.approvedBudgetName != null) {
      sb.writeln('FINANCIAL');
      sb.writeln('  Budget: ${ctx.approvedBudgetName}'
          '${ctx.budgetApprovalNote?.isNotEmpty == true ? ' (${ctx.budgetApprovalNote})' : ''}');
      sb.writeln('  Total: ${ctx.approvedBudgetTotal}');
      if (ctx.budgetFySummaries.isNotEmpty) {
        sb.writeln('  By FY: ${ctx.budgetFySummaries.join(', ')}');
      }
      if (ctx.budgetCategorySummaries.isNotEmpty) {
        sb.writeln(
            '  By category: ${ctx.budgetCategorySummaries.join(', ')}');
      }
      if (ctx.forecastSummary != null) {
        sb.writeln('  Forecast: ${ctx.forecastSummary}'
            '${ctx.forecastToleranceNote != null ? ' — ${ctx.forecastToleranceNote}' : ''}');
      }
      if (ctx.actualsSummary != null) {
        sb.writeln('  Actuals: ${ctx.actualsSummary}');
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
