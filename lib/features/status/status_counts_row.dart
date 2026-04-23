import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';

class StatusCountsRow extends StatelessWidget {
  final int overdueActions;
  final int openActions;
  final int pendingDecisions;
  final int openRisks;

  const StatusCountsRow({
    super.key,
    required this.overdueActions,
    required this.openActions,
    required this.pendingDecisions,
    required this.openRisks,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        _CountTile(
          count: overdueActions,
          label: 'Overdue actions',
          countColor: overdueActions > 0 ? KColors.red : KColors.textMuted,
        ),
        _CountTile(count: openActions,      label: 'Open actions'),
        _CountTile(count: pendingDecisions, label: 'Pending decisions'),
        _CountTile(count: openRisks,        label: 'Open risks'),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  final int count;
  final String label;
  final Color countColor;

  const _CountTile({
    required this.count,
    required this.label,
    this.countColor = KColors.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: TextStyle(
                  color: countColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: KColors.textMuted,
                  fontSize: 10,
                  letterSpacing: 0.1)),
        ],
      ),
    );
  }
}
