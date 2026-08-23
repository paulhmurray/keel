/// Lightweight programme context snapshot — assembled once per session,
/// cached, used by Overview narrative and other Claude-powered features.
class ProgrammeContext {
  final String projectId;
  final String projectName;
  final String? organisationName;

  // Charter
  final String? vision;
  final String? objectives;
  final String? scopeIn;
  final String? deliveryApproach;

  // Current RAG
  final String programmeRag; // green | amber | red | not_started
  final String? previousRag;

  // Playbook
  final String? currentStageName;
  final String? playbookStageStatus;
  final int playbookStagesDone;
  final int playbookStagesTotal;

  // Counts
  final int overdueActionsCount;
  final int openActionsCount;
  final int pendingDecisionsCount;
  final int openRisksCount;
  final int atRiskDependenciesCount;

  // Top items (for narrative generation)
  final List<String> topRiskDescriptions;
  final List<String> pendingDecisionDescriptions;
  final List<String> overdueActionDescriptions;
  final List<String> workstreamSummaries; // "Name: RAG"

  // Finance v1 — the APPROVED budget only. All null/empty when no budget
  // is approved (the prompt section is omitted entirely). Amounts are
  // pre-formatted strings ("A$1,200,000") so no money maths happens
  // outside the integer-minor-unit path.
  final String? approvedBudgetName;
  final String? approvedBudgetTotal;
  final String? budgetApprovalNote; // "approved 12 Jul 2026 by Jane"
  final List<String> budgetFySummaries; // "FY27: A$800,000"
  final List<String> budgetCategorySummaries; // "People: A$500,000"

  // Finance v2 — latest forecast + actuals; null until they exist.
  final String? forecastSummary; // "£44.2M at completion (2026-07, +5.2%)"
  final String? forecastToleranceNote; // "beyond ±5.0% tolerance" | "within..."
  final String? actualsSummary; // "£12.4M actuals to date"

  final DateTime assembledAt;

  const ProgrammeContext({
    required this.projectId,
    required this.projectName,
    this.organisationName,
    this.vision,
    this.objectives,
    this.scopeIn,
    this.deliveryApproach,
    required this.programmeRag,
    this.previousRag,
    this.currentStageName,
    this.playbookStageStatus,
    this.playbookStagesDone = 0,
    this.playbookStagesTotal = 0,
    this.overdueActionsCount = 0,
    this.openActionsCount = 0,
    this.pendingDecisionsCount = 0,
    this.openRisksCount = 0,
    this.atRiskDependenciesCount = 0,
    this.topRiskDescriptions = const [],
    this.pendingDecisionDescriptions = const [],
    this.overdueActionDescriptions = const [],
    this.workstreamSummaries = const [],
    this.approvedBudgetName,
    this.approvedBudgetTotal,
    this.budgetApprovalNote,
    this.budgetFySummaries = const [],
    this.budgetCategorySummaries = const [],
    this.forecastSummary,
    this.forecastToleranceNote,
    this.actualsSummary,
    required this.assembledAt,
  });
}
