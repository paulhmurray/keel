/// Which playbook stage a project is "on" right now.
///
/// One rule, used by the Status page, the weekly snapshot, the LLM
/// context and the exports: walk the stages in order and the current
/// one is the first that is not complete — in progress, blocked,
/// pending approval or not yet started all count. When every stage is
/// complete the last stage is reported as current with [allComplete]
/// set. The old logic looked only for in-progress or not-started rows,
/// so a project parked on a blocked stage showed "no playbook attached".
library;

import '../database/database.dart';

class CurrentStage {
  final PlaybookStage stage;

  /// The progress row for [stage]; null when none has been created yet
  /// (treated as not started).
  final ProjectStageProgressesData? progress;
  final int stagesDone;
  final int stagesTotal;
  final bool allComplete;

  const CurrentStage({
    required this.stage,
    required this.progress,
    required this.stagesDone,
    required this.stagesTotal,
    required this.allComplete,
  });

  String get status => progress?.status ?? 'not_started';

  /// "Stage 4: Procurement"
  String get label => 'Stage ${stage.sortOrder + 1}: ${stage.name}';

  /// "Blocked", "In progress", …
  String get statusLabel => playbookStatusLabel(status);

  /// "3 of 5 stages complete"
  String get progressLabel =>
      '$stagesDone of $stagesTotal stage${stagesTotal == 1 ? '' : 's'} complete';
}

String playbookStatusLabel(String status) => switch (status) {
      'complete' => 'Complete',
      'in_progress' => 'In progress',
      'blocked' => 'Blocked',
      'pending_approval' => 'Pending approval',
      _ => 'Not started',
    };

/// Resolves the current stage from a playbook's [stages] and the
/// project's [progresses]. Null only when the playbook has no stages.
CurrentStage? resolveCurrentStage({
  required List<PlaybookStage> stages,
  required List<ProjectStageProgressesData> progresses,
}) {
  if (stages.isEmpty) return null;
  final ordered = [...stages]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final byStage = {for (final p in progresses) p.stageId: p};
  final done = ordered
      .where((s) => byStage[s.id]?.status == 'complete')
      .length;

  for (final s in ordered) {
    final p = byStage[s.id];
    if (p?.status != 'complete') {
      return CurrentStage(
        stage: s,
        progress: p,
        stagesDone: done,
        stagesTotal: ordered.length,
        allComplete: false,
      );
    }
  }
  final last = ordered.last;
  return CurrentStage(
    stage: last,
    progress: byStage[last.id],
    stagesDone: done,
    stagesTotal: ordered.length,
    allComplete: true,
  );
}
