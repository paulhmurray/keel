import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

class UpcomingMilestonesList extends StatelessWidget {
  final List<TimelineActivity> milestones;
  final List<String> monthLabels;

  const UpcomingMilestonesList({
    super.key,
    required this.milestones,
    required this.monthLabels,
  });

  String _monthLabel(int? idx) {
    if (idx == null) return '—';
    if (idx >= 0 && idx < monthLabels.length) return monthLabels[idx];
    return 'M$idx';
  }

  @override
  Widget build(BuildContext context) {
    if (milestones.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No milestones in the next 30 days.',
            style: TextStyle(color: KColors.textMuted, fontSize: 12)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          for (int i = 0; i < milestones.length; i++)
            _MilestoneRow(
              activity: milestones[i],
              monthLabel: _monthLabel(milestones[i].startMonth),
              isLast: i == milestones.length - 1,
            ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final TimelineActivity activity;
  final String monthLabel;
  final bool isLast;

  const _MilestoneRow({
    required this.activity,
    required this.monthLabel,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor) = switch (activity.activityType) {
      'hard_deadline' => ('⚠', KColors.red),
      'gate'          => ('◈', KColors.amber),
      _               => ('◆', KColors.textDim),
    };
    final isHard = activity.activityType == 'hard_deadline';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isHard
            ? const Color(0x08EF4444)
            : KColors.surface,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                    color: KColors.border.withValues(alpha: 0.5))),
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(4))
            : null,
      ),
      child: Row(children: [
        SizedBox(
          width: 24,
          child: Text(icon,
              style: TextStyle(color: iconColor, fontSize: 13)),
        ),
        Expanded(
          child: Text(
            activity.name,
            style: TextStyle(
                color: isHard ? KColors.red : KColors.text,
                fontSize: 12,
                fontWeight:
                    isHard ? FontWeight.w600 : FontWeight.normal),
          ),
        ),
        SizedBox(
          width: 72,
          child: Text(monthLabel,
              style: const TextStyle(
                  color: KColors.textDim, fontSize: 11)),
        ),
        SizedBox(
          width: 120,
          child: Text(activity.owner ?? '—',
              style: const TextStyle(
                  color: KColors.textMuted, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}
