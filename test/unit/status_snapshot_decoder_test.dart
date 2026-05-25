import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/status/status_snapshot_decoder.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

StatusSnapshot _makeSnapshot({
  String? workstreamHealthJson,
  String? topRisksJson,
  String? upcomingMilestonesJson,
  String? pendingDecisionsJson,
  String? playbookStageJson,
}) {
  return StatusSnapshot(
    id: 's1',
    projectId: 'p1',
    weekEnding: DateTime(2026, 4, 27),
    programmeRag: 'green',
    workstreamRag: '{}',
    overdueActionsCount: 0,
    openActionsCount: 0,
    pendingDecisionsCount: 0,
    openRisksCount: 0,
    createdAt: DateTime(2026, 4, 27),
    narrative: null,
    workstreamHealthJson: workstreamHealthJson,
    topRisksJson: topRisksJson,
    upcomingMilestonesJson: upcomingMilestonesJson,
    pendingDecisionsJson: pendingDecisionsJson,
    playbookStageJson: playbookStageJson,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('workstreams', () {
    test('decodes a list of workstreams with id, name, rag', () {
      final s = _makeSnapshot(
        workstreamHealthJson: jsonEncode([
          {'id': 'wp1', 'name': 'Build', 'rag': 'green'},
          {'id': 'wp2', 'name': 'Migration', 'rag': 'amber'},
        ]),
      );
      final ws = SnapshotDecoder.workstreams(s);
      expect(ws, hasLength(2));
      expect(ws[0].id, 'wp1');
      expect(ws[0].name, 'Build');
      expect(ws[0].rag, 'green');
      expect(ws[1].rag, 'amber');
    });

    test('returns empty list when JSON is null (pre-v19 snapshot)', () {
      final s = _makeSnapshot(workstreamHealthJson: null);
      expect(SnapshotDecoder.workstreams(s), isEmpty);
    });

    test('returns empty list on malformed JSON', () {
      final s = _makeSnapshot(workstreamHealthJson: 'not valid json');
      expect(SnapshotDecoder.workstreams(s), isEmpty);
    });
  });

  group('topRisks', () {
    test('decodes a list of risks with all fields', () {
      final s = _makeSnapshot(
        topRisksJson: jsonEncode([
          {
            'id': 'r1',
            'ref': 'RS01',
            'description': 'data loss',
            'likelihood': 'high',
            'impact': 'high',
          },
        ]),
      );
      final risks = SnapshotDecoder.topRisks(s);
      expect(risks, hasLength(1));
      expect(risks[0].ref, 'RS01');
      expect(risks[0].description, 'data loss');
      expect(risks[0].likelihood, 'high');
    });

    test('handles null ref gracefully', () {
      final s = _makeSnapshot(
        topRisksJson: jsonEncode([
          {
            'id': 'r1',
            'ref': null,
            'description': 'no ref',
            'likelihood': 'low',
            'impact': 'low',
          },
        ]),
      );
      expect(SnapshotDecoder.topRisks(s)[0].ref, isNull);
    });

    test('returns empty list when JSON is null', () {
      expect(SnapshotDecoder.topRisks(_makeSnapshot()), isEmpty);
    });
  });

  group('upcomingMilestones', () {
    test('decodes id, name, owner, monthLabel', () {
      final s = _makeSnapshot(
        upcomingMilestonesJson: jsonEncode([
          {
            'id': 'm1',
            'name': 'Go-live',
            'owner': 'Alice',
            'monthLabel': 'Jul 2026',
          },
        ]),
      );
      final ms = SnapshotDecoder.upcomingMilestones(s);
      expect(ms, hasLength(1));
      expect(ms[0].name, 'Go-live');
      expect(ms[0].owner, 'Alice');
      expect(ms[0].monthLabel, 'Jul 2026');
    });

    test('handles missing optional fields', () {
      final s = _makeSnapshot(
        upcomingMilestonesJson: jsonEncode([
          {'id': 'm1', 'name': 'Go-live', 'owner': null, 'monthLabel': null},
        ]),
      );
      expect(SnapshotDecoder.upcomingMilestones(s)[0].owner, isNull);
    });
  });

  group('pendingDecisions', () {
    test('decodes id, ref, description, dueDate, owner', () {
      final s = _makeSnapshot(
        pendingDecisionsJson: jsonEncode([
          {
            'id': 'd1',
            'ref': 'DC01',
            'description': 'pick auth provider',
            'dueDate': '2026-12-31',
            'owner': 'Sponsor',
          },
        ]),
      );
      final ds = SnapshotDecoder.pendingDecisions(s);
      expect(ds, hasLength(1));
      expect(ds[0].ref, 'DC01');
      expect(ds[0].dueDate, '2026-12-31');
      expect(ds[0].owner, 'Sponsor');
    });
  });

  group('playbookStage', () {
    test('decodes object form', () {
      final s = _makeSnapshot(
        playbookStageJson: jsonEncode({
          'stageId': 'st1',
          'stageName': 'Discovery',
          'status': 'in_progress',
        }),
      );
      final stage = SnapshotDecoder.playbookStage(s);
      expect(stage, isNotNull);
      expect(stage!.stageName, 'Discovery');
      expect(stage.status, 'in_progress');
    });

    test('returns null when no playbook attached', () {
      expect(SnapshotDecoder.playbookStage(_makeSnapshot()), isNull);
    });

    test('returns null on malformed JSON', () {
      final s = _makeSnapshot(playbookStageJson: 'not valid');
      expect(SnapshotDecoder.playbookStage(s), isNull);
    });
  });

  group('robustness', () {
    test('list decoders skip non-map entries', () {
      final s = _makeSnapshot(
        workstreamHealthJson: '[{"id":"wp1","name":"OK","rag":"green"}, "junk", 42]',
      );
      // Junk and 42 are filtered by whereType<Map<String, dynamic>>().
      expect(SnapshotDecoder.workstreams(s), hasLength(1));
    });
  });
}
