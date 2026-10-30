import 'package:flutter/material.dart';

import '../../core/portfolio/portfolio_rules.dart';
import '../../core/portfolio/programme_pulse.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/min_width_hscroll.dart';
import 'portfolio_series.dart';
import 'portfolio_widgets.dart';

/// Health by rules: one row per programme, one cell per dimension, the
/// self-reported colour beside the computed one, and a trend of the rule
/// verdict over the weeks of pulse history. Hover a cell for the rule.
class PortfolioHeatmap extends StatelessWidget {
  final List<ProgrammeSeries> series;
  final void Function(ProgrammeSeries)? onOpen;
  final DateTime now;
  const PortfolioHeatmap({
    super.key,
    required this.series,
    required this.now,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final head = portfolioHeadStyle();
    return PortfolioCard(
      child: MinWidthHScroll(
        minWidth: 980,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(flex: 5, child: Text('PROGRAMME', style: head)),
                  _hcell(Text('RULES', style: head)),
                  for (final d in HealthDimension.values)
                    _hcell(Text(d.label.toUpperCase(), style: head)),
                  _hcell(Text('REPORTED', style: head), w: 96),
                  _hcell(Text('TREND', style: head), w: 96),
                  _hcell(Text('DATA', style: head), w: 110),
                  _hcell(Text('PULSE', style: head), w: 64),
                ],
              ),
            ),
            Divider(height: 1, color: KColors.border),
            for (final s in series)
              _HeatRow(series: s, now: now, onOpen: onOpen),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(
                'Rules: schedule amber at ${PortfolioRules.scheduleAmberOverdue} overdue '
                'milestone, red at ${PortfolioRules.scheduleRedOverdue} · finance red when a '
                'project breaches its own tolerance, amber beyond ±'
                '${PortfolioRules.financeAmberBp ~/ 100}.${PortfolioRules.financeAmberBp % 100 ~/ 10}% · '
                'RAID amber at ${PortfolioRules.raidAmberHigh} high or any escalation, red at '
                '${PortfolioRules.raidRedHigh} high or ${PortfolioRules.raidRedEscalated} escalations · '
                'decisions amber at ${PortfolioRules.decisionsAmberPastNeedBy} past need-by or a '
                'log quiet ${PortfolioRules.decisionsStaleDays}+ days, red at '
                '${PortfolioRules.decisionsRedPastNeedBy} past need-by. '
                'Reported is what the programme said; ⚠ marks a report better than its data.',
                style: portfolioDimStyle(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _hcell(Widget child, {double w = 72}) => SizedBox(
    width: w,
    child: Center(child: child),
  );
}

class _HeatRow extends StatelessWidget {
  final ProgrammeSeries series;
  final DateTime now;
  final void Function(ProgrammeSeries)? onOpen;
  const _HeatRow({required this.series, required this.now, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = series.latest;
    final overall = PortfolioRules.overall(p, now: now);
    final trend = [
      for (final h in series.history)
        ragSeverity(PortfolioRules.overall(h, now: h.capturedAt)),
    ];
    final age = daysBetween(p.capturedAt, now);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.programmeName.isEmpty
                        ? series.programmeId
                        : p.programmeName,
                    style: portfolioBodyStyle().copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (series.isLocal)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.open_in_new,
                      size: 13,
                      color: KColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          _cell(
            RagCell(rag: overall, reason: 'Worst of the four rule dimensions'),
          ),
          for (final d in HealthDimension.values)
            _cell(
              Builder(
                builder: (_) {
                  final v = PortfolioRules.judge(p, d, now: now);
                  return RagCell(rag: v.rag, reason: '${d.label}: ${v.reason}');
                },
              ),
            ),
          _cell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RagChip(
                  p.health.reportedRag ?? 'not_started',
                  label: p.health.reportedRag == null ? 'none' : null,
                ),
                if (p.health.watermelon) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message:
                        'Reported ${p.health.reportedRag} while the plan data computes '
                        '${p.health.computedRag}',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: KColors.red,
                    ),
                  ),
                ],
              ],
            ),
            w: 96,
          ),
          _cell(PulseSparkline(values: trend, max: 3), w: 96),
          _cell(_Completeness(score: p.completeness.score), w: 110),
          _cell(
            Text(
              age <= 0 ? 'today' : '${age}d ago',
              style: age > 10
                  ? portfolioDimStyle().copyWith(color: KColors.amber)
                  : portfolioDimStyle(),
            ),
            w: 64,
          ),
        ],
      ),
    );
    if (!series.isLocal || onOpen == null) return content;
    return Tooltip(
      message: 'Open ${p.programmeName}',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () => onOpen!(series),
        hoverColor: KColors.surface2,
        child: content,
      ),
    );
  }

  static Widget _cell(Widget child, {double w = 72}) => SizedBox(
    width: w,
    child: Center(child: child),
  );
}

class _Completeness extends StatelessWidget {
  final int score;
  const _Completeness({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? KColors.phosphor
        : score >= 50
        ? KColors.amber
        : KColors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 6,
                backgroundColor: KColors.surface2,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('$score%', style: portfolioDimStyle()),
        ],
      ),
    );
  }
}
