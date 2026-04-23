import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

class TopRisksPanel extends StatelessWidget {
  final List<Risk> risks;

  const TopRisksPanel({super.key, required this.risks});

  @override
  Widget build(BuildContext context) {
    if (risks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No open risks.',
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
          for (int i = 0; i < risks.length; i++)
            _RiskRow(
              risk: risks[i],
              rank: i + 1,
              isLast: i == risks.length - 1,
            ),
        ],
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  final Risk risk;
  final int rank;
  final bool isLast;

  const _RiskRow({
    required this.risk,
    required this.rank,
    required this.isLast,
  });

  Color _levelColor(String l) => switch (l) {
        'high'   => KColors.red,
        'medium' => KColors.amber,
        _        => KColors.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    final lColor = _levelColor(risk.likelihood);
    final iColor = _levelColor(risk.impact);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.surface,
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
          width: 36,
          child: Text(
            risk.ref ?? 'R$rank',
            style: const TextStyle(
                color: KColors.amber,
                fontSize: 11,
                fontWeight: FontWeight.w700),
          ),
        ),
        // Likelihood/Impact
        SizedBox(
          width: 80,
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 11),
              children: [
                TextSpan(
                    text: _cap(risk.likelihood),
                    style: TextStyle(
                        color: lColor, fontWeight: FontWeight.w600)),
                const TextSpan(
                    text: ' / ',
                    style: TextStyle(color: KColors.textMuted)),
                TextSpan(
                    text: _cap(risk.impact),
                    style: TextStyle(
                        color: iColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        // Description
        Expanded(
          child: Text(
            risk.description,
            style: const TextStyle(color: KColors.text, fontSize: 12),
          ),
        ),
      ]),
    );
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
