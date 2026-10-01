import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../core/finance/contingency_ledger.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';

/// Project-side: "Allocation from [programme]: X", with the movement
/// history behind it on tap. Read-only — the programme owns the number.
class ReceivedAllocationChip extends StatelessWidget {
  final AppDatabase db;
  final String projectId;
  /// The project's own approved budget total, to show the gap.
  final int? approvedBudgetMinor;
  const ReceivedAllocationChip(
      {super.key, required this.db, required this.projectId, this.approvedBudgetMinor});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ReceivedAllocation>>(
      stream: db.financeDao.watchReceivedAllocations(projectId),
      builder: (context, snap) {
        final rows = snap.data ?? const [];
        if (rows.isEmpty) return const SizedBox.shrink();
        return Wrap(spacing: 8, children: [for (final r in rows) _chip(context, r)]);
      },
    );
  }

  Widget _chip(BuildContext context, ReceivedAllocation r) {
    final over = approvedBudgetMinor != null && approvedBudgetMinor! > r.amountMinor;
    final colour = over ? KColors.amber : KColors.phosphor;
    return InkWell(
      onTap: () => _showHistory(context, r),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.1),
          border: Border.all(color: colour.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.account_balance_wallet_outlined, size: 12, color: colour),
          const SizedBox(width: 6),
          Text(
            'Allocated by ${r.programmeName ?? 'programme'}: '
            '${Money.formatMinorCompact(r.amountMinor, r.currency)}'
            '${over ? '  ·  budget exceeds it by ${Money.formatMinorCompact(approvedBudgetMinor! - r.amountMinor, r.currency)}' : ''}',
            style: TextStyle(color: colour, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }

  void _showHistory(BuildContext context, ReceivedAllocation r) {
    List<Map<String, dynamic>> history = const [];
    try {
      history = ((jsonDecode(r.historyJson ?? '[]') as List).cast<Map>())
          .map((m) => m.cast<String, dynamic>())
          .toList();
    } catch (_) {}
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColors.surface,
        title: Text('Allocation from ${r.programmeName ?? 'the programme'}',
            style: const TextStyle(color: KColors.text, fontSize: 14)),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Money.formatMinorCompact(r.amountMinor, r.currency),
                style: const TextStyle(color: KColors.text, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
            const SizedBox(height: 4),
            const Text('Set by the programme; every change below carries the decision behind it.',
                style: TextStyle(color: KColors.textDim, fontSize: 11)),
            const SizedBox(height: 12),
            if (history.isEmpty)
              const Text('No movements recorded.', style: TextStyle(color: KColors.textMuted, fontSize: 12))
            else
              for (final h in history.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 84,
                      child: Text('${h['moved_on'] ?? ''}',
                          style: const TextStyle(color: KColors.textDim, fontSize: 11, fontFamily: 'monospace')),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${movementLabel('${h['kind']}')}  '
                          '${movementSign('${h['kind']}') < 0 ? '−' : '+'}'
                          '${Money.formatMinorCompact(h['amount_minor'] as int? ?? 0, r.currency)}',
                          style: const TextStyle(color: KColors.text, fontSize: 12),
                        ),
                        if (h['decision_ref'] != null || h['decision'] != null)
                          Text('${h['decision_ref'] ?? ''} ${h['decision'] ?? ''}'.trim(),
                              style: const TextStyle(color: KColors.amber, fontSize: 11)),
                        if (h['reason'] != null)
                          Text('${h['reason']}', style: const TextStyle(color: KColors.textDim, fontSize: 11)),
                      ]),
                    ),
                  ]),
                ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }
}
