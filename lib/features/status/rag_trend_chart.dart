import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import 'rag_sparkline.dart' show ragColor;

/// Aggregate stats summarising a series of snapshots' RAG values.
/// Pure value object, exposed for testing.
class RagTrendStats {
  final int greenWeeks;
  final int amberWeeks;
  final int redWeeks;
  final int otherWeeks;
  // Most recent RAG value, or null if no snapshots.
  final String? currentRag;
  // Number of consecutive most-recent snapshots at [currentRag], inclusive.
  final int currentStreak;

  const RagTrendStats({
    required this.greenWeeks,
    required this.amberWeeks,
    required this.redWeeks,
    required this.otherWeeks,
    required this.currentRag,
    required this.currentStreak,
  });

  int get totalWeeks => greenWeeks + amberWeeks + redWeeks + otherWeeks;
}

/// Computes [RagTrendStats] from a list of snapshots ordered most-recent-first.
/// Pure function — exposed for testing.
RagTrendStats summariseTrend(List<StatusSnapshot> mostRecentFirst) {
  if (mostRecentFirst.isEmpty) {
    return const RagTrendStats(
      greenWeeks: 0,
      amberWeeks: 0,
      redWeeks: 0,
      otherWeeks: 0,
      currentRag: null,
      currentStreak: 0,
    );
  }

  var green = 0, amber = 0, red = 0, other = 0;
  for (final s in mostRecentFirst) {
    switch (s.programmeRag) {
      case 'green':
        green++;
      case 'amber':
        amber++;
      case 'red':
        red++;
      default:
        other++;
    }
  }

  final current = mostRecentFirst.first.programmeRag;
  var streak = 0;
  for (final s in mostRecentFirst) {
    if (s.programmeRag != current) break;
    streak++;
  }

  return RagTrendStats(
    greenWeeks: green,
    amberWeeks: amber,
    redWeeks: red,
    otherWeeks: other,
    currentRag: current,
    currentStreak: streak,
  );
}

/// Full RAG trend chart: a horizontally-scrollable timeline of every
/// captured snapshot, plus a summary header with weeks-at-each-RAG counts
/// and the current-RAG streak. Used inside the History view.
class RagTrendChart extends StatelessWidget {
  final List<StatusSnapshot> snapshotsMostRecentFirst;

  const RagTrendChart({
    super.key,
    required this.snapshotsMostRecentFirst,
  });

  @override
  Widget build(BuildContext context) {
    final stats = summariseTrend(snapshotsMostRecentFirst);
    final fmt = DateFormat('MMM d');
    // Render oldest → newest left-to-right; matches sparkline's convention.
    final chronological = snapshotsMostRecentFirst.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary stats row
        Row(children: [
          _StatPill('${stats.greenWeeks}w', 'green', KColors.phosphor),
          const SizedBox(width: 6),
          _StatPill('${stats.amberWeeks}w', 'amber', KColors.amber),
          const SizedBox(width: 6),
          _StatPill('${stats.redWeeks}w', 'red', KColors.red),
          const SizedBox(width: 16),
          if (stats.currentRag != null)
            Text(
              'Currently ${stats.currentRag!.toUpperCase()} '
              'for ${stats.currentStreak} '
              'week${stats.currentStreak == 1 ? "" : "s"}',
              style: const TextStyle(
                  color: KColors.textDim, fontSize: 12),
            ),
        ]),
        const SizedBox(height: 12),

        // Horizontal timeline
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final s in chronological)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  children: [
                    Tooltip(
                      message: '${fmt.format(s.weekEnding)} — '
                          '${s.programmeRag}',
                      child: Container(
                        width: 22,
                        height: 32,
                        decoration: BoxDecoration(
                          color: ragColor(s.programmeRag),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fmt.format(s.weekEnding),
                      style: const TextStyle(
                          color: KColors.textMuted, fontSize: 9),
                    ),
                  ],
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatPill(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}
