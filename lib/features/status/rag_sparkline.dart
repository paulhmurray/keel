import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

/// At-a-glance horizontal strip of the last [maxWeeks] programme-RAG values,
/// sourced from [StatusSnapshots]. Most recent on the right.
///
/// Intentionally small and dense — sits inline near the live programme RAG
/// so the trend is visible without navigating to history.
class RagSparkline extends StatelessWidget {
  final String projectId;
  final int maxWeeks;

  const RagSparkline({
    super.key,
    required this.projectId,
    this.maxWeeks = 12,
  });

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<StatusSnapshot>>(
      stream: db.statusSnapshotDao.watchForProject(projectId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 18);
        }
        return _RagSparklineView(
          snapshots: snap.data!,
          maxWeeks: maxWeeks,
        );
      },
    );
  }
}

/// Stateless render of an already-fetched list of snapshots. Pulled out to
/// keep [RagSparkline] thin and to make this part directly testable in
/// widget tests without setting up a database.
class _RagSparklineView extends StatelessWidget {
  final List<StatusSnapshot> snapshots;
  final int maxWeeks;

  const _RagSparklineView({
    required this.snapshots,
    required this.maxWeeks,
  });

  @override
  Widget build(BuildContext context) {
    if (snapshots.length < 2) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          snapshots.isEmpty
              ? 'No snapshots yet — take a snapshot to start tracking trend.'
              : 'Take more snapshots to see RAG trend over time.',
          style: const TextStyle(color: KColors.textMuted, fontSize: 11),
        ),
      );
    }

    // Snapshots come most-recent-first; reverse for left-to-right time order.
    final ordered = sparklineSlice(snapshots, maxWeeks);
    final fmt = DateFormat('MMM d');

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('RAG TREND',
              style: TextStyle(
                color: KColors.textDim,
                fontSize: 10,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(width: 10),
          for (final s in ordered) ...[
            Tooltip(
              message: '${fmt.format(s.weekEnding)} — '
                  '${_ragLabel(s.programmeRag)}',
              child: Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: ragColor(s.programmeRag),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Picks the last [maxWeeks] snapshots in chronological order
/// (oldest left → newest right). Pure function — exposed for testing.
List<StatusSnapshot> sparklineSlice(
    List<StatusSnapshot> mostRecentFirst, int maxWeeks) {
  if (mostRecentFirst.isEmpty) return const [];
  final taken = mostRecentFirst.take(maxWeeks).toList();
  return taken.reversed.toList();
}

/// Maps a RAG string (`green` | `amber` | `red` | other) to its display color.
/// Pure function — exposed for testing.
Color ragColor(String rag) {
  switch (rag) {
    case 'green':
      return KColors.phosphor;
    case 'amber':
      return KColors.amber;
    case 'red':
      return KColors.red;
    default:
      return KColors.textMuted;
  }
}

String _ragLabel(String rag) {
  switch (rag) {
    case 'green':
      return 'Green';
    case 'amber':
      return 'Amber';
    case 'red':
      return 'Red';
    default:
      return 'Not started';
  }
}
