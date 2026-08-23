import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import 'finance_form.dart';
import 'money_grid.dart';

/// Budget-lines adapter over the generic [MoneyGrid]: FY columns,
/// draft-only editing, secondary-tap opens the full line dialog.
class BudgetGrid extends StatelessWidget {
  final AppDatabase db;
  final String projectId;
  final ProjectBudget budget;
  final List<CostCategory> categories;
  final List<TimelineWorkPackage> workPackages;
  final String? actor;
  final bool readOnly;
  final VoidCallback? onReadOnlyTap;

  const BudgetGrid({
    super.key,
    required this.db,
    required this.projectId,
    required this.budget,
    required this.categories,
    required this.workPackages,
    required this.actor,
    required this.readOnly,
    this.onReadOnlyTap,
  });

  @override
  Widget build(BuildContext context) {
    final dao = db.financeDao;
    return MoneyGrid(
      cells: dao.watchLines(budget.id).map((lines) => [
            for (final l in lines)
              MoneyCell(
                id: l.id,
                categoryId: l.costCategoryId,
                workstreamId: l.workstreamId,
                columnKey: l.financialYear,
                amountMinor: l.amountMinor,
                notes: l.notes,
              ),
          ]),
      categories: categories,
      workPackages: workPackages,
      currency: budget.currency,
      readOnly: readOnly,
      columnNoun: 'Financial Year',
      columnHint: 'e.g. FY28',
      defaultColumnKey: defaultFyLabel(),
      onCommit: ({
        required existing,
        required categoryId,
        required workstreamId,
        required columnKey,
        required amountMinor,
      }) =>
          dao.upsertLine(
        id: existing?.id ?? const Uuid().v4(),
        projectId: projectId,
        budgetId: budget.id,
        costCategoryId: categoryId,
        workstreamId: existing?.workstreamId ?? workstreamId,
        financialYear: columnKey,
        amountMinor: amountMinor,
        notes: existing?.notes,
        changedBy: actor,
      ),
      onDelete: (cells) async {
        for (final c in cells) {
          await dao.deleteLine(c.id, changedBy: actor);
        }
      },
      onDetail: (categoryId, workstreamId, columnKey, cell) async {
        final line = cell == null
            ? null
            : (await dao.getLines(budget.id))
                .where((l) => l.id == cell.id)
                .firstOrNull;
        if (!context.mounted) return;
        await showDialog(
          context: context,
          builder: (_) => BudgetLineFormDialog(
            projectId: projectId,
            db: db,
            budget: budget,
            categories: categories,
            workPackages: workPackages,
            line: line,
            initialCategoryId: categoryId,
            initialFinancialYear: columnKey,
            initialWorkstreamId: workstreamId,
          ),
        );
      },
      onReadOnlyTap: onReadOnlyTap,
    );
  }
}
