import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
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
  });
}
