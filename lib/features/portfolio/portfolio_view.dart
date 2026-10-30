import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/portfolio/portfolio_rollup.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import 'portfolio_heatmap.dart';
import 'portfolio_sections.dart';
import 'portfolio_series.dart';
import 'portfolio_widgets.dart';

/// Portfolio overview: the PMO's view across programmes, built entirely
/// from each programme's weekly pulse. Health by rules (with the
/// self-reported colour beside it), the decision system, flow and load,
/// the finance roll-up, the portfolio's top risks, and the completeness
/// ladder. Trends come from the weekly pulse history.
///
/// Web-safe by construction: reads the local pulse table only.
class PortfolioView extends StatelessWidget {
  const PortfolioView({super.key});

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProjectProvider>();
    final portfolioId = pp.currentProjectId;
    if (portfolioId == null || !pp.isPortfolio) {
      return Center(
        child: Text('Select a portfolio.', style: TextStyle(color: KColors.textDim)),
      );
    }
    final db = context.read<AppDatabase>();
    final localIds = {for (final p in pp.projects) p.id};
    return StreamBuilder<List<PortfolioPulse>>(
      stream: db.portfolioPulsesDao.watchForPortfolio(portfolioId),
      builder: (context, snap) {
        final history = historyByProgramme(snap.data ?? const []);
        final series = sortSeries([
          for (final e in history.entries)
            ProgrammeSeries(
              programmeId: e.key,
              history: e.value,
              isLocal: localIds.contains(e.key),
            ),
        ]);
        return _PortfolioBody(
          series: series,
          loading: snap.connectionState == ConnectionState.waiting,
          onOpen: (s) => pp.selectProjectById(s.programmeId),
        );
      },
    );
  }
}

class _PortfolioBody extends StatelessWidget {
  final List<ProgrammeSeries> series;
  final bool loading;
  final void Function(ProgrammeSeries) onOpen;
  const _PortfolioBody({
    required this.series,
    required this.loading,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final latest = [for (final s in series) s.latest];
    final weeks = series.isEmpty
        ? 0
        : series.map((s) => s.history.length).reduce((a, b) => a > b ? a : b);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PortfolioSectionLabel(
            'PORTFOLIO PULSE',
            hint: series.isEmpty
                ? 'No programme pulses yet.'
                : '${series.length} programme${series.length == 1 ? '' : 's'} '
                    'reporting over $weeks week${weeks == 1 ? '' : 's'}. Health is '
                    'computed from each programme\'s data; the reported colour sits beside it.',
          ),
          const SizedBox(height: 14),
          if (series.isEmpty && !loading) ...[
            _EmptyState(),
          ] else if (series.isNotEmpty) ...[
            PortfolioTotals(pulses: latest),
            const SizedBox(height: 24),
            const PortfolioSectionLabel(
              'HEALTH BY RULES',
              hint: 'Colour falls out of the data under declared thresholds. '
                  'Hover a cell for the rule that fired; click a programme to open it.',
            ),
            const SizedBox(height: 8),
            PortfolioHeatmap(series: series, now: now, onOpen: onOpen),
            const SizedBox(height: 24),
            const PortfolioSectionLabel(
              'DECISION SYSTEM',
              hint: 'Measure the system, not a curated list: latency, age past need-by, '
                  'and how recently the log moved.',
            ),
            const SizedBox(height: 8),
            DecisionSystemSection(series: series),
            const SizedBox(height: 24),
            const PortfolioSectionLabel(
              'FLOW AND LOAD',
              hint: 'Starts vs active, demonstrated throughput, and who is spread across '
                  'the most projects.',
            ),
            const SizedBox(height: 8),
            FlowSection(series: series),
            const SizedBox(height: 24),
            const PortfolioSectionLabel(
              'FINANCE',
              hint: 'Approved budgets, submitted forecasts and actuals, summed only where '
                  'currencies match.',
            ),
            const SizedBox(height: 8),
            FinanceSection(series: series),
            const SizedBox(height: 24),
            const PortfolioSectionLabel(
              'TOP RISKS ACROSS THE PORTFOLIO',
              hint: 'Every programme\'s top risks merged and ranked by score; escalated first on ties.',
            ),
            const SizedBox(height: 8),
            TopRisksSection(series: series),
            const SizedBox(height: 24),
            const PortfolioSectionLabel(
              'DATA COMPLETENESS',
              hint: 'The minimum data standard, per programme. The roll-up is only as '
                  'trustworthy as the least complete row.',
            ),
            const SizedBox(height: 8),
            CompletenessSection(series: series),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PortfolioCard(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Link programmes from Settings → Portfolio Links. Generate a code '
        'here and have each programme manager paste it into their '
        'programme\'s settings. Each linked programme sends one pulse a '
        'week; the first arrives on its next sync or launch.',
        style: TextStyle(color: KColors.textDim, fontSize: 12, height: 1.5),
      ),
    );
  }
}
