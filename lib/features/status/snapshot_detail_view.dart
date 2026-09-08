import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/database/database.dart';
import '../../core/status/status_snapshot_decoder.dart';
import '../../shared/theme/keel_colors.dart';
import 'rag_sparkline.dart' show ragColor;

/// Read-only re-render of the Status dashboard for a single past snapshot.
///
/// The widgets here are deliberately *not* the same as the live ones — those
/// expect rich domain types (TimelineWorkPackage, Risk, Decision) and have
/// affordances (sorting, links, edits) that don't make sense for a frozen
/// historical view. This is a compact, read-only restatement.
class SnapshotDetailView extends StatelessWidget {
  final StatusSnapshot snapshot;
  final String projectName;
  final VoidCallback onBack;

  const SnapshotDetailView({
    super.key,
    required this.snapshot,
    required this.projectName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE d MMM yyyy');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner: which week + back ────────────────────────────────────
          Row(children: [
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Back to history'),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: KColors.amberDim,
                  borderRadius: BorderRadius.circular(3),
                  border:
                      Border.all(color: KColors.amber.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Snapshot — week ending ${fmt.format(snapshot.weekEnding)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: KColors.amber, fontSize: 11),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('PROGRAMME RAG'),
                  _RagBadge(rag: snapshot.programmeRag),
                  const SizedBox(height: 18),

                  _SectionLabel('WORKSTREAMS'),
                  _WorkstreamsList(snapshot: snapshot),
                  const SizedBox(height: 18),

                  _SectionLabel('NARRATIVE'),
                  _NarrativeBlock(narrative: snapshot.narrative),
                  const SizedBox(height: 18),

                  _SectionLabel('UPCOMING MILESTONES (CAPTURED AT THE TIME)'),
                  _MilestonesList(snapshot: snapshot),
                  const SizedBox(height: 18),

                  _SectionLabel('TOP RISKS'),
                  _RisksList(snapshot: snapshot),
                  const SizedBox(height: 18),

                  _SectionLabel('PENDING DECISIONS'),
                  _DecisionsList(snapshot: snapshot),
                  const SizedBox(height: 18),

                  _SectionLabel('PLAYBOOK STAGE'),
                  _PlaybookStageBlock(snapshot: snapshot),
                  const SizedBox(height: 18),

                  _SectionLabel('COUNTS'),
                  _CountsRow(snapshot: snapshot),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── small read-only widgets ────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: KColors.textDim,
          fontSize: 11,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RagBadge extends StatelessWidget {
  final String rag;
  const _RagBadge({required this.rag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ragColor(rag).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        rag.toUpperCase(),
        style: TextStyle(
            color: ragColor(rag), fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

class _WorkstreamsList extends StatelessWidget {
  final StatusSnapshot snapshot;
  const _WorkstreamsList({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final wss = SnapshotDecoder.workstreams(snapshot);
    if (wss.isEmpty) {
      return const Text('(no workstream data captured)',
          style: TextStyle(color: KColors.textMuted, fontSize: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final ws in wss)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: ragColor(ws.rag),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(ws.name,
                  style: const TextStyle(color: KColors.text, fontSize: 13)),
              const SizedBox(width: 8),
              Text('(${ws.rag})',
                  style: const TextStyle(
                      color: KColors.textMuted, fontSize: 11)),
            ]),
          ),
      ],
    );
  }
}

class _NarrativeBlock extends StatelessWidget {
  final String? narrative;
  const _NarrativeBlock({required this.narrative});

  @override
  Widget build(BuildContext context) {
    final n = narrative;
    if (n == null || n.isEmpty) {
      return const Text('(no narrative captured)',
          style: TextStyle(color: KColors.textMuted, fontSize: 12));
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(n,
          style: const TextStyle(
              color: KColors.text, fontSize: 13, height: 1.5)),
    );
  }
}

class _MilestonesList extends StatelessWidget {
  final StatusSnapshot snapshot;
  const _MilestonesList({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final ms = SnapshotDecoder.upcomingMilestones(snapshot);
    if (ms.isEmpty) {
      return const Text('(none)',
          style: TextStyle(color: KColors.textMuted, fontSize: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in ms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${m.name}'
              '${m.monthLabel != null ? "  ·  ${m.monthLabel}" : ""}'
              '${m.owner != null ? "  ·  ${m.owner}" : ""}',
              style: const TextStyle(color: KColors.text, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _RisksList extends StatelessWidget {
  final StatusSnapshot snapshot;
  const _RisksList({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final rs = SnapshotDecoder.topRisks(snapshot);
    if (rs.isEmpty) {
      return const Text('(none)',
          style: TextStyle(color: KColors.textMuted, fontSize: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${r.ref ?? "—"}  ${r.description}  '
              '[${r.likelihood}/${r.impact}]',
              style: const TextStyle(color: KColors.text, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _DecisionsList extends StatelessWidget {
  final StatusSnapshot snapshot;
  const _DecisionsList({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final ds = SnapshotDecoder.pendingDecisions(snapshot);
    if (ds.isEmpty) {
      return const Text('(none)',
          style: TextStyle(color: KColors.textMuted, fontSize: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in ds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '• ${d.ref ?? "—"}  ${d.description}'
              '${d.dueDate != null ? "  ·  due ${d.dueDate}" : ""}'
              '${d.owner != null ? "  ·  ${d.owner}" : ""}',
              style: const TextStyle(color: KColors.text, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _PlaybookStageBlock extends StatelessWidget {
  final StatusSnapshot snapshot;
  const _PlaybookStageBlock({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final stage = SnapshotDecoder.playbookStage(snapshot);
    if (stage == null) {
      return const Text('(no playbook attached)',
          style: TextStyle(color: KColors.textMuted, fontSize: 12));
    }
    return Text(
      '${stage.stageName}  ·  ${stage.status}',
      style: const TextStyle(color: KColors.text, fontSize: 13),
    );
  }
}

class _CountsRow extends StatelessWidget {
  final StatusSnapshot snapshot;
  const _CountsRow({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _CountTile('Open actions', snapshot.openActionsCount),
        _CountTile('Overdue', snapshot.overdueActionsCount),
        _CountTile('Pending decisions', snapshot.pendingDecisionsCount),
        _CountTile('Open risks', snapshot.openRisksCount),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final int value;
  const _CountTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: KColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: KColors.textDim, fontSize: 10)),
          const SizedBox(height: 2),
          Text('$value',
              style: const TextStyle(
                  color: KColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
