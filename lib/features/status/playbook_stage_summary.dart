import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

class PlaybookStageSummary extends StatelessWidget {
  final PlaybookStage? stage;
  final ProjectStageProgressesData? progress;

  const PlaybookStageSummary({
    super.key,
    required this.stage,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    if (stage == null || progress == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No playbook attached.',
            style: TextStyle(color: KColors.textMuted, fontSize: 12)),
      );
    }

    final checklist = _parseChecklist(progress!.checklist);
    final total     = checklist.length;
    final complete  = checklist.where((c) => c['checked'] == true).length;

    final statusColor = switch (progress!.status) {
      'complete'     => KColors.phosphor,
      'in_progress'  => KColors.amber,
      'blocked'      => KColors.red,
      _              => KColors.textMuted,
    };
    final statusLabel = switch (progress!.status) {
      'complete'     => 'Complete',
      'in_progress'  => 'In progress',
      'blocked'      => 'Blocked',
      _              => 'Not started',
    };

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
              Text('$complete of $total checklist items complete',
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
