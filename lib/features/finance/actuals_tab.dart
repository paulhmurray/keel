import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';
import 'finance_form.dart';
import 'money_grid.dart';

/// ACTUALS — manual monthly spend entry (Finance v2; CSV import from
/// the finance partner's GL arrives in v3). Same grid as budget and
/// forecast, but columns are calendar months: type what actually landed
/// each period, per category and optionally per workstream.
class ActualsTab extends StatelessWidget {
  final AppDatabase db;
  final String projectId;
  final List<TimelineWorkPackage> workPackages;
  final String? actor;

  const ActualsTab({
    super.key,
    required this.db,
    required this.projectId,
    required this.workPackages,
    required this.actor,
  });

  @override
  Widget build(BuildContext context) {
    final dao = db.financeDao;
    return StreamBuilder<List<CostCategory>>(
      stream: dao.watchCategories(projectId),
      builder: (context, catSnap) {
        return StreamBuilder<List<ProjectBudget>>(
          stream: dao.watchBudgets(projectId),
          builder: (context, budgetSnap) {
            return StreamBuilder<List<ActualLine>>(
              stream: dao.watchActuals(projectId),
              builder: (context, actualSnap) {
                if (!catSnap.hasData || !actualSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final categories = catSnap.data!;
                final actuals = actualSnap.data!;
                final budgets = budgetSnap.data ?? [];
                final approved = budgets
                    .where((b) => b.status == 'approved')
                    .firstOrNull;
                final currency = approved?.currency ??
                    budgets.firstOrNull?.currency ??
                    'AUD';
                final spent =
                    actuals.fold<int>(0, (s, l) => s + l.amountMinor);

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summaryBar(context, dao, approved, spent, currency),
                      const SizedBox(height: 12),
                      MoneyGrid(
                        cells: dao.watchActuals(projectId).map((ls) => [
                              for (final l in ls)
                                MoneyCell(
                                  id: l.id,
                                  categoryId: l.costCategoryId,
                                  workstreamId: l.workstreamId,
                                  columnKey: l.period,
                                  amountMinor: l.amountMinor,
                                  notes: l.notes,
                                ),
                            ]),
                        categories: categories,
                        workPackages: workPackages,
                        currency: currency,
                        readOnly: false,
                        columnNoun: 'Month',
                        columnHint: 'e.g. ${currentPeriodLabel()}',
                        defaultColumnKey: currentPeriodLabel(),
                        onCommit: ({
                          required existing,
                          required categoryId,
                          required workstreamId,
                          required columnKey,
                          required amountMinor,
                        }) =>
                            dao.upsertActualLine(
                          id: existing?.id ?? const Uuid().v4(),
                          projectId: projectId,
                          period: columnKey,
                          costCategoryId: categoryId,
                          workstreamId:
                              existing?.workstreamId ?? workstreamId,
                          amountMinor: amountMinor,
                          notes: existing?.notes,
                          changedBy: actor,
                        ),
                        onDelete: (cells) async {
                          for (final c in cells) {
                            await dao.deleteActualLine(c.id,
                                changedBy: actor);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _summaryBar(BuildContext context, FinanceDao dao,
      ProjectBudget? approved, int spentMinor, String currency) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ACTUALS TO DATE',
                    style: TextStyle(
                        color: KColors.textMuted,
                        fontSize: 10,
                        letterSpacing: 0.5)),
                Text(
                  Money.formatMinorCompact(spentMinor, currency),
                  style: const TextStyle(
                      color: KColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                const Text(
                    'Manual entry — CSV import from your finance partner '
                    'arrives with reconciliation in v3.',
                    style:
                        TextStyle(color: KColors.textMuted, fontSize: 10)),
              ],
            ),
          ),
          if (approved != null)
            FutureBuilder<BudgetTotals>(
              future: dao.getTotals(approved.id),
              builder: (context, snap) {
                final budgetTotal = snap.data?.totalMinor;
                if (budgetTotal == null || budgetTotal <= 0) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('OF APPROVED BUDGET',
                        style: TextStyle(
                            color: KColors.textMuted,
                            fontSize: 10,
                            letterSpacing: 0.5)),
                    Text(
                      '${Money.formatMinorCompact(budgetTotal, currency)}'
                      '  ·  ${Money.formatBp(_shareBp(spentMinor, budgetTotal)).replaceAll('+', '')} spent',
                      style: const TextStyle(
                          color: KColors.textDim, fontSize: 13),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  /// spent/budget in basis points, half-away rounded (integer maths).
  static int _shareBp(int spent, int budget) {
    final n = spent.abs() * 10000;
    final r = (2 * n + budget) ~/ (2 * budget);
    return spent < 0 ? -r : r;
  }
}
