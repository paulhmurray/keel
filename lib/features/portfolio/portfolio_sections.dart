import 'package:flutter/material.dart';

import '../../core/portfolio/portfolio_rollup.dart';
import '../../core/portfolio/programme_pulse.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';
import '../../shared/widgets/min_width_hscroll.dart';
import 'portfolio_series.dart';
import 'portfolio_widgets.dart';

/// The hero row: counts a Head of PMO reacts to before reading anything.
class PortfolioTotals extends StatelessWidget {
  final List<ProgrammePulse> pulses;
  const PortfolioTotals({super.key, required this.pulses});

  @override
  Widget build(BuildContext context) {
    final red = pulses.where((p) => p.health.computedRag == 'red').length;
    final amber = pulses.where((p) => p.health.computedRag == 'amber').length;
    final watermelons = pulses.where((p) => p.health.watermelon).length;
    final pastNeedBy = pulses.fold<int>(
      0,
      (n, p) => n + p.decisions.pastNeedBy,
    );
    final overdueMs = pulses.fold<int>(
      0,
      (n, p) => n + p.health.overdueMilestones,
    );
    final escalated = pulses.fold<int>(0, (n, p) => n + p.raid.escalatedOpen);
    final loaded = portfolioLoad(
      pulses,
      limit: 1000,
    ).where((l) => l.projects >= 3).length;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        StatTile('Red / amber (computed)', '$red / $amber', alert: red > 0),
        StatTile('Watermelons', '$watermelons', alert: watermelons > 0),
        StatTile(
          'Decisions past need-by',
          '$pastNeedBy',
          alert: pastNeedBy > 0,
        ),
        StatTile('Overdue milestones', '$overdueMs', alert: overdueMs > 0),
        StatTile('Escalated open', '$escalated'),
        StatTile('People on 3+ projects', '$loaded', alert: loaded > 0),
        StatTile('Data completeness', '${averageCompleteness(pulses)}%'),
      ],
    );
  }
}

/// Decisions measured as a system, not a curated list.
class DecisionSystemSection extends StatelessWidget {
  final List<ProgrammeSeries> series;
  const DecisionSystemSection({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final head = portfolioHeadStyle();
    return PortfolioCard(
      child: MinWidthHScroll(
        minWidth: 900,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(flex: 4, child: Text('PROGRAMME', style: head)),
                  Expanded(flex: 2, child: Text('OPEN', style: head)),
                  Expanded(flex: 3, child: Text('PAST NEED-BY', style: head)),
                  Expanded(flex: 3, child: Text('OLDEST OPEN', style: head)),
                  Expanded(flex: 3, child: Text('LATENCY (90D)', style: head)),
                  Expanded(flex: 3, child: Text('MADE (30D)', style: head)),
                  Expanded(flex: 3, child: Text('LOG UPDATED', style: head)),
                  SizedBox(
                    width: 96,
                    child: Center(
                      child: Text(
                        'PAST NEED-BY TREND',
                        style: head,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: KColors.border),
            for (final s in series)
              Builder(
                builder: (_) {
                  final d = s.latest.decisions;
                  final body = portfolioBodyStyle();
                  final red = portfolioBodyStyle(color: KColors.red);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: KColors.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            s.name,
                            style: body.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${d.open}', style: body),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '${d.pastNeedBy}',
                            style: d.pastNeedBy > 0 ? red : body,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            d.open == 0 ? '–' : '${d.oldestOpenDays}d',
                            style: body,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            d.medianLatencyDays == null
                                ? 'none made'
                                : 'median ${d.medianLatencyDays}d',
                            style: d.medianLatencyDays == null
                                ? portfolioDimStyle()
                                : body,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('${d.decidedLast30}', style: body),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(d.logLastUpdated ?? '–', style: body),
                        ),
                        SizedBox(
                          width: 96,
                          child: Center(
                            child: PulseSparkline(
                              values: [
                                for (final h in s.history)
                                  h.decisions.pastNeedBy,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(
                'Latency is raised→made over decisions made in the last 90 days. '
                'A quiet log usually means decisions are being made somewhere else, or not at all.',
                style: portfolioDimStyle(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// WIP and load: starts vs active, demonstrated throughput, who is spread
/// across the most projects.
class FlowSection extends StatelessWidget {
  final List<ProgrammeSeries> series;
  const FlowSection({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final head = portfolioHeadStyle();
    final body = portfolioBodyStyle();
    final load = portfolioLoad(series.map((s) => s.latest));
    return MinWidthHScroll(
      minWidth: 900,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: PortfolioCard(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text('PROGRAMME', style: head),
                        ),
                        Expanded(flex: 3, child: Text('PROJECTS', style: head)),
                        Expanded(
                          flex: 3,
                          child: Text('STARTED THIS QTR', style: head),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('DONE (90D)', style: head),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('ON 3+ PROJECTS', style: head),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: KColors.border),
                  for (final s in series)
                    Builder(
                      builder: (_) {
                        final f = s.latest.flow;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: KColors.border),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  s.name,
                                  style: body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  f.projectsActive == null
                                      ? '${f.projectsLinked} linked'
                                      : '${f.projectsActive} active of ${f.projectsLinked}',
                                  style: body,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  f.startsThisQuarter?.toString() ?? '–',
                                  style: body,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  '${f.completedActivitiesLast90} activities',
                                  style: body,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  '${f.peopleOn3PlusProjects}',
                                  style: f.peopleOn3PlusProjects > 0
                                      ? portfolioBodyStyle(color: KColors.amber)
                                      : body,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Text(
                      'Start more than you finish and WIP grows; by Little\'s Law durations stretch '
                      'unless throughput rises. Finishes per quarter arrive with project close dates.',
                      style: portfolioDimStyle(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: PortfolioCard(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MOST LOADED PEOPLE', style: head),
                  const SizedBox(height: 6),
                  if (load.isEmpty)
                    Text(
                      'No team roles assigned yet.',
                      style: portfolioDimStyle(),
                    )
                  else
                    for (final l in load)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.name,
                                style: body,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${l.projects} projects · ${l.programmes} prog',
                              style: l.projects >= 3
                                  ? portfolioBodyStyle(color: KColors.amber)
                                  : portfolioDimStyle(),
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 6),
                  Text(
                    'As utilisation nears 100% wait times climb sharply, not gradually.',
                    style: portfolioDimStyle(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Money across programmes, matching currency only.
class FinanceSection extends StatelessWidget {
  final List<ProgrammeSeries> series;
  const FinanceSection({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final totals = rollupPortfolioFinance(series.map((s) => s.latest));
    final head = portfolioHeadStyle();
    final body = portfolioBodyStyle();
    if (totals == null) {
      return PortfolioCard(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No programme has cascaded an approved budget yet.',
          style: portfolioDimStyle(),
        ),
      );
    }
    final cur = totals.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatTile(
              'Budget ($cur)',
              Money.formatMinorCompact(totals.budgetMinor, cur),
            ),
            StatTile(
              'Forecast at completion',
              Money.formatMinorCompact(totals.forecastMinor, cur),
            ),
            StatTile(
              'Actuals to date',
              Money.formatMinorCompact(totals.actualsMinor, cur),
            ),
            StatTile(
              'Variance',
              Money.formatBp(totals.varianceBp),
              alert: (totals.varianceBp ?? 0).abs() > 500,
            ),
            StatTile(
              'Projects breaching tolerance',
              '${totals.breachingProjects}',
              alert: totals.breachingProjects > 0,
            ),
          ],
        ),
        const SizedBox(height: 12),
        PortfolioCard(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Text('PROGRAMME', style: head)),
                    Expanded(flex: 3, child: Text('BUDGET', style: head)),
                    Expanded(flex: 3, child: Text('FORECAST', style: head)),
                    Expanded(flex: 3, child: Text('ACTUALS', style: head)),
                    Expanded(flex: 2, child: Text('VARIANCE', style: head)),
                    Expanded(flex: 2, child: Text('BREACHING', style: head)),
                  ],
                ),
              ),
              Divider(height: 1, color: KColors.border),
              for (final s in series.where((s) => s.latest.finance != null))
                Builder(
                  builder: (_) {
                    final f = s.latest.finance!;
                    final c = f.currency ?? cur;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: KColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              s.name,
                              style: body.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              Money.formatMinorCompact(f.budgetMinor, c),
                              style: body,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              Money.formatMinorCompact(f.forecastMinor, c),
                              style: body,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              Money.formatMinorCompact(f.actualsMinor, c),
                              style: body,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              Money.formatBp(f.varianceBp),
                              style: body,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${f.breachingProjects}',
                              style: f.breachingProjects > 0
                                  ? portfolioBodyStyle(color: KColors.red)
                                  : body,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (totals.excludedProgrammes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Text(
                    'Not in the totals (different currency): ${totals.excludedProgrammes.join(', ')}.',
                    style: portfolioDimStyle().copyWith(color: KColors.amber),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The portfolio's top risks, merged from every programme's top list.
class TopRisksSection extends StatelessWidget {
  final List<ProgrammeSeries> series;
  const TopRisksSection({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final risks = portfolioTopRisks(series.map((s) => s.latest));
    final body = portfolioBodyStyle();
    return PortfolioCard(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: risks.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No open risks across the portfolio.',
                style: portfolioDimStyle(),
              ),
            )
          : Column(
              children: [
                for (final r in risks)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: KColors.border)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${r.risk.score}',
                            style: body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: r.risk.score >= 15
                                  ? KColors.red
                                  : KColors.text,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            r.risk.title,
                            style: body,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (r.risk.escalated) ...[
                          const SizedBox(width: 8),
                          const RagChip('red', label: '↑ esc'),
                        ],
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 200,
                          child: Text(
                            r.programmeName,
                            style: portfolioDimStyle(),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The maturity ladder: which inputs each programme actually populates.
class CompletenessSection extends StatelessWidget {
  final List<ProgrammeSeries> series;
  const CompletenessSection({super.key, required this.series});

  static final _steps = <(String, bool Function(PulseCompleteness))>[
    ('Status report', (c) => c.hasStatusReport),
    ('Dated milestones', (c) => c.hasMilestones),
    ('Team roles', (c) => c.hasTeamRoles),
    ('Need-by on decisions', (c) => c.hasDecisionNeedBy),
    ('Approved budget', (c) => c.hasBudget),
    ('Submitted forecast', (c) => c.hasForecast),
  ];

  @override
  Widget build(BuildContext context) {
    final head = portfolioHeadStyle();
    final body = portfolioBodyStyle();
    return PortfolioCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text('PROGRAMME', style: head)),
                for (final s in _steps)
                  Expanded(
                    flex: 2,
                    child: Text(
                      s.$1.toUpperCase(),
                      style: head,
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(
                  width: 56,
                  child: Text('SCORE', style: head, textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: KColors.border),
          for (final s in series)
            Builder(
              builder: (_) {
                final c = s.latest.completeness;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: KColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          s.name,
                          style: body.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final step in _steps)
                        Expanded(
                          flex: 2,
                          child: Center(
                            child: Tooltip(
                              message:
                                  '${step.$1}: ${step.$2(c) ? 'populated' : 'missing'}',
                              child: Icon(
                                step.$2(c)
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 15,
                                color: step.$2(c)
                                    ? KColors.phosphor
                                    : KColors.textMuted,
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${c.score}%',
                          style: body,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Text(
              'Each step is an input the portfolio can only report if the programme records it. '
              'This is the maturity ladder: fill the gaps and the roll-up gets more trustworthy.',
              style: portfolioDimStyle(),
            ),
          ),
        ],
      ),
    );
  }
}
