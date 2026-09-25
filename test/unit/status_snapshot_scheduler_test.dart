import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/status/status_snapshot_scheduler.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _projectId = 'p-test';

Future<void> _seedProject(AppDatabase db) async {
  await db.into(db.projects).insert(ProjectsCompanion.insert(
        id: _projectId,
        name: 'Test Project',
      ));
}

Future<void> _seedWorkPackage(
  AppDatabase db, {
  required String id,
  required String name,
  required String rag,
}) async {
  await db.into(db.timelineWorkPackages).insert(
        TimelineWorkPackagesCompanion.insert(
          id: id,
          projectId: _projectId,
          name: name,
          ragStatus: Value(rag),
        ),
      );
}

Future<void> _seedRisk(
  AppDatabase db, {
  required String id,
  required String description,
  String likelihood = 'medium',
  String impact = 'medium',
  String status = 'open',
}) async {
  await db.into(db.risks).insert(RisksCompanion.insert(
        id: id,
        projectId: _projectId,
        description: description,
        likelihood: Value(likelihood),
        impact: Value(impact),
        status: Value(status),
      ));
}

Future<void> _seedDecision(
  AppDatabase db, {
  required String id,
  required String description,
  String status = 'pending',
  String? dueDate,
}) async {
  await db.into(db.decisions).insert(DecisionsCompanion.insert(
        id: id,
        projectId: _projectId,
        description: description,
        status: Value(status),
        dueDate: Value(dueDate),
      ));
}

Future<void> _seedAction(
  AppDatabase db, {
  required String id,
  required String description,
  String status = 'open',
  String? dueDate,
}) async {
  await db.into(db.projectActions).insert(ProjectActionsCompanion.insert(
        id: id,
        projectId: _projectId,
        description: description,
        status: Value(status),
        dueDate: Value(dueDate),
      ));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await _seedProject(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('createNow — base fields', () {
    test('writes a snapshot row with the supplied narrative', () async {
      await StatusSnapshotScheduler.createNow(db, _projectId,
          narrative: 'all on track');

      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      expect(snap, isNotNull);
      expect(snap!.narrative, 'all on track');
    });

    test('writes a null narrative when none supplied', () async {
      await StatusSnapshotScheduler.createNow(db, _projectId);

      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      expect(snap!.narrative, isNull);
    });

    test('programmeRag aggregates from work-package RAGs (red wins)',
        () async {
      await _seedWorkPackage(db, id: 'wp1', name: 'Build', rag: 'green');
      await _seedWorkPackage(db, id: 'wp2', name: 'Migration', rag: 'red');

      await StatusSnapshotScheduler.createNow(db, _projectId);

      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      expect(snap!.programmeRag, 'red');
    });

    test('counts overdue, open actions and open risks', () async {
      await _seedAction(db,
          id: 'a1', description: 'overdue', dueDate: '2020-01-01');
      await _seedAction(db, id: 'a2', description: 'no due');
      await _seedAction(db,
          id: 'a3', description: 'closed', status: 'closed');
      await _seedRisk(db, id: 'r1', description: 'live');
      await _seedRisk(db, id: 'r2', description: 'closed', status: 'closed');
      await _seedDecision(db, id: 'd1', description: 'pending one');
      await _seedDecision(db,
          id: 'd2', description: 'approved', status: 'approved');

      await StatusSnapshotScheduler.createNow(db, _projectId);

      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      expect(snap!.overdueActionsCount, 1);
      expect(snap.openActionsCount, 2);
      expect(snap.openRisksCount, 1);
      expect(snap.pendingDecisionsCount, 1);
    });
  });

  group('createNow — rich JSON fields', () {
    test('workstreamHealthJson freezes id, name and rag for each WP',
        () async {
      await _seedWorkPackage(db, id: 'wp1', name: 'Build', rag: 'green');
      await _seedWorkPackage(db, id: 'wp2', name: 'Migration', rag: 'amber');

      await StatusSnapshotScheduler.createNow(db, _projectId);

      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      final decoded = jsonDecode(snap!.workstreamHealthJson!) as List;
      expect(decoded, hasLength(2));
      // Order-insensitive lookup
      final byId = {for (final w in decoded) w['id']: w};
      expect(byId['wp1'], {'id': 'wp1', 'name': 'Build', 'rag': 'green'});
      expect(byId['wp2'],
          {'id': 'wp2', 'name': 'Migration', 'rag': 'amber'});
    });

    test('topRisksJson is capped at 5, ordered by severity, and carries the '
        'fields the report needs', () async {
      await _seedRisk(db,
          id: 'r-fifth',
          description: 'fifth',
          likelihood: 'low',
          impact: 'medium');
      await _seedRisk(db,
          id: 'r-sixth',
          description: 'sixth',
          likelihood: 'rare',
          impact: 'minimal');
      await _seedRisk(db,
          id: 'r-low',
          description: 'low',
          likelihood: 'low',
          impact: 'low');
      await _seedRisk(db,
          id: 'r-high',
          description: 'high',
          likelihood: 'high',
          impact: 'high');
      await _seedRisk(db,
          id: 'r-med',
          description: 'medium',
          likelihood: 'medium',
          impact: 'medium');
      await _seedRisk(db,
          id: 'r-fourth',
          description: 'fourth',
          likelihood: 'medium',
          impact: 'low');

      await StatusSnapshotScheduler.createNow(db, _projectId);

      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      final decoded = jsonDecode(snap!.topRisksJson!) as List;
      expect(decoded, hasLength(5));
      // The high-severity risk should be first.
      expect(decoded.first['id'], 'r-high');
      // The lowest one drops out in favour of the others.
      expect(decoded.map((e) => e['id']), isNot(contains('r-sixth')));
      // Rich fields ride along so later reports can show what changed.
      expect(decoded.first['score'], 16); // legacy high/high → likely/major
      expect(decoded.first['steerco'], isFalse);
      expect(decoded.first['status'], 'open');
      expect(decoded.first.containsKey('strategy'), isTrue);
    });

    test('pendingDecisionsJson includes only pending decisions', () async {
      await _seedDecision(db,
          id: 'd1', description: 'pending', dueDate: '2026-12-31');
      await _seedDecision(db,
          id: 'd2', description: 'done', status: 'approved');

      await StatusSnapshotScheduler.createNow(db, _projectId);

      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      final decoded = jsonDecode(snap!.pendingDecisionsJson!) as List;
      expect(decoded, hasLength(1));
      expect(decoded.first['id'], 'd1');
      expect(decoded.first['description'], 'pending');
    });

    test('upcomingMilestonesJson is empty when no milestones present',
        () async {
      await StatusSnapshotScheduler.createNow(db, _projectId);

      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      expect(jsonDecode(snap!.upcomingMilestonesJson!), isEmpty);
    });

    test('playbookStageJson is null when no playbook attached', () async {
      await StatusSnapshotScheduler.createNow(db, _projectId);

      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      expect(snap!.playbookStageJson, isNull);
    });

    test('playbookStageJson captures a BLOCKED stage as current (used to '
        'report nothing when no stage was in progress or not started)',
        () async {
      await db.playbookDao.upsertOrganisation(const OrganisationsCompanion(
        id: Value('org-1'),
        name: Value('Org'),
      ));
      await db.playbookDao.upsertPlaybook(const PlaybooksCompanion(
        id: Value('pb-1'),
        organisationId: Value('org-1'),
        name: Value('Project Delivery'),
      ));
      for (final (i, name) in ['Lean Canvas', 'CEO Brief', 'Procurement',
        'Business Case'].indexed) {
        await db.playbookDao.upsertStage(PlaybookStagesCompanion(
          id: Value('st-$i'),
          playbookId: const Value('pb-1'),
          name: Value(name),
          sortOrder: Value(i),
        ));
      }
      await db.playbookDao.upsertProjectPlaybook(const ProjectPlaybooksCompanion(
        id: Value('pp-1'),
        projectId: Value(_projectId),
        playbookId: Value('pb-1'),
      ));
      for (final (i, status) in ['complete', 'complete', 'blocked', 'complete']
          .indexed) {
        await db.playbookDao.upsertProgress(ProjectStageProgressesCompanion(
          id: Value('prog-$i'),
          projectPlaybookId: const Value('pp-1'),
          stageId: Value('st-$i'),
          status: Value(status),
        ));
      }

      await StatusSnapshotScheduler.createNow(db, _projectId);
      final snap = await db.statusSnapshotDao.getMostRecent(_projectId);
      final stage = jsonDecode(snap!.playbookStageJson!) as Map<String, dynamic>;
      expect(stage['stageName'], 'Procurement');
      expect(stage['status'], 'blocked');
      expect(stage['stagesDone'], 3);
      expect(stage['stagesTotal'], 4);
    });
  });

  group('maybeCreateSnapshot — idempotency', () {
    test('does not create a duplicate when one already exists for this week',
        () async {
      await StatusSnapshotScheduler.createNow(db, _projectId);
      await StatusSnapshotScheduler.maybeCreateSnapshot(db, _projectId);

      final all = await db.statusSnapshotDao.getForProject(_projectId);
      expect(all, hasLength(1));
    });

    test('createNow always creates a new row (one per call)', () async {
      await StatusSnapshotScheduler.createNow(db, _projectId);
      await StatusSnapshotScheduler.createNow(db, _projectId);

      final all = await db.statusSnapshotDao.getForProject(_projectId);
      expect(all, hasLength(2));
    });
  });
}
