import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/status/rag_trend_chart.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

StatusSnapshot _snap(String id, DateTime week, String rag) => StatusSnapshot(
      id: id,
      projectId: 'p1',
      weekEnding: week,
      programmeRag: rag,
      workstreamRag: '{}',
      overdueActionsCount: 0,
      openActionsCount: 0,
      pendingDecisionsCount: 0,
      openRisksCount: 0,
      createdAt: week,
      narrative: null,
      workstreamHealthJson: null,
      topRisksJson: null,
      upcomingMilestonesJson: null,
      pendingDecisionsJson: null,
      playbookStageJson: null,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('summariseTrend', () {
    test('handles empty list', () {
      final s = summariseTrend(const []);
      expect(s.totalWeeks, 0);
      expect(s.currentRag, isNull);
      expect(s.currentStreak, 0);
    });

    test('counts each RAG bucket', () {
      final snaps = [
        _snap('s5', DateTime(2026, 5, 4), 'green'),
        _snap('s4', DateTime(2026, 4, 27), 'amber'),
        _snap('s3', DateTime(2026, 4, 20), 'amber'),
        _snap('s2', DateTime(2026, 4, 13), 'red'),
        _snap('s1', DateTime(2026, 4, 6), 'green'),
      ];
      final s = summariseTrend(snaps);
      expect(s.greenWeeks, 2);
      expect(s.amberWeeks, 2);
      expect(s.redWeeks, 1);
      expect(s.otherWeeks, 0);
      expect(s.totalWeeks, 5);
    });

    test('not_started and unknown values land in otherWeeks', () {
      final snaps = [
        _snap('s2', DateTime(2026, 5, 4), 'not_started'),
        _snap('s1', DateTime(2026, 4, 27), 'unknown_value'),
      ];
      final s = summariseTrend(snaps);
      expect(s.otherWeeks, 2);
      expect(s.greenWeeks, 0);
    });

    test('currentRag is the most recent snapshot value', () {
      final snaps = [
        _snap('newer', DateTime(2026, 5, 4), 'green'),
        _snap('older', DateTime(2026, 4, 27), 'red'),
      ];
      expect(summariseTrend(snaps).currentRag, 'green');
    });

    test('currentStreak counts consecutive matching from the front', () {
      final snaps = [
        // Three greens in a row, then it switches.
        _snap('s5', DateTime(2026, 5, 4), 'green'),
        _snap('s4', DateTime(2026, 4, 27), 'green'),
        _snap('s3', DateTime(2026, 4, 20), 'green'),
        _snap('s2', DateTime(2026, 4, 13), 'amber'),
        _snap('s1', DateTime(2026, 4, 6), 'green'),
      ];
      final s = summariseTrend(snaps);
      expect(s.currentRag, 'green');
      expect(s.currentStreak, 3);
    });

    test('streak of 1 when only the most recent matches', () {
      final snaps = [
        _snap('s2', DateTime(2026, 5, 4), 'amber'),
        _snap('s1', DateTime(2026, 4, 27), 'green'),
      ];
      final s = summariseTrend(snaps);
      expect(s.currentRag, 'amber');
      expect(s.currentStreak, 1);
    });

    test('streak equals total when all snapshots match', () {
      final snaps = [
        _snap('s3', DateTime(2026, 5, 4), 'green'),
        _snap('s2', DateTime(2026, 4, 27), 'green'),
        _snap('s1', DateTime(2026, 4, 20), 'green'),
      ];
      expect(summariseTrend(snaps).currentStreak, 3);
    });
  });
}
