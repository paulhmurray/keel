import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

class PendingDecisionsPanel extends StatelessWidget {
  final List<Decision> decisions;

  const PendingDecisionsPanel({super.key, required this.decisions});

  @override
  Widget build(BuildContext context) {
    if (decisions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No pending decisions.',
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
          for (int i = 0; i < decisions.length; i++)
            _DecisionRow(
              decision: decisions[i],
              rank: i + 1,
              isLast: i == decisions.length - 1,
            ),
        ],
      ),
    );
  }
}

class _DecisionRow extends StatelessWidget {
  final Decision decision;
  final int rank;
  final bool isLast;

  const _DecisionRow({
    required this.decision,
    required this.rank,
    required this.isLast,
  });

  bool get _isOverdue {
    if (decision.dueDate == null) return false;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return decision.dueDate!.compareTo(today) < 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isOverdue ? const Color(0x08EF4444) : KColors.surface,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                    color: KColors.border.withValues(alpha: 0.5))),
        borderRadius: isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(4))
            : null,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Ref
        SizedBox(
          width: 48,
          child: Text(
            decision.ref ?? 'DC$rank',
            style: TextStyle(
                color: _isOverdue ? KColors.red : KColors.amber,
                fontSize: 11,
                fontWeight: FontWeight.w700),
          ),
        ),
        // Due date
        SizedBox(
          width: 90,
          child: Text(
            decision.dueDate ?? '—',
            style: TextStyle(
                color: _isOverdue ? KColors.red : KColors.textDim,
                fontSize: 11,
                fontWeight: _isOverdue ? FontWeight.w600 : FontWeight.normal),
          ),
        ),
        // Description
        Expanded(
          child: Text(
            decision.description,
            style: TextStyle(
                color: _isOverdue ? KColors.red : KColors.text,
                fontSize: 12),
          ),
        ),
      ]),
    );
  }
}
