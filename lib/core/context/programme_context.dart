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
    required this.assembledAt,
  });
}
