import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import 'rag_sparkline.dart' show ragColor;
import 'rag_trend_chart.dart';
import 'snapshot_detail_view.dart';

/// History view for the Status page. Streams all snapshots for a project
/// and toggles between a list view (with the full RAG trend chart at the
/// top) and a detail view (read-only re-render of a chosen snapshot).
class SnapshotHistoryPanel extends StatefulWidget {
  final String projectId;
  final String projectName;

  const SnapshotHistoryPanel({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  State<SnapshotHistoryPanel> createState() => _SnapshotHistoryPanelState();
}

class _SnapshotHistoryPanelState extends State<SnapshotHistoryPanel> {
  String? _selectedSnapshotId;

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<StatusSnapshot>>(
      stream: db.statusSnapshotDao.watchForProject(widget.projectId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final snapshots = snap.data!;
        if (snapshots.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No snapshots yet. Take one from the live Status view.',
              style: TextStyle(color: KColors.textDim),
            ),
          );
        }

        // Detail mode — selected snapshot is re-rendered.
        if (_selectedSnapshotId != null) {
          final selected = snapshots.firstWhere(
            (s) => s.id == _selectedSnapshotId,
            orElse: () => snapshots.first,
          );
          return SnapshotDetailView(
            snapshot: selected,
            projectName: widget.projectName,
            onBack: () => setState(() => _selectedSnapshotId = null),
          );
        }

        // List mode — chart + list of past snapshots.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RagTrendChart(snapshotsMostRecentFirst: snapshots),
              const SizedBox(height: 20),
              const Text('SNAPSHOTS',
                  style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  itemCount: snapshots.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _SnapshotListTile(
                    snapshot: snapshots[i],
                    onTap: () => setState(
                        () => _selectedSnapshotId = snapshots[i].id),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SnapshotListTile extends StatelessWidget {
  final StatusSnapshot snapshot;
  final VoidCallback onTap;

  const _SnapshotListTile({required this.snapshot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE d MMM yyyy');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KColors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: KColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: ragColor(snapshot.programmeRag),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Week ending ${fmt.format(snapshot.weekEnding)}',
                style:
                    const TextStyle(color: KColors.text, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            _Mini('Open', snapshot.openActionsCount),
            _Mini('Overdue', snapshot.overdueActionsCount),
            _Mini('Risks', snapshot.openRisksCount),
            _Mini('Decisions', snapshot.pendingDecisionsCount),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                size: 16, color: KColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final String label;
  final int value;
  const _Mini(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Text('$value',
              style: const TextStyle(
                  color: KColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          Text(label,
              style: const TextStyle(color: KColors.textDim, fontSize: 9)),
        ],
      ),
    );
  }
}
