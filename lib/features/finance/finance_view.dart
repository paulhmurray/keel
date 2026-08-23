import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';
import 'actuals_tab.dart';
import 'budget_grid.dart';
import 'finance_form.dart';
import 'forecast_tab.dart';

/// FINANCE — Project Finance v1+v2.
/// BUDGET: versioned baselines (draft → approved → superseded) in a
/// category × FY grid, with the financial audit trail.
/// FORECAST: monthly rolling snapshots vs the approved budget —
/// variance and the forecast-at-completion trend.
/// ACTUALS: manual monthly spend entry (CSV import lands in v3).
class FinanceView extends StatefulWidget {
  final bool triggerNew;

  const FinanceView({super.key, this.triggerNew = false});

  @override
  State<FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends State<FinanceView> {
  String? _selectedBudgetId;
  List<TimelineWorkPackage> _workPackages = [];
  int _tab = 0; // 0 = budget, 1 = forecast, 2 = actuals

  /// The project the view is currently initialised for. Seeding and
  /// workstream loading re-run whenever the user switches project WHILE
  /// this view is mounted — init-once left a freshly-switched project
  /// with no cost categories and therefore no rows to enter lines into.
  String? _initedProjectId;
  bool _triggerNewConsumed = false;

  void _ensureInitedFor(String projectId) {
    if (_initedProjectId == projectId) return;
    _initedProjectId = projectId;
    _selectedBudgetId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final db = context.read<AppDatabase>();
      await db.financeDao
          .seedDefaultCategories(projectId, changedBy: financeActor(context));
      final wps = await db.programmeGanttDao.getWorkPackages(projectId);
      if (mounted) setState(() => _workPackages = wps);
      if (widget.triggerNew && !_triggerNewConsumed && mounted) {
        _triggerNewConsumed = true;
        await _triggerNewLine(projectId);
      }
    });
  }

  /// Leader-key "new line": opens the line dialog on the current draft,
  /// or the budget dialog when the project has no draft to add to.
  Future<void> _triggerNewLine(String projectId) async {
    final db = context.read<AppDatabase>();
    final budgets = await db.financeDao.getBudgets(projectId);
    final draft = budgets.where((b) => b.status == 'draft').firstOrNull;
    if (!mounted) return;
    if (draft == null) {
      await showDialog(
        context: context,
        builder: (_) => BudgetFormDialog(projectId: projectId, db: db),
      );
    } else {
      final cats = await db.financeDao.getCategories(projectId);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => BudgetLineFormDialog(
          projectId: projectId,
          db: db,
          budget: draft,
          categories: cats,
          workPackages: _workPackages,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(
          child: Text('Select a project to view finance.',
              style: TextStyle(color: KColors.textDim)));
    }
    _ensureInitedFor(projectId);
    final db = context.read<AppDatabase>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_outlined,
                  color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Text('FINANCE',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(width: 24),
              _TabChip(
                  label: 'BUDGET',
                  selected: _tab == 0,
                  onTap: () => setState(() => _tab = 0)),
              _TabChip(
                  label: 'FORECAST',
                  selected: _tab == 1,
                  onTap: () => setState(() => _tab = 1)),
              _TabChip(
                  label: 'ACTUALS',
                  selected: _tab == 2,
                  onTap: () => setState(() => _tab = 2)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: switch (_tab) {
              1 => ForecastTab(
                  db: db,
                  projectId: projectId,
                  workPackages: _workPackages,
                  actor: financeActor(context),
                ),
              2 => ActualsTab(
                  db: db,
                  projectId: projectId,
                  workPackages: _workPackages,
                  actor: financeActor(context),
                ),
              _ => _budgetTab(db, projectId),
            },
          ),
        ],
      ),
    );
  }

  Widget _budgetTab(AppDatabase db, String projectId) {
    return StreamBuilder<List<ProjectBudget>>(
      stream: db.financeDao.watchBudgets(projectId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final budgets = snap.data!;
        final selected = budgets
                .where((b) => b.id == _selectedBudgetId)
                .firstOrNull ??
            budgets.where((b) => b.status == 'approved').firstOrNull ??
            budgets.firstOrNull;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, db, projectId, budgets, selected),
            const SizedBox(height: 12),
            if (selected == null)
              Expanded(child: _emptyState(context, db, projectId))
            else
              Expanded(
                child: _BudgetDetail(
                  key: ValueKey(selected.id),
                  db: db,
                  projectId: projectId,
                  budget: selected,
                  workPackages: _workPackages,
                  onDraftCreated: (id) =>
                      setState(() => _selectedBudgetId = id),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, AppDatabase db, String projectId,
      List<ProjectBudget> budgets, ProjectBudget? selected) {
    return Row(
      children: [
        if (budgets.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: KColors.surface,
              border: Border.all(color: KColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected?.id,
                dropdownColor: KColors.surface2,
                style: const TextStyle(color: KColors.text, fontSize: 12),
                items: budgets
                    .map((b) => DropdownMenuItem(
                          value: b.id,
                          child: Text('${b.name}  ·  ${b.status}'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedBudgetId = v),
              ),
            ),
          ),
        const Spacer(),
        if (selected != null && selected.status == 'draft') ...[
          OutlinedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => ApproveBudgetDialog(
                  projectId: projectId, db: db, budget: selected),
            ),
            icon: const Icon(Icons.check, size: 14),
            label: const Text('Approve…'),
          ),
          const SizedBox(width: 8),
        ],
        if (selected != null && selected.status != 'draft') ...[
          OutlinedButton.icon(
            onPressed: () async {
              final newId = await db.financeDao.createDraftFrom(selected.id,
                  changedBy: financeActor(context));
              setState(() => _selectedBudgetId = newId);
            },
            icon: const Icon(Icons.copy_outlined, size: 14),
            label: const Text('New Draft From This'),
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => BudgetFormDialog(projectId: projectId, db: db),
          ),
          icon: const Icon(Icons.add, size: 14),
          label: const Text('New Budget'),
        ),
        if (selected != null && selected.status == 'draft')
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                size: 18, color: KColors.textMuted),
            onSelected: (val) async {
              if (val == 'edit') {
                await showDialog(
                  context: context,
                  builder: (_) => BudgetFormDialog(
                      projectId: projectId, db: db, budget: selected),
                );
              } else if (val == 'delete') {
                await db.financeDao.deleteDraftBudget(selected.id,
                    changedBy: financeActor(context));
                setState(() => _selectedBudgetId = null);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit details')),
              PopupMenuItem(value: 'delete', child: Text('Delete draft')),
            ],
          ),
      ],
    );
  }

  Widget _emptyState(BuildContext context, AppDatabase db, String projectId) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance_outlined,
              size: 40, color: KColors.textMuted),
          const SizedBox(height: 12),
          const Text('No budget yet.',
              style: TextStyle(color: KColors.textDim)),
          const SizedBox(height: 4),
          const Text(
              'Create a draft, build the lines, then approve it as the '
              'baseline.',
              style: TextStyle(color: KColors.textMuted, fontSize: 11)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => BudgetFormDialog(projectId: projectId, db: db),
            ),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('New Budget'),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? KColors.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? KColors.amber : KColors.textMuted,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget detail — summary bar, category × FY grid, audit trail
// ---------------------------------------------------------------------------

class _BudgetDetail extends StatelessWidget {
  final AppDatabase db;
  final String projectId;
  final ProjectBudget budget;
  final List<TimelineWorkPackage> workPackages;
  final ValueChanged<String> onDraftCreated;

  const _BudgetDetail({
    super.key,
    required this.db,
    required this.projectId,
    required this.budget,
    required this.workPackages,
    required this.onDraftCreated,
  });

  bool get isDraft => budget.status == 'draft';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CostCategory>>(
      stream: db.financeDao.watchCategories(projectId),
      builder: (context, catSnap) {
        return StreamBuilder<List<BudgetLine>>(
          stream: db.financeDao.watchLines(budget.id),
          builder: (context, lineSnap) {
            if (!catSnap.hasData || !lineSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final categories = catSnap.data!;
            final lines = lineSnap.data!;
            final totals = BudgetTotals.fromLines(lines);

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryBar(context, totals),
                  const SizedBox(height: 12),
                  if (!isDraft) _readOnlyBanner(),
                  BudgetGrid(
                    db: db,
                    projectId: projectId,
                    budget: budget,
                    categories: categories,
                    workPackages: workPackages,
                    actor: financeActor(context),
                    readOnly: !isDraft,
                    onReadOnlyTap: () => _offerDraft(context),
                  ),
                  const SizedBox(height: 20),
                  _AuditTrailPanel(
                      db: db, projectId: projectId, currency: budget.currency),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// A cell tap on a read-only budget offers the edit path instead of
  /// dead silence.
  void _offerDraft(BuildContext context) {
    final actor = financeActor(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('"${budget.name}" is ${budget.status} — read-only.'),
      action: SnackBarAction(
        label: 'NEW DRAFT',
        onPressed: () async {
          final id = await db.financeDao
              .createDraftFrom(budget.id, changedBy: actor);
          onDraftCreated(id);
        },
      ),
    ));
  }

  Widget _readOnlyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.amberDim,
        border: Border.all(color: KColors.amber, width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 13, color: KColors.amber),
          const SizedBox(width: 8),
          Text(
            budget.status == 'approved'
                ? 'This is the approved budget — read-only. '
                    'Use "New Draft From This" to propose changes.'
                : 'This budget was superseded — read-only history.',
            style: const TextStyle(color: KColors.amber, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _summaryBar(BuildContext context, BudgetTotals totals) {
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
                Row(
                  children: [
                    Flexible(
                      child: Text(budget.name,
                          style: const TextStyle(
                              color: KColors.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    _statusChip(budget.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    budget.currency,
                    if (budget.fundingSource != null &&
                        budget.fundingSource!.isNotEmpty)
                      budget.fundingSource!,
                    if (budget.status == 'approved' &&
                        budget.approvedAt != null)
                      'approved ${DateFormat('d MMM yyyy').format(budget.approvedAt!)}'
                          '${budget.approvedBy == null ? '' : ' by ${budget.approvedBy}'}',
                  ].join(' · '),
                  style:
                      const TextStyle(color: KColors.textDim, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('TOTAL',
                  style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 0.5)),
              Text(
                Money.formatMinorCompact(totals.totalMinor, budget.currency),
                style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final (color, dim) = switch (status) {
      'approved' => (KColors.phosphor, KColors.phosDim),
      'draft' => (KColors.blue, KColors.blueDim),
      _ => (KColors.textMuted, KColors.surface2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: dim,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(status.toUpperCase(),
          style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4)),
    );
  }

}

// ---------------------------------------------------------------------------
// Audit trail
// ---------------------------------------------------------------------------

class _AuditTrailPanel extends StatelessWidget {
  final AppDatabase db;
  final String projectId;
  final String currency;

  const _AuditTrailPanel(
      {required this.db, required this.projectId, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('AUDIT TRAIL',
              style: TextStyle(
                  color: KColors.textDim,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
          leading: const Icon(Icons.history,
              size: 16, color: KColors.textMuted),
          childrenPadding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          children: [
            StreamBuilder<List<FinancialAuditLogData>>(
              stream: db.financeDao.watchAuditLog(projectId),
              builder: (context, snap) {
                final entries = snap.data ?? [];
                if (entries.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('No changes recorded yet.',
                        style: TextStyle(
                            color: KColors.textMuted, fontSize: 11)),
                  );
                }
                return Column(
                  children:
                      entries.take(100).map(_entryRow).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _entryRow(FinancialAuditLogData e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              DateFormat('d MMM yy HH:mm').format(e.changedAt),
              style: const TextStyle(color: KColors.textMuted, fontSize: 10),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(e.entityType,
                style:
                    const TextStyle(color: KColors.textDim, fontSize: 10)),
          ),
          Expanded(
            child: Text(_describe(e),
                style: const TextStyle(color: KColors.text, fontSize: 11)),
          ),
          if (e.changedBy != null)
            Text(e.changedBy!,
                style:
                    const TextStyle(color: KColors.textDim, fontSize: 10)),
        ],
      ),
    );
  }

  String _describe(FinancialAuditLogData e) {
    String amount(String? v) {
      final minor = v == null ? null : int.tryParse(v);
      return minor == null ? (v ?? '—') : Money.formatMinorCompact(minor, currency);
    }

    switch (e.field) {
      case 'created':
        return 'created'
            '${e.entityType == 'BudgetLine' ? ' at ${amount(e.newValue)}' : e.newValue == null ? '' : ' "${e.newValue}"'}';
      case 'deleted':
        return 'deleted'
            '${e.entityType == 'BudgetLine' ? ' (was ${amount(e.oldValue)})' : e.oldValue == null ? '' : ' "${e.oldValue}"'}';
      case 'amountMinor':
        return 'amount ${amount(e.oldValue)} → ${amount(e.newValue)}';
      default:
        return '${e.field} ${e.oldValue ?? '—'} → ${e.newValue ?? '—'}';
    }
  }
}
