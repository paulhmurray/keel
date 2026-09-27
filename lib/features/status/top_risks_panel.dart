import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../core/raid/risk_rating.dart';
import '../../core/status/risk_ranking.dart';
import '../../core/status/status_snapshot_decoder.dart' show SnapshotRisk;
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;

/// Top risks for the business owner: each row says what the risk is,
/// how bad (rating and score), whether it has been escalated, what we are
/// doing about it, who owns it and when, and what changed since the
/// last report. Enough to be briefed from without opening the register.
class TopRisksPanel extends StatelessWidget {
  final List<Risk> risks;

  /// The previous snapshot's frozen top risks by id, for change markers.
  /// Null when there is no earlier snapshot.
  final Map<String, SnapshotRisk>? previous;

  const TopRisksPanel({super.key, required this.risks, this.previous});

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
              change: riskChangeSince(risks[i], previous),
              changeLabel: riskChangeLabel(
                  riskChangeSince(risks[i], previous), risks[i], previous),
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
  final RiskChange? change;
  final String? changeLabel;

  const _RiskRow({
    required this.risk,
    required this.rank,
    required this.isLast,
    required this.change,
    required this.changeLabel,
  });

  Color _bandColor(String band) => switch (band) {
        'high' => KColors.red,
        'medium' => KColors.amber,
        _ => KColors.phosphor,
      };

  @override
  Widget build(BuildContext context) {
    final band = riskBand(risk.likelihood, risk.impact);
    final c = _bandColor(band);
    final hasTitle = risk.title != null && risk.title!.isNotEmpty;
    final today = DateTime.now();
    final overdue = risk.dueDate != null &&
        risk.dueDate!.compareTo(du.toIsoDate(today)) < 0;
    final reviewLate = reviewOverdue(risk.nextReviewAt, today);
    final soWhat = riskSoWhat(risk);
    final changeColor = switch (change) {
      RiskChange.up => KColors.red,
      RiskChange.down => KColors.phosphor,
      RiskChange.newEntry => KColors.amber,
      _ => KColors.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
        // Rank + ref + score bar
        SizedBox(
          width: 44,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(risk.ref ?? '#$rank',
                style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                border: Border.all(color: c.withAlpha(140)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('${riskScore(risk.likelihood, risk.impact)}',
                  style: TextStyle(
                      color: c, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Headline: title (or description), escalated, change marker
            Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(hasTitle ? risk.title! : risk.description,
                    style: const TextStyle(
                        color: KColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                if (risk.steerco)
                  const Tooltip(
                    message: 'Escalated for attention — how and where it is '
                        'raised is the PM\'s call',
                    child: Text('▲ ESCALATED',
                        style: TextStyle(
                            color: KColors.red,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4)),
                  ),
                if (changeLabel != null)
                  Text(changeLabel!,
                      style: TextStyle(
                          color: changeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 3),
            // Rating in words — the score alone doesn't teach anyone
            Text(
              '${likelihoodLabel(risk.likelihood)} likelihood, '
              '${consequenceLabel(risk.impact).toLowerCase()} consequence'
              '${risk.likelihoodTarget != null || risk.impactTarget != null ? '  ·  target ${likelihoodLabel(risk.likelihoodTarget ?? risk.likelihood)} / ${consequenceLabel(risk.impactTarget ?? risk.impact)}' : ''}',
              style: TextStyle(color: c, fontSize: 11),
            ),
            if (hasTitle) ...[
              const SizedBox(height: 3),
              Text(risk.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: KColors.textDim, fontSize: 11)),
            ],
            if (soWhat != null) ...[
              const SizedBox(height: 4),
              Text(
                '${risk.statusNote?.trim().isNotEmpty == true ? 'Latest' : 'Treatment'}: $soWhat',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: KColors.text, fontSize: 11),
              ),
            ],
            const SizedBox(height: 4),
            // Meta line: strategy · owner · due · review
            Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(
                    kRiskStrategyLabels[risk.strategy]?.split(' — ').first ??
                        risk.strategy,
                    style: const TextStyle(
                        color: KColors.textMuted, fontSize: 10)),
                if (risk.owner != null && risk.owner!.isNotEmpty)
                  Text('Owner ${risk.owner}',
                      style: const TextStyle(
                          color: KColors.textMuted, fontSize: 10)),
                if (risk.dueDate != null)
                  Text(
                      '${overdue ? 'Treatment overdue' : 'Treatment due'} '
                      '${du.formatDate(risk.dueDate)}',
                      style: TextStyle(
                          color: overdue ? KColors.red : KColors.textMuted,
                          fontSize: 10,
                          fontWeight:
                              overdue ? FontWeight.w600 : FontWeight.normal)),
                if (reviewLate)
                  Text('Review overdue ${du.formatDate(risk.nextReviewAt)}',
                      style: const TextStyle(
                          color: KColors.amber, fontSize: 10)),
                if (risk.status == 'in progress')
                  const Text('Treatment in progress',
                      style: TextStyle(color: KColors.textMuted, fontSize: 10)),
              ],
            ),
          ]),
        ),
      ]),
    );
  }
}
