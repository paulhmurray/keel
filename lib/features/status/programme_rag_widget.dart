import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../core/status/status_calculator.dart';
import '../../shared/theme/keel_colors.dart';

class ProgrammeRagWidget extends StatelessWidget {
  final Rag rag;
  final RagTrend trend;
  final String? previousRagLabel;
  final String projectId;
  final AppDatabase db;
  final List<TimelineWorkPackage> wps;

  const ProgrammeRagWidget({
    super.key,
    required this.rag,
    required this.trend,
    this.previousRagLabel,
    required this.projectId,
    required this.db,
    required this.wps,
  });

  Color get _ragColor => switch (rag) {
        Rag.green      => KColors.phosphor,
        Rag.amber      => KColors.amber,
        Rag.red        => KColors.red,
        Rag.notStarted => KColors.textMuted,
      };

  Color get _ragBg => switch (rag) {
        Rag.green      => KColors.phosDim,
        Rag.amber      => KColors.amberDim,
        Rag.red        => KColors.redDim,
        Rag.notStarted => KColors.surface,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        // RAG badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _ragBg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _ragColor),
          ),
          child: Text(
            rag.label.toUpperCase(),
            style: TextStyle(
                color: _ragColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5),
          ),
        ),
        const SizedBox(width: 20),
        // Trend + narrative
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (trend != RagTrend.noData)
                Text(
                  '${trend.arrow}  ${trend.label}'
                  '${previousRagLabel != null ? ' (was $previousRagLabel)' : ''}',
                  style: const TextStyle(
                      color: KColors.textDim, fontSize: 12),
                ),
            ],
          ),
        ),
        // Override button
        PopupMenuButton<String>(
          tooltip: 'Override RAG',
          color: KColors.surface2,
          icon: const Icon(Icons.edit_outlined,
              size: 14, color: KColors.textDim),
          onSelected: (v) => _overrideRag(v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'green',       height: 32,
                child: Text('Green',       style: TextStyle(color: KColors.phosphor, fontSize: 12))),
            const PopupMenuItem(value: 'amber',       height: 32,
                child: Text('Amber',       style: TextStyle(color: KColors.amber, fontSize: 12))),
            const PopupMenuItem(value: 'red',         height: 32,
                child: Text('Red',         style: TextStyle(color: KColors.red, fontSize: 12))),
            const PopupMenuItem(value: 'not_started', height: 32,
                child: Text('Not started', style: TextStyle(color: KColors.textMuted, fontSize: 12))),
          ],
        ),
      ]),
    );
  }

  Future<void> _overrideRag(String ragValue) async {
    // Override by setting ALL work packages to the chosen RAG,
    // or — when clearing — to not_started. PM can adjust per-WP in Plan view.
    for (final wp in wps) {
      await db.programmeGanttDao.upsertWorkPackage(
        TimelineWorkPackagesCompanion(
          id:        Value(wp.id),
          projectId: Value(wp.projectId),
          name:      Value(wp.name),
          ragStatus: Value(ragValue),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }
}
