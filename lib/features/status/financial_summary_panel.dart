import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/database/database.dart';
import '../../core/finance/programme_rollup.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';

/// Status-page financial summary — Finance v1+v2. The approved budget
/// (total, FY breakdown, per-category bars, approval record) plus,
/// when forecasting has started, the latest forecast-at-completion with
/// variance against tolerance and actuals to date. Quiet single line
/// when no budget is approved.
class FinancialSummaryPanel extends StatelessWidget {
  final ProjectBudget? approvedBudget;
  final BudgetTotals? totals;

  /// Cost category id → display name, for the category bars.
  final Map<String, String> categoryNames;

  /// v2 extras — all null/absent until forecasting/actuals start.
  final int? forecastTotalMinor;
  final String? forecastPeriod;
  final int? varianceBp;
  final int? actualsToDateMinor;

  /// Programme roll-up over linked projects (null / empty on a project).
  final ProgrammeFinance? portfolio;
  final Map<String, String> projectNames;

  const FinancialSummaryPanel({
    super.key,
    required this.approvedBudget,
    required this.totals,
    required this.categoryNames,
    this.forecastTotalMinor,
    this.forecastPeriod,
    this.varianceBp,
    this.actualsToDateMinor,
    this.portfolio,
    this.projectNames = const {},
  });

  @override
  Widget build(BuildContext context) {
    final own = _own(context);
    final port = portfolio;
    if (port == null || port.isEmpty) return own;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _PortfolioBlock(finance: port, projectNames: projectNames),
      const SizedBox(height: 10),
      own,
    ]);
  }

  Widget _own(BuildContext context) {
    final budget = approvedBudget;
    if (budget == null || totals == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
            portfolio == null || portfolio!.isEmpty
                ? 'No approved budget.'
                : 'No programme-level budget of its own.',
            style: const TextStyle(color: KColors.textMuted, fontSize: 12)),
      );
    }
    final t = totals!;
    final fys = t.byFinancialYear.keys.toList()..sort();
    final maxCategoryMinor = t.byCategoryId.values
        .fold<int>(0, (m, v) => v > m ? v : m);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(budget.name,
                        style: const TextStyle(
                            color: KColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(
                      budget.approvedAt == null
                          ? 'Approved'
                          : 'Approved ${DateFormat('d MMM yyyy').format(budget.approvedAt!)}'
                              '${budget.approvedBy == null ? '' : ' by ${budget.approvedBy}'}',
                      style: const TextStyle(
                          color: KColors.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                Money.formatMinorCompact(t.totalMinor, budget.currency),
                style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (forecastTotalMinor != null || actualsToDateMinor != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (forecastTotalMinor != null) ...[
                  _metric(
                    'FORECAST AT COMPLETION'
                    '${forecastPeriod == null ? '' : ' ($forecastPeriod)'}',
                    Money.formatMinorCompact(
                        forecastTotalMinor!, budget.currency),
                    _varianceColor(),
                  ),
                  const SizedBox(width: 24),
                  _metric('VARIANCE', Money.formatBp(varianceBp),
                      _varianceColor()),
                  const SizedBox(width: 24),
                ],
                if (actualsToDateMinor != null)
                  _metric(
                      'ACTUALS TO DATE',
                      Money.formatMinorCompact(
                          actualsToDateMinor!, budget.currency),
                      KColors.text),
              ],
            ),
          ],
          if (fys.length > 1) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: fys
                  .map((fy) => Text(
                        '$fy  ${Money.formatMinorCompact(t.byFinancialYear[fy]!, budget.currency)}',
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 11),
                      ))
                  .toList(),
            ),
          ],
          if (t.byCategoryId.isNotEmpty && maxCategoryMinor > 0) ...[
            const SizedBox(height: 12),
            ...(t.byCategoryId.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .map((e) => _categoryBar(
                      categoryNames[e.key] ?? 'Unknown',
                      e.value,
                      maxCategoryMinor,
                      budget.currency,
                    )),
          ],
        ],
      ),
    );
  }

  Color _varianceColor() {
    final bp = varianceBp;
    final tol = approvedBudget?.varianceToleranceBp ?? 500;
    if (bp == null) return KColors.text;
    if (bp.abs() > tol) return KColors.red;
    if (bp > 0) return KColors.amber;
    return KColors.phosphor;
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: KColors.textMuted, fontSize: 9, letterSpacing: 0.5)),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _categoryBar(
      String name, int amountMinor, int maxMinor, String currency) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(name,
                style: const TextStyle(color: KColors.textDim, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Integer minor units drive the ratio; the double exists
                // only for pixel layout, never for money values.
                final frac = amountMinor / maxMinor;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 8,
                    width: (constraints.maxWidth * frac)
                        .clamp(2.0, constraints.maxWidth),
                    decoration: BoxDecoration(
                      color: KColors.blue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              Money.formatMinorCompact(amountMinor, currency),
              textAlign: TextAlign.right,
              style: const TextStyle(color: KColors.text, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Portfolio roll-up for a programme: the linked projects' approved
/// budgets, latest submitted forecasts and actuals, and who is beyond
/// tolerance.
class _PortfolioBlock extends StatelessWidget {
  final ProgrammeFinance finance;
  final Map<String, String> projectNames;
  const _PortfolioBlock({required this.finance, required this.projectNames});

  @override
  Widget build(BuildContext context) {
    final f = finance;
    final cur = f.currency ?? 'AUD';
    final breaches = f.breaches;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
              'PORTFOLIO · ${f.projects.length} '
              '${f.projects.length == 1 ? 'PROJECT' : 'PROJECTS'}',
              style: const TextStyle(
                  color: KColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const Spacer(),
          Text(
            breaches.isEmpty
                ? 'All within tolerance'
                : '${breaches.length} beyond tolerance',
            style: TextStyle(
                color: breaches.isEmpty ? KColors.phosphor : KColors.red,
                fontSize: 11,
                fontWeight: FontWeight.w700),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _stat('Budget', Money.formatMinorCompact(f.budgetMinor, cur)),
          _stat('Forecast', Money.formatMinorCompact(f.forecastMinor, cur)),
          _stat('Actuals', Money.formatMinorCompact(f.actualsMinor, cur)),
          _stat('Variance', Money.formatBp(f.varianceBp),
              color: f.varianceBp == null
                  ? KColors.textMuted
                  : f.varianceBp!.abs() > 500
                      ? KColors.red
                      : KColors.text),
        ]),
        const SizedBox(height: 10),
        for (final r in f.projects)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              if (r.breach)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.warning_amber_rounded,
                      size: 12, color: KColors.red),
                ),
              Expanded(
                child: Text(projectNames[r.sourceId] ?? 'Linked project',
                    style: const TextStyle(color: KColors.text, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(
                '${Money.formatMinorCompact(r.budgetMinor, r.currency ?? cur)}'
                ' → ${r.forecastMinor == null ? 'no forecast' : Money.formatMinorCompact(r.forecastMinor, r.currency ?? cur)}'
                '  ${Money.formatBp(r.varianceBp)}',
                style: TextStyle(
                    color: r.breach ? KColors.red : KColors.textDim,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _stat(String label, String value, {Color color = KColors.text}) =>
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: KColors.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
        ]),
      );
}
