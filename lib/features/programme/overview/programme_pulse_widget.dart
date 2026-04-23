import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/status/status_calculator.dart';
import '../../../shared/theme/keel_colors.dart';

class ProgrammePulseWidget extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final List<TimelineWorkPackage> workPackages;
  final StatusSnapshot? lastSnapshot;
  final ProgrammeOverviewState? overviewState;
  final VoidCallback onEditNarrative;

  const ProgrammePulseWidget({
    super.key,
    required this.projectId,
    required this.db,
    required this.workPackages,
    this.lastSnapshot,
    this.overviewState,
    required this.onEditNarrative,
  });

  Rag get _effectiveRag {
    // Manual override takes priority
    final override = overviewState?.ragManualOverride;
    if (override != null) {
      switch (override) {
        case 'green': return Rag.green;
        case 'amber': return Rag.amber;
        case 'red':   return Rag.red;
      }
    }
    return workPackages.isEmpty
        ? Rag.notStarted
        : StatusCalculator.computeProgrammeRag(workPackages);
  }

  RagTrend get _trend {
    if (lastSnapshot == null) return RagTrend.noData;
    Rag? prev;
    switch (lastSnapshot!.programmeRag) {
      case 'green': prev = Rag.green; break;
      case 'amber': prev = Rag.amber; break;
      case 'red':   prev = Rag.red;   break;
    }
    return StatusCalculator.computeTrend(_effectiveRag, prev);
  }

  Color get _ragColor {
    switch (_effectiveRag) {
      case Rag.green:      return const Color(0xFF22c55e);
      case Rag.amber:      return KColors.amber;
      case Rag.red:        return KColors.red;
      case Rag.notStarted: return KColors.textMuted;
    }
  }

  Color get _ragBg {
    switch (_effectiveRag) {
      case Rag.green:      return const Color(0xFF0d3325);
      case Rag.amber:      return KColors.amberDim;
      case Rag.red:        return KColors.redDim;
      case Rag.notStarted: return KColors.surface2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rag = _effectiveRag;
    final trend = _trend;
    final narrative = overviewState?.narrativeManualOverride ??
        overviewState?.cachedNarrative;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // RAG badge
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _ragBg,
              border: Border.all(color: _ragColor, width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                rag.label.toUpperCase(),
                style: TextStyle(
                  color: _ragColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.05,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),

          // Right side
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text(
                    'PROGRAMME RAG',
                    style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.15,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (trend != RagTrend.noData)
                    Text(
                      '${trend.arrow} ${trend.label}',
                      style: const TextStyle(
                          color: KColors.textDim, fontSize: 11),
                    ),
                  if (lastSnapshot != null && trend != RagTrend.noData) ...[
                    const Text('  ·  ',
                        style: TextStyle(
                            color: KColors.border2, fontSize: 11)),
                    Text(
                      'was ${lastSnapshot!.programmeRag}',
                      style: const TextStyle(
                          color: KColors.textMuted, fontSize: 11),
                    ),
                  ],
                ]),
                const SizedBox(height: 8),
                if (narrative != null && narrative.isNotEmpty)
                  Text(
                    narrative,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  )
                else
                  const Text(
                    'No narrative yet. Click "Draft narrative" below to generate one.',
                    style: TextStyle(
                        color: KColors.textMuted, fontSize: 12),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  TextButton.icon(
                    onPressed: onEditNarrative,
                    icon: const Icon(Icons.edit_outlined, size: 13),
                    label: const Text('Edit narrative',
                        style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                        foregroundColor: KColors.textDim),
                  ),
                  const SizedBox(width: 8),
                  _RagOverrideButton(
                    projectId: projectId,
                    db: db,
                    overviewState: overviewState,
                    currentRag: rag,
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RagOverrideButton extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final ProgrammeOverviewState? overviewState;
  final Rag currentRag;

  const _RagOverrideButton({
    required this.projectId,
    required this.db,
    required this.overviewState,
    required this.currentRag,
  });

  Future<void> _setOverride(BuildContext context, String? value) async {
    final id = overviewState?.id ?? const Uuid().v4();
    await db.programmeOverviewStateDao.upsert(
      ProgrammeOverviewStatesCompanion(
        id: Value(id),
        projectId: Value(projectId),
        ragManualOverride: Value(value),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasOverride = overviewState?.ragManualOverride != null;
    return PopupMenuButton<String?>(
      color: KColors.surface2,
      tooltip: 'Override RAG',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: KColors.border2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          hasOverride ? 'RAG: manual' : 'Override RAG',
          style: const TextStyle(
              color: KColors.textDim, fontSize: 11),
        ),
      ),
      onSelected: (v) => _setOverride(context, v),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'green',
          child: Text('Force Green',
              style: TextStyle(
                  color: Color(0xFF22c55e), fontSize: 12)),
        ),
        const PopupMenuItem(
          value: 'amber',
          child: Text('Force Amber',
              style: TextStyle(color: KColors.amber, fontSize: 12)),
        ),
        const PopupMenuItem(
          value: 'red',
          child: Text('Force Red',
              style: TextStyle(color: KColors.red, fontSize: 12)),
        ),
        if (hasOverride)
          const PopupMenuItem(
            value: null,
            child: Text('Clear override',
                style: TextStyle(
                    color: KColors.textDim, fontSize: 12)),
          ),
      ],
    );
  }
}
