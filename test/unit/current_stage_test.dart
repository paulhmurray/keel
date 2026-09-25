import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/playbook/current_stage.dart';

PlaybookStage _stage(String id, int order, String name) => PlaybookStage(
      id: id,
      playbookId: 'pb',
      name: name,
      sortOrder: order,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

ProjectStageProgressesData _progress(String stageId, String status) =>
    ProjectStageProgressesData(
      id: 'p-$stageId',
      projectPlaybookId: 'pp',
      stageId: stageId,
      status: status,
      gateMet: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  // The TAC shape that used to show "No playbook attached": four done,
  // one blocked in the middle.
  final stages = [
    _stage('s0', 0, 'Lean Canvas'),
    _stage('s1', 1, 'Pilot'),
    _stage('s2', 2, 'CEO Brief'),
    _stage('s3', 3, 'Procurement'),
    _stage('s4', 4, 'Business Case'),
  ];

  test('a blocked stage is the current stage', () {
    final c = resolveCurrentStage(stages: stages, progresses: [
      _progress('s0', 'complete'),
      _progress('s1', 'complete'),
      _progress('s2', 'complete'),
      _progress('s3', 'blocked'),
      _progress('s4', 'complete'),
    ])!;
    expect(c.stage.name, 'Procurement');
    expect(c.status, 'blocked');
    expect(c.statusLabel, 'Blocked');
    expect(c.label, 'Stage 4: Procurement');
    expect(c.stagesDone, 4);
    expect(c.stagesTotal, 5);
    expect(c.allComplete, isFalse);
    expect(c.progressLabel, '4 of 5 stages complete');
  });

  test('pending approval counts as current too', () {
    final c = resolveCurrentStage(stages: stages, progresses: [
      _progress('s0', 'complete'),
      _progress('s1', 'pending_approval'),
    ])!;
    expect(c.stage.name, 'Pilot');
    expect(c.statusLabel, 'Pending approval');
  });

  test('a stage with no progress row yet is not started and current', () {
    final c = resolveCurrentStage(stages: stages, progresses: [
      _progress('s0', 'complete'),
    ])!;
    expect(c.stage.name, 'Pilot');
    expect(c.progress, isNull);
    expect(c.status, 'not_started');
  });

  test('in-progress beats a later not-started stage', () {
    final c = resolveCurrentStage(stages: stages, progresses: [
      _progress('s0', 'complete'),
      _progress('s1', 'in_progress'),
      _progress('s2', 'not_started'),
    ])!;
    expect(c.stage.name, 'Pilot');
  });

  test('all complete reports the last stage with allComplete', () {
    final c = resolveCurrentStage(
        stages: stages,
        progresses: [for (final s in stages) _progress(s.id, 'complete')])!;
    expect(c.stage.name, 'Business Case');
    expect(c.allComplete, isTrue);
    expect(c.stagesDone, 5);
  });

  test('stages are walked in sort order regardless of list order', () {
    final shuffled = [stages[3], stages[0], stages[4], stages[1], stages[2]];
    final c = resolveCurrentStage(stages: shuffled, progresses: [
      _progress('s0', 'complete'),
      _progress('s1', 'complete'),
    ])!;
    expect(c.stage.name, 'CEO Brief');
  });

  test('no stages → null', () {
    expect(resolveCurrentStage(stages: const [], progresses: const []), isNull);
  });

  test('status labels', () {
    expect(playbookStatusLabel('complete'), 'Complete');
    expect(playbookStatusLabel('in_progress'), 'In progress');
    expect(playbookStatusLabel('blocked'), 'Blocked');
    expect(playbookStatusLabel('pending_approval'), 'Pending approval');
    expect(playbookStatusLabel('anything else'), 'Not started');
  });
}
