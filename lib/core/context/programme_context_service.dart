import '../../shared/utils/money.dart';
import '../raid/risk_rating.dart';
import '../database/database.dart';
import '../playbook/current_stage.dart';
import '../finance/contingency_ledger.dart';
import '../finance/programme_rollup.dart';
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
      final stages =
          await db.playbookDao.getStagesForPlaybook(pp.playbookId);
      final progresses = await db.playbookDao
          .getProgressForProjectPlaybook(pp.id);
      final current =
          resolveCurrentStage(stages: stages, progresses: progresses);
      if (current != null) {
        stagesTotal = current.stagesTotal;
        stagesDone = current.stagesDone;
        stageName = current.stage.name;
        stageStatus = current.allComplete ? 'complete' : current.status;
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

    // Portfolio finance — what the linked projects have cascaded up.
    final portfolioLines = <String>[];
    final cascadedBudgets = await db.financeDao.getCascadedBudgets(projectId);
    if (cascadedBudgets.isNotEmpty) {
      final f = computeProgrammeFinance(
        categories: await db.financeDao.getCascadedCategories(projectId),
        budgets: cascadedBudgets,
        budgetLines: await db.financeDao.getCascadedBudgetLines(projectId),
        snapshots: await db.financeDao.getCascadedSnapshots(projectId),
        forecastLines: await db.financeDao.getCascadedForecastLines(projectId),
        actuals: await db.financeDao.getCascadedActuals(projectId),
        merges: await db.financeDao.getMerges(projectId),
      );
      final cur = f.currency ?? 'AUD';
      portfolioLines.add(
          '${f.projects.length} linked projects: budget '
          '${Money.formatMinorCompact(f.budgetMinor, cur)}, forecast '
          '${Money.formatMinorCompact(f.forecastMinor, cur)} '
          '(${Money.formatBp(f.varianceBp)}), actuals '
          '${Money.formatMinorCompact(f.actualsMinor, cur)}; '
          '${f.breaches.length} beyond tolerance');
      for (final r in f.projects) {
        final p = await db.projectDao.getProjectById(r.sourceId);
        final c = r.currency ?? cur;
        portfolioLines.add(
            '${p?.name ?? 'Linked project'}: budget '
            '${Money.formatMinorCompact(r.budgetMinor, c)}, '
            '${r.forecastMinor == null ? 'no forecast submitted' : 'forecast ${Money.formatMinorCompact(r.forecastMinor, c)} (${Money.formatBp(r.varianceBp)}${r.breach ? ', BEYOND tolerance' : ''})'}'
            ', actuals ${Money.formatMinorCompact(r.actualsMinor, c)}');
      }
    }

    final funding = await db.financeDao.getFunding(projectId);
    if (funding.isNotEmpty) {
      final l = computeLedger(
          approvals: funding,
          movements: await db.financeDao.getMovements(projectId));
      final warnBp = (await db.financeDao.getFinanceSettings(projectId))
              ?.contingencyWarnBp ??
          2000;
      final cur = l.currency ?? 'AUD';
      portfolioLines.add(
          'Envelope: funding ${Money.formatMinorCompact(l.fundingMinor, cur)}, '
          'allocated ${Money.formatMinorCompact(l.allocatedMinor, cur)}, '
          'contingency balance ${Money.formatMinorCompact(l.balanceMinor, cur)} '
          '(${Money.formatBp(l.balanceBp).replaceAll('+', '')} of funding'
          '${l.belowThreshold(warnBp) ? ', BELOW the ${Money.formatBp(warnBp).replaceAll('+', '')} threshold' : ''}); '
          '${Money.formatMinorCompact(l.drawnMinor, cur)} drawn, '
          '${Money.formatMinorCompact(l.returnedMinor, cur)} returned');
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
      portfolioFinanceLines: portfolioLines,
      isProgramme: project?.kind == 'programme',
      assembledAt: DateTime.now(),
    );
  }

  int _score(dynamic r) {
    return riskScore(r.likelihood, r.impact);
  }

  /// Formats context as a structured prompt string.
  String toPromptString(ProgrammeContext ctx) {
    final sb = StringBuffer();
    final entity = ctx.isProgramme ? 'Programme' : 'Project';
    sb.writeln('${entity.toUpperCase()} CONTEXT');
    sb.writeln('This is a ${entity.toLowerCase()}. Refer to it as '
        '"the ${entity.toLowerCase()}"'
        '${ctx.isProgramme ? '' : '; "programme" means only the wider '
            'programme it reports into'}.');
    sb.writeln();
    sb.writeln('$entity: ${ctx.projectName}');
    sb.writeln('Overall RAG: ${ctx.programmeRag.toUpperCase()}'
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

    if (ctx.portfolioFinanceLines.isNotEmpty) {
      sb.writeln('PORTFOLIO FINANCE (linked projects)');
      for (final l in ctx.portfolioFinanceLines) {
        sb.writeln('  $l');
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
