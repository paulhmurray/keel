import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/status/rag_sparkline.dart';
import 'package:keel/shared/theme/keel_colors.dart';

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
  group('sparklineSlice', () {
    test('returns empty when no snapshots', () {
      expect(sparklineSlice(const [], 12), isEmpty);
    });

    test('caps at maxWeeks, taking the most recent', () {
      final snaps = [
        // input is most-recent-first
        _snap('s5', DateTime(2026, 5, 4), 'green'),
        _snap('s4', DateTime(2026, 4, 27), 'amber'),
        _snap('s3', DateTime(2026, 4, 20), 'amber'),
        _snap('s2', DateTime(2026, 4, 13), 'red'),
        _snap('s1', DateTime(2026, 4, 6), 'green'),
      ];
      final sliced = sparklineSlice(snaps, 3);
      expect(sliced, hasLength(3));
      // Output is oldest → newest (left-to-right time order).
      expect(sliced.first.id, 's3');
      expect(sliced.last.id, 's5');
    });

    test('reverses input order (most-recent-first → chronological)', () {
      final snaps = [
        _snap('newer', DateTime(2026, 5, 4), 'green'),
        _snap('older', DateTime(2026, 4, 27), 'red'),
      ];
      final sliced = sparklineSlice(snaps, 12);
      expect(sliced.first.id, 'older');
      expect(sliced.last.id, 'newer');
    });

    test('returns all when fewer than maxWeeks', () {
      final snaps = [
        _snap('s2', DateTime(2026, 5, 4), 'green'),
        _snap('s1', DateTime(2026, 4, 27), 'amber'),
      ];
      expect(sparklineSlice(snaps, 12), hasLength(2));
    });
  });

  group('ragColor', () {
    test('green → phosphor', () {
      expect(ragColor('green'), KColors.phosphor);
    });
    test('amber → amber', () {
      expect(ragColor('amber'), KColors.amber);
    });
    test('red → red', () {
      expect(ragColor('red'), KColors.red);
    });
    test('unknown / not_started → muted text colour', () {
      expect(ragColor('not_started'), KColors.textMuted);
      expect(ragColor('anything-else'), KColors.textMuted);
    });
    test('returned colours are non-null Color objects', () {
      expect(ragColor('green'), isA<Color>());
    });
  });
}
