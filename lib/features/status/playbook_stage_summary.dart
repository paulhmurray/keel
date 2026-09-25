import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../core/playbook/current_stage.dart';
import '../../shared/theme/keel_colors.dart';

class PlaybookStageSummary extends StatelessWidget {
  final PlaybookStage? stage;
  final ProjectStageProgressesData? progress;
  final bool attached;
  final int stagesDone;
  final int stagesTotal;
  final bool allComplete;

  const PlaybookStageSummary({
    super.key,
    required this.stage,
    required this.progress,
    this.attached = false,
    this.stagesDone = 0,
    this.stagesTotal = 0,
    this.allComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    if (stage == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
            attached
                ? 'Playbook attached but it has no stages yet.'
                : 'No playbook attached.',
            style: const TextStyle(color: KColors.textMuted, fontSize: 12)),
      );
    }

    final status = progress?.status ?? 'not_started';
    final checklist = _parseChecklist(progress?.checklist);
    final total     = checklist.length;
    final complete  = checklist.where((c) => c['checked'] == true).length;

    final statusColor = switch (status) {
      'complete'         => KColors.phosphor,
      'in_progress'      => KColors.amber,
      'blocked'          => KColors.red,
      'pending_approval' => KColors.violet,
      _                  => KColors.textMuted,
    };
    final statusLabel =
        allComplete ? 'All stages complete' : playbookStatusLabel(status);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        const Text('▶ ', style: TextStyle(color: KColors.amber, fontSize: 13)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12),
                  children: [
                    TextSpan(
                        text: 'Stage ${stage!.sortOrder + 1}: ${stage!.name}',
                        style: const TextStyle(
                            color: KColors.text,
                            fontWeight: FontWeight.w500)),
                    const TextSpan(text: '  '),
                    TextSpan(
                        text: '— $statusLabel',
                        style: TextStyle(
                            color: statusColor, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                  '$complete of $total checklist items complete'
                  '${stagesTotal > 0 ? '  ·  $stagesDone of $stagesTotal stages complete' : ''}',
                  style: const TextStyle(
                      color: KColors.textDim, fontSize: 11)),
            ],
          ),
        ),
      ]),
    );
  }

  List<Map<String, dynamic>> _parseChecklist(String? json) {
    if (json == null) return [];
    try {
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
