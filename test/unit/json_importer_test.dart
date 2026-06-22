import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/import/json_importer.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _baseExport({
  String projectId = 'p-test',
  String projectName = 'Test Project',
  String status = 'active',
}) {
  final now = DateTime(2025, 3, 28).toIso8601String();
  return {
    'keel_version': '1.0',
    'exported_at': now,
    'project': {
      'id': projectId,
      'name': projectName,
      'description': null,
      'start_date': null,
      'status': status,
      'created_at': now,
      'updated_at': now,
    },
  };
}

Map<String, dynamic> _riskEntry({String id = 'r-1', String ref = 'RS01'}) {
  final now = DateTime(2025, 1, 1).toIso8601String();
  return {
    'id': id,
    'ref': ref,
    'description': 'Data loss risk',
    'likelihood': 'low',
    'impact': 'high',
    'status': 'open',
    'source': 'manual',
    'mitigation': null,
    'owner': null,
    'source_note': null,
    'created_at': now,
    'updated_at': now,
  };
}

Map<String, dynamic> _decisionEntry(
    {String id = 'd-1', String ref = 'DC01', String desc = 'Adopt Dart'}) {
  final now = DateTime(2025, 1, 1).toIso8601String();
  return {
    'id': id,
    'ref': ref,
    'description': desc,
    'status': 'approved',
    'source': 'manual',
    'decision_maker': null,
    'due_date': null,
    'rationale': null,
    'outcome': null,
    'source_note': null,
    'created_at': now,
    'updated_at': now,
  };
}

Map<String, dynamic> _personEntry({String id = 'per-1', String name = 'Alice'}) {
  final now = DateTime(2025, 1, 1).toIso8601String();
  return {
    'id': id,
    'name': name,
    'person_type': 'stakeholder',
    'email': null,
    'role': null,
    'organisation': null,
    'phone': null,
    'teams_handle': null,
    'created_at': now,
    'updated_at': now,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  // --- ImportResult ---

  group('ImportResult', () {
    test('stores all fields correctly', () {
      const result = ImportResult(
        projectName: 'My Project',
        risks: 3,
        assumptions: 2,
        issues: 1,
        dependencies: 4,
        decisions: 5,
        persons: 6,
        actions: 7,
        journalEntries: 8,
        contextEntries: 9,
      );
      expect(result.projectName, 'My Project');
      expect(result.risks, 3);
      expect(result.assumptions, 2);
      expect(result.issues, 1);
      expect(result.dependencies, 4);
      expect(result.decisions, 5);
      expect(result.persons, 6);
      expect(result.actions, 7);
      expect(result.journalEntries, 8);
      expect(result.contextEntries, 9);
    });

    test('zero counts are valid', () {
      const result = ImportResult(
        projectName: 'Empty',
        risks: 0,
        assumptions: 0,
        issues: 0,
        dependencies: 0,
        decisions: 0,
        persons: 0,
        actions: 0,
        journalEntries: 0,
        contextEntries: 0,
      );
      expect(result.risks, 0);
      expect(result.decisions, 0);
    });
  });

  // --- JsonImporter.importFromString ---

  group('JsonImporter.importFromString', () {
    test('imports minimal project and returns project name', () async {
      final result = await JsonImporter.importFromString(
          jsonEncode(_baseExport()), db);
      expect(result.projectName, 'Test Project');
    });

    test('zero entity counts when no sections present', () async {
      final result = await JsonImporter.importFromString(
          jsonEncode(_baseExport(projectId: 'p-empty')), db);
      expect(result.risks, 0);
      expect(result.assumptions, 0);
      expect(result.issues, 0);
      expect(result.dependencies, 0);
      expect(result.decisions, 0);
      expect(result.persons, 0);
      expect(result.actions, 0);
      expect(result.journalEntries, 0);
      expect(result.contextEntries, 0);
    });

    test('counts one imported risk', () async {
      final data = _baseExport(projectId: 'p-risk');
      data['raid'] = {
        'risks': [_riskEntry()],
        'assumptions': [],
        'issues': [],
        'dependencies': [],
      };
      final result =
          await JsonImporter.importFromString(jsonEncode(data), db);
      expect(result.risks, 1);
      expect(result.assumptions, 0);
    });

    test('counts multiple risks', () async {
      final data = _baseExport(projectId: 'p-risks');
      data['raid'] = {
        'risks': [
          _riskEntry(id: 'r-1', ref: 'RS01'),
          _riskEntry(id: 'r-2', ref: 'RS02'),
          _riskEntry(id: 'r-3', ref: 'RS03'),
        ],
        'assumptions': [],
        'issues': [],
        'dependencies': [],
      };
      final result =
          await JsonImporter.importFromString(jsonEncode(data), db);
      expect(result.risks, 3);
    });

    test('counts imported decisions', () async {
      final data = _baseExport(projectId: 'p-dec');
      data['decisions'] = [
        _decisionEntry(id: 'd-1', ref: 'DC01'),
        _decisionEntry(id: 'd-2', ref: 'DC02', desc: 'Use Flutter'),
      ];
      final result =
          await JsonImporter.importFromString(jsonEncode(data), db);
      expect(result.decisions, 2);
    });

    test('counts imported persons', () async {
      final data = _baseExport(projectId: 'p-ppl');
      data['people'] = {
        'persons': [
          _personEntry(id: 'per-1', name: 'Alice'),
          _personEntry(id: 'per-2', name: 'Bob'),
        ],
        'stakeholder_profiles': [],
        'colleague_profiles': [],
      };
      final result =
          await JsonImporter.importFromString(jsonEncode(data), db);
      expect(result.persons, 2);
    });

    test('counts imported actions', () async {
      final now = DateTime(2025, 1, 1).toIso8601String();
      final data = _baseExport(projectId: 'p-act');
      data['actions'] = [
        {
          'id': 'act-1',
          'ref': 'AC01',
          'description': 'Send the report',
          'owner': 'Alice',
          'due_date': '2025-04-01',
          'status': 'open',
          'priority': 'high',
          'source': 'manual',
          'source_note': null,
          'created_at': now,
          'updated_at': now,
        },
      ];
      final result =
          await JsonImporter.importFromString(jsonEncode(data), db);
      expect(result.actions, 1);
    });

    test('counts imported journal entries', () async {
      final now = DateTime(2025, 1, 1).toIso8601String();
      final data = _baseExport(projectId: 'p-journal');
      data['journal'] = {
        'entries': [
          {
            'id': 'je-1',
            'title': 'Day one',
            'body': 'Started the project.',
            'entry_date': '2025-01-01',
            'meeting_context': null,
            'parsed': false,
            'confirmed_at': null,
            'created_at': now,
            'updated_at': now,
          },
        ],
        'links': [],
      };
      final result =
          await JsonImporter.importFromString(jsonEncode(data), db);
      expect(result.journalEntries, 1);
    });

    test('import is idempotent — running twice succeeds without error', () async {
      final json = jsonEncode(_baseExport(
          projectId: 'p-idem', projectName: 'Idempotent Project')
        ..['decisions'] = [_decisionEntry()]);
      await JsonImporter.importFromString(json, db);
      final result = await JsonImporter.importFromString(json, db);
      expect(result.projectName, 'Idempotent Project');
      expect(result.decisions, 1);
    });

    test('idempotent import does not duplicate risks in DB', () async {
      final data = _baseExport(projectId: 'p-dedup');
      data['raid'] = {
        'risks': [_riskEntry(id: 'r-dedup')],
        'assumptions': [],
        'issues': [],
        'dependencies': [],
      };
      final json = jsonEncode(data);
      await JsonImporter.importFromString(json, db);
      await JsonImporter.importFromString(json, db);

      final risks = await db.raidDao.getRisksForProject('p-dedup');
      expect(risks.length, 1);
    });

    test('applies default status when field is missing', () async {
      final data = _baseExport(projectId: 'p-defaults');
      (data['project'] as Map).remove('status');
      // Should not throw — importer applies defaults
      final result =
          await JsonImporter.importFromString(jsonEncode(data), db);
      expect(result.projectName, isNotEmpty);
    });

    test('project is actually persisted in DB', () async {
      final data = _baseExport(
          projectId: 'p-persist', projectName: 'Persisted Project');
      await JsonImporter.importFromString(jsonEncode(data), db);
      final project = await db.projectDao.getProjectById('p-persist');
      expect(project, isNotNull);
      expect(project!.name, 'Persisted Project');
    });

    test('risk is actually persisted in DB', () async {
      final data = _baseExport(projectId: 'p-riskdb');
      data['raid'] = {
        'risks': [_riskEntry(id: 'r-persist', ref: 'RS99')],
        'assumptions': [],
        'issues': [],
        'dependencies': [],
      };
      await JsonImporter.importFromString(jsonEncode(data), db);
      final risks = await db.raidDao.getRisksForProject('p-riskdb');
      expect(risks.length, 1);
      expect(risks.first.ref, 'RS99');
      expect(risks.first.description, 'Data loss risk');
    });

    test('decision is actually persisted in DB', () async {
      final data = _baseExport(projectId: 'p-decdb');
      data['decisions'] = [_decisionEntry(id: 'd-persist', ref: 'DC99')];
      await JsonImporter.importFromString(jsonEncode(data), db);
      final decisions = await db.decisionsDao.getDecisionsForProject('p-decdb');
      expect(decisions.length, 1);
      expect(decisions.first.ref, 'DC99');
    });

    test('import without action_comments key (older export) is graceful',
        () async {
      // Pre-schema-22 export: no action_comments key at all. Should not
      // throw and should leave the comments table untouched.
      final now = DateTime(2025, 1, 1).toIso8601String();
      final data = _baseExport(projectId: 'p-graceful');
      data['actions'] = [
        {
          'id': 'a-graceful',
          'ref': 'AC01',
          'description': 'Legacy action',
          'owner': null,
          'due_date': null,
          'status': 'open',
          'priority': 'medium',
          'source': 'manual',
          'source_note': null,
          'created_at': now,
          'updated_at': now,
        },
      ];
      final result =
          await JsonImporter.importFromString(jsonEncode(data), db);
      expect(result.actions, 1);
      final comments =
          await db.actionCommentsDao.getForAction('a-graceful');
      expect(comments, isEmpty);
    });

    test('action_comments are persisted including the completion flag',
        () async {
      final now = DateTime(2025, 1, 1).toIso8601String();
      final data = _baseExport(projectId: 'p-comments');
      data['actions'] = [
        {
          'id': 'a-c',
          'ref': 'AC02',
          'description': 'Migrate users',
          'owner': null,
          'due_date': null,
          'status': 'closed',
          'priority': 'medium',
          'source': 'manual',
          'source_note': null,
          'created_at': now,
          'updated_at': now,
        },
      ];
      data['action_comments'] = [
        {
          'id': 'c-1',
          'action_id': 'a-c',
          'content': 'Reason it was completed.',
          'is_completion': true,
          'author_name': 'Paul',
          'created_at': now,
          'updated_at': now,
        },
        {
          'id': 'c-2',
          'action_id': 'a-c',
          'content': 'Just a regular note.',
          'is_completion': false,
          'author_name': null,
          'created_at': now,
          'updated_at': now,
        },
      ];
      await JsonImporter.importFromString(jsonEncode(data), db);
      final comments = await db.actionCommentsDao.getForAction('a-c');
      expect(comments.length, 2);
      final completion = comments.firstWhere((c) => c.isCompletion);
      expect(completion.content, 'Reason it was completed.');
      expect(completion.authorName, 'Paul');
      final regular = comments.firstWhere((c) => !c.isCompletion);
      expect(regular.content, 'Just a regular note.');
    });

    test('comments are cleared with their parent action on re-import',
        () async {
      final now = DateTime(2025, 1, 1).toIso8601String();
      final data = _baseExport(projectId: 'p-reimp');
      data['actions'] = [
        {
          'id': 'a-x',
          'ref': 'AC03',
          'description': 'Initial',
          'owner': null,
          'due_date': null,
          'status': 'closed',
          'priority': 'medium',
          'source': 'manual',
          'source_note': null,
          'created_at': now,
          'updated_at': now,
        },
      ];
      data['action_comments'] = [
        {
          'id': 'c-stale',
          'action_id': 'a-x',
          'content': 'Stale',
          'is_completion': false,
          'created_at': now,
          'updated_at': now,
        },
      ];
      await JsonImporter.importFromString(jsonEncode(data), db);
      expect((await db.actionCommentsDao.getForAction('a-x')).length, 1);

      // Re-import the same project with NO comments in the payload.
      // _clearSyncedTables should drop the prior comment so we don't end up
      // with an orphan.
      (data['action_comments'] as List).clear();
      await JsonImporter.importFromString(jsonEncode(data), db);
      expect((await db.actionCommentsDao.getForAction('a-x')).length, 0);
    });
  });

  // --- Escalation / cascade round-trip (export → import) ---
  //
  // Regression guard: a Pull clears + re-imports the project from its
  // exported JSON. Before escalated_at / source_project_id were
  // serialized, that round-trip silently wiped escalation and turned
  // read-only cascaded rows into plain editable ones.

  group('escalation + cascade survive an export→import round-trip', () {
    test('escalatedAt persists on a natively-escalated risk', () async {
      const projectId = 'rt-proj';
      await db.projectDao.insertProject(
          ProjectsCompanion.insert(id: projectId, name: 'Round Trip'));
      final escalatedAt = DateTime(2026, 5, 1, 9, 30);
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'r-esc',
        projectId: projectId,
        ref: const Value('R1'),
        description: 'Escalated risk',
        escalatedAt: Value(escalatedAt),
      ));

      // Export → wipe → import into a fresh DB, exactly like a Pull.
      final jsonStr = await JsonExporter.exportProjectToString(
          projectId: projectId, db: db);
      final fresh = AppDatabase.memory();
      addTearDown(fresh.close);
      await JsonImporter.importFromString(jsonStr, fresh);

      final risk = await fresh.raidDao.getRiskById('r-esc');
      expect(risk, isNotNull);
      expect(risk!.escalatedAt, escalatedAt);
      expect(risk.sourceProjectId, isNull);
    });

    test(
        'a cascaded risk keeps its sourceProjectId (stays read-only, not '
        'demoted to a native row)', () async {
      const programmeId = 'rt-prog';
      await db.projectDao.insertProject(ProjectsCompanion.insert(
        id: programmeId,
        name: 'Programme',
        kind: const Value('programme'),
      ));
      await db.raidDao.upsertRisk(RisksCompanion.insert(
        id: 'cascade:risk:child:r-9',
        projectId: programmeId,
        description: 'Cascaded up from a project',
        source: const Value('cascade'),
        escalatedAt: Value(DateTime(2026, 4, 2)),
        sourceProjectId: const Value('child'),
      ));

      final jsonStr = await JsonExporter.exportProjectToString(
          projectId: programmeId, db: db);
      final fresh = AppDatabase.memory();
      addTearDown(fresh.close);
      await JsonImporter.importFromString(jsonStr, fresh);

      final risk =
          await fresh.raidDao.getRiskById('cascade:risk:child:r-9');
      expect(risk, isNotNull);
      expect(risk!.sourceProjectId, 'child');
      expect(risk.source, 'cascade');
    });

    test('escalatedAt + sourceProjectId round-trip for actions + decisions',
        () async {
      const projectId = 'rt-deliv';
      await db.projectDao.insertProject(
          ProjectsCompanion.insert(id: projectId, name: 'Delivery'));
      final esc = DateTime(2026, 6, 6, 12);
      await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
        id: 'a-esc',
        projectId: projectId,
        description: 'Escalated action',
        escalatedAt: Value(esc),
      ));
      await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
        id: 'd-esc',
        projectId: projectId,
        description: 'Escalated decision',
        escalatedAt: Value(esc),
      ));

      final jsonStr = await JsonExporter.exportProjectToString(
          projectId: projectId, db: db);
      final fresh = AppDatabase.memory();
      addTearDown(fresh.close);
      await JsonImporter.importFromString(jsonStr, fresh);

      final action = await fresh.actionsDao.getActionById('a-esc');
      expect(action!.escalatedAt, esc);
      final decision = await fresh.decisionsDao.getDecisionById('d-esc');
      expect(decision!.escalatedAt, esc);
    });
  });
}
