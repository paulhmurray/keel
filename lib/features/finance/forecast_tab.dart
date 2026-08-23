import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../core/finance/variance.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';
import 'finance_form.dart';
import 'money_grid.dart';

/// FORECAST — the PM's monthly rolling forecast (Finance v2). One
/// working snapshot per month, edited in the same grid shape as the
/// budget; submitting freezes it as that month's record. Below the
/// grid: variance vs the approved budget and the forecast-at-completion
/// trend — the "am I drifting?" view.
class ForecastTab extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final List<TimelineWorkPackage> workPackages;
  final String? actor;

  const ForecastTab({
    super.key,
    required this.db,
    required this.projectId,
    required this.workPackages,
    required this.actor,
  });

  @override
  State<ForecastTab> createState() => _ForecastTabState();
}

class _ForecastTabState extends State<ForecastTab> {
  String? _selectedSnapshotId;

  AppDatabase get db => widget.db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ForecastSnapshot>>(
      stream: db.financeDao.watchSnapshots(widget.projectId),
      builder: (context, snapSnap) {
        if (!snapSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final snapshots = snapSnap.data!;
        final selected = snapshots
                .where((s) => s.id == _selectedSnapshotId)
                .firstOrNull ??
            snapshots.where((s) => s.status == 'working').firstOrNull ??
            snapshots.firstOrNull;

        return StreamBuilder<List<ProjectBudget>>(
          stream: db.financeDao.watchBudgets(widget.projectId),
          builder: (context, budgetSnap) {
            final budgets = budgetSnap.data ?? [];
            final approved =
                budgets.where((b) => b.status == 'approved').firstOrNull;
            final currency =
                approved?.currency ?? budgets.firstOrNull?.currency ?? 'AUD';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _controls(context, snapshots, selected, approved),
                const SizedBox(height: 12),
                if (selected == null)
                  Expanded(child: _emptyState(context, snapshots, approved))
                else
                  Expanded(
                    child: _ForecastDetail(
                      key: ValueKey(selected.id),
                      db: db,
                      projectId: widget.projectId,
                      snapshot: selected,
                      approved: approved,
                      currency: currency,
                      workPackages: widget.workPackages,
                      actor: widget.actor,
                      snapshotCount: snapshots.length,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _controls(BuildContext context, List<ForecastSnapshot> snapshots,
      ForecastSnapshot? selected, ProjectBudget? approved) {
    return Row(
      children: [
        if (snapshots.isNotEmpty)
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
                items: snapshots
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text('${s.period}  ·  ${s.status}'),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedSnapshotId = v),
              ),
            ),
          ),
        const Spacer(),
        if (selected != null && selected.status == 'working') ...[
          OutlinedButton.icon(
            onPressed: () async {
              await db.financeDao
                  .submitSnapshot(selected.id, changedBy: widget.actor);
            },
            icon: const Icon(Icons.check, size: 14),
            label: Text('Submit ${selected.period}'),
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton.icon(
          onPressed: () => _newMonth(context, snapshots, approved),
          icon: const Icon(Icons.add, size: 14),
          label: const Text('New Month'),
        ),
        if (selected != null)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                size: 18, color: KColors.textMuted),
            onSelected: (val) async {
              if (val == 'reopen') {
                await db.financeDao
                    .reopenSnapshot(selected.id, changedBy: widget.actor);
              } else if (val == 'delete') {
                await db.financeDao.deleteWorkingSnapshot(selected.id,
                    changedBy: widget.actor);
                setState(() => _selectedSnapshotId = null);
              }
            },
            itemBuilder: (_) => [
              if (selected.status == 'submitted')
                const PopupMenuItem(
                    value: 'reopen', child: Text('Reopen for editing')),
              if (selected.status == 'working')
                const PopupMenuItem(
                    value: 'delete', child: Text('Delete working snapshot')),
            ],
          ),
      ],
    );
  }

  Widget _emptyState(BuildContext context, List<ForecastSnapshot> snapshots,
      ProjectBudget? approved) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_up, size: 40, color: KColors.textMuted),
          const SizedBox(height: 12),
          const Text('No forecast yet.',
              style: TextStyle(color: KColors.textDim)),
          const SizedBox(height: 4),
          Text(
              approved == null
                  ? 'Approve a budget first — the forecast is compared '
                      'against it.'
                  : 'Start this month\'s forecast from the approved budget, '
                      'then update it as the picture changes.',
              style:
                  const TextStyle(color: KColors.textMuted, fontSize: 11)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _newMonth(context, snapshots, approved),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('New Month'),
          ),
        ],
      ),
    );
  }

  Future<void> _newMonth(BuildContext context,
      List<ForecastSnapshot> snapshots, ProjectBudget? approved) async {
    final latest = snapshots.firstOrNull; // sorted period desc
    final defaultPeriod = latest == null
        ? currentPeriodLabel()
        : _nextPeriod(latest.period);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _NewSnapshotDialog(
        defaultPeriod: defaultPeriod,
        hasBudget: approved != null,
        hasPrevious: latest != null,
      ),
    );
    if (result == null) return;
    final (period, source) = result;
    try {
      final id = await db.financeDao.createSnapshot(
        projectId: widget.projectId,
        period: period,
        copyFromBudget: source == 'budget',
        copyFromSnapshotId: source == 'previous' ? latest!.id : null,
        changedBy: widget.actor,
      );
      setState(() => _selectedSnapshotId = id);
    } on StateError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static String _nextPeriod(String period) {
    final parts = period.split('-');
    var y = int.tryParse(parts[0]) ?? DateTime.now().year;
    var m = (parts.length > 1 ? int.tryParse(parts[1]) : null) ?? 1;
    m += 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
    return '$y-${m.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Snapshot detail — grid, variance vs budget, FAC trend
// ---------------------------------------------------------------------------

class _ForecastDetail extends StatelessWidget {
  final AppDatabase db;
  final String projectId;
  final ForecastSnapshot snapshot;
  final ProjectBudget? approved;
  final String currency;
  final List<TimelineWorkPackage> workPackages;
  final String? actor;
  final int snapshotCount;

  const _ForecastDetail({
    super.key,
    required this.db,
    required this.projectId,
    required this.snapshot,
    required this.approved,
    required this.currency,
    required this.workPackages,
    required this.actor,
    required this.snapshotCount,
  });

  bool get isWorking => snapshot.status == 'working';

  @override
  Widget build(BuildContext context) {
    final dao = db.financeDao;
    return StreamBuilder<List<CostCategory>>(
      stream: dao.watchCategories(projectId),
      builder: (context, catSnap) {
        return StreamBuilder<List<ForecastLine>>(
          stream: dao.watchForecastLines(snapshot.id),
          builder: (context, lineSnap) {
            if (!catSnap.hasData || !lineSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final categories = catSnap.data!;
            final lines = lineSnap.data!;
            final forecastTotals = BudgetTotals.fromForecastLines(lines);

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isWorking) _frozenBanner(),
                  MoneyGrid(
                    cells: dao.watchForecastLines(snapshot.id).map(
                        (ls) => [
                              for (final l in ls)
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
                    currency: currency,
                    readOnly: !isWorking,
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
                        dao.upsertForecastLine(
                      id: existing?.id ?? const Uuid().v4(),
                      projectId: projectId,
                      snapshotId: snapshot.id,
                      costCategoryId: categoryId,
                      workstreamId: existing?.workstreamId ?? workstreamId,
                      financialYear: columnKey,
                      amountMinor: amountMinor,
                      notes: existing?.notes,
                      changedBy: actor,
                    ),
                    onDelete: (cells) async {
                      for (final c in cells) {
                        await dao.deleteForecastLine(c.id,
                            changedBy: actor);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  if (approved != null)
                    _VarianceSection(
                      db: db,
                      approved: approved!,
                      forecastTotals: forecastTotals,
                      categories: categories,
                      currency: currency,
                      actor: actor,
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                          'No approved budget — approve one on the Budget '
                          'tab to see variance.',
                          style: TextStyle(
                              color: KColors.textMuted, fontSize: 11)),
                    ),
                  const SizedBox(height: 16),
                  _TrendSection(
                    db: db,
                    projectId: projectId,
                    approved: approved,
                    currency: currency,
                    // Recompute when the visible lines or snapshot set
                    // change.
                    refreshKey:
                        '$snapshotCount|${snapshot.id}|${forecastTotals.totalMinor}',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _frozenBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KColors.blueDim,
        border: Border.all(color: KColors.blue, width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.ac_unit, size: 13, color: KColors.blue),
          const SizedBox(width: 8),
          Text(
            '${snapshot.period} was submitted — frozen monthly record. '
            'Reopen from the menu if it needs correcting.',
            style: const TextStyle(color: KColors.blue, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Variance vs approved budget
// ---------------------------------------------------------------------------

class _VarianceSection extends StatelessWidget {
  final AppDatabase db;
  final ProjectBudget approved;
  final BudgetTotals forecastTotals;
  final List<CostCategory> categories;
  final String currency;
  final String? actor;

  const _VarianceSection({
    required this.db,
    required this.approved,
    required this.forecastTotals,
    required this.categories,
    required this.currency,
    required this.actor,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BudgetLine>>(
      stream: db.financeDao.watchLines(approved.id),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final budgetTotals = BudgetTotals.fromLines(snap.data!);
        final rows = computeVariance(budgetTotals, forecastTotals,
            categories.map((c) => c.id).toList());
        final catNames = {for (final c in categories) c.id: c.name};
        final total = rows.last;
        final tolBp = approved.varianceToleranceBp;
        final breach =
            total.varianceBp != null && total.varianceBp!.abs() > tolBp;

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
                  const Text('VARIANCE VS APPROVED BUDGET',
                      style: TextStyle(
                          color: KColors.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                  const Spacer(),
                  InkWell(
                    onTap: () => _editTolerance(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            breach ? KColors.redDim : KColors.surface2,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'tolerance ±${Money.formatBp(tolBp).replaceAll('+', '')}',
                            style: TextStyle(
                                color: breach
                                    ? KColors.red
                                    : KColors.textDim,
                                fontSize: 10),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.edit_outlined,
                              size: 10,
                              color:
                                  breach ? KColors.red : KColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _headerRow(),
              for (final r in rows.take(rows.length - 1))
                _row(catNames[r.key] ?? 'Unknown', r, false),
              const Divider(height: 12, color: KColors.border),
              _row('TOTAL — FORECAST AT COMPLETION', total, true,
                  breach: breach),
            ],
          ),
        );
      },
    );
  }

  Widget _headerRow() {
    const style = TextStyle(
        color: KColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4);
    return const Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: SizedBox()),
          SizedBox(
              width: 120,
              child:
                  Text('BUDGET', textAlign: TextAlign.right, style: style)),
          SizedBox(
              width: 120,
              child: Text('FORECAST',
                  textAlign: TextAlign.right, style: style)),
          SizedBox(
              width: 120,
              child: Text('VARIANCE',
                  textAlign: TextAlign.right, style: style)),
          SizedBox(
              width: 70,
              child: Text('VAR %', textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }

  Widget _row(String label, VarianceRow r, bool emphasize,
      {bool breach = false}) {
    final varColor = r.varianceMinor > 0
        ? (breach ? KColors.red : KColors.amber)
        : r.varianceMinor < 0
            ? KColors.phosphor
            : KColors.textDim;
    final base = TextStyle(
      color: emphasize ? KColors.text : KColors.textDim,
      fontSize: emphasize ? 12 : 11,
      fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(label, style: base, overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 120,
            child: Text(Money.formatMinorCompact(r.budgetMinor, currency),
                textAlign: TextAlign.right, style: base),
          ),
          SizedBox(
            width: 120,
            child: Text(
                Money.formatMinorCompact(r.forecastMinor, currency),
                textAlign: TextAlign.right,
                style: base),
          ),
          SizedBox(
            width: 120,
            child: Text(
              '${r.varianceMinor > 0 ? '+' : ''}${Money.formatMinorCompact(r.varianceMinor, currency)}',
              textAlign: TextAlign.right,
              style: base.copyWith(color: varColor),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              Money.formatBp(r.varianceBp),
              textAlign: TextAlign.right,
              style: base.copyWith(color: varColor),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTolerance(BuildContext context) async {
    final ctrl = TextEditingController(
        text: (approved.varianceToleranceBp / 100).toStringAsFixed(1));
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Variance Tolerance'),
        content: SizedBox(
          width: 280,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Tolerance (± %)',
              hintText: 'e.g. 5.0',
              helperText:
                  'Forecast drift past this raises a programme pressure.',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final pct = double.tryParse(ctrl.text.trim());
              if (pct == null || pct <= 0) return;
              Navigator.of(ctx).pop((pct * 100).round());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await db.financeDao
          .setVarianceTolerance(approved.id, result, changedBy: actor);
    }
  }
}

// ---------------------------------------------------------------------------
// Forecast-at-completion trend
// ---------------------------------------------------------------------------

class _TrendSection extends StatelessWidget {
  final AppDatabase db;
  final String projectId;
  final ProjectBudget? approved;
  final String currency;
  final String refreshKey;

  const _TrendSection({
    required this.db,
    required this.projectId,
    required this.approved,
    required this.currency,
    required this.refreshKey,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<
        (List<({String period, int totalMinor, bool submitted})>, int?)>(
      key: ValueKey(refreshKey),
      future: () async {
        final trend = await db.financeDao.getForecastTrend(projectId);
        int? budgetTotal;
        if (approved != null) {
          budgetTotal =
              (await db.financeDao.getTotals(approved!.id)).totalMinor;
        }
        return (trend, budgetTotal);
      }(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final (trend, budgetTotal) = snap.data!;
        if (trend.length < 2) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
                'The forecast-at-completion trend appears once two or '
                'more months exist.',
                style: TextStyle(color: KColors.textMuted, fontSize: 11)),
          );
        }
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
              const Text('FORECAST AT COMPLETION — TREND',
                  style: TextStyle(
                      color: KColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendPainter(
                    trend: trend,
                    budgetTotal: budgetTotal,
                    toleranceBp: approved?.varianceToleranceBp,
                    currency: currency,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<({String period, int totalMinor, bool submitted})> trend;
  final int? budgetTotal;
  final int? toleranceBp;
  final String currency;

  _TrendPainter({
    required this.trend,
    required this.budgetTotal,
    required this.toleranceBp,
    required this.currency,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 8.0, rightPad = 80.0, topPad = 12.0, bottomPad = 22.0;
    final plotW = size.width - leftPad - rightPad;
    final plotH = size.height - topPad - bottomPad;
    if (plotW <= 0 || plotH <= 0) return;

    // Y-range spans the trend, the budget line, and the tolerance band.
    final values = <int>[
      for (final t in trend) t.totalMinor,
      ?budgetTotal,
      if (budgetTotal != null && toleranceBp != null) ...[
        budgetTotal! + budgetTotal! * toleranceBp! ~/ 10000,
        budgetTotal! - budgetTotal! * toleranceBp! ~/ 10000,
      ],
    ];
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    final span = hi - lo;
    lo -= span ~/ 10;
    hi += span ~/ 10;

    double y(int v) => topPad + plotH * (1 - (v - lo) / (hi - lo));
    double x(int i) => trend.length == 1
        ? leftPad + plotW / 2
        : leftPad + plotW * i / (trend.length - 1);

    // Tolerance band + budget line.
    if (budgetTotal != null) {
      if (toleranceBp != null) {
        final bandTop = y(budgetTotal! + budgetTotal! * toleranceBp! ~/ 10000);
        final bandBot = y(budgetTotal! - budgetTotal! * toleranceBp! ~/ 10000);
        canvas.drawRect(
          Rect.fromLTRB(leftPad, bandTop, leftPad + plotW, bandBot),
          Paint()..color = KColors.amberDim.withValues(alpha: 0.45),
        );
      }
      final budgetY = y(budgetTotal!);
      final dash = Paint()
        ..color = KColors.amber
        ..strokeWidth = 1;
      for (var dx = leftPad; dx < leftPad + plotW; dx += 8) {
        canvas.drawLine(
            Offset(dx, budgetY), Offset(dx + 4, budgetY), dash);
      }
      _label(canvas, 'budget ${Money.formatMinorCompact(budgetTotal!, currency)}',
          Offset(leftPad + plotW + 6, budgetY - 6), KColors.amber);
    }

    // FAC polyline + points.
    final line = Paint()
      ..color = KColors.phosphor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < trend.length; i++) {
      final p = Offset(x(i), y(trend[i].totalMinor));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, line);
    for (var i = 0; i < trend.length; i++) {
      final t = trend[i];
      final p = Offset(x(i), y(t.totalMinor));
      canvas.drawCircle(
          p,
          3,
          Paint()
            ..color = t.submitted ? KColors.phosphor : KColors.surface
            ..style = PaintingStyle.fill);
      if (!t.submitted) {
        canvas.drawCircle(
            p,
            3,
            Paint()
              ..color = KColors.phosphor
              ..strokeWidth = 1.2
              ..style = PaintingStyle.stroke);
      }
    }
    final last = trend.last;
    _label(
        canvas,
        Money.formatMinorCompact(last.totalMinor, currency),
        Offset(leftPad + plotW + 6, y(last.totalMinor) + 2),
        KColors.phosphor);

    // X labels: first, last, and middle when room allows.
    _label(canvas, trend.first.period,
        Offset(leftPad, size.height - 14), KColors.textMuted);
    final lastLabelX = leftPad + plotW - 44;
    _label(canvas, trend.last.period, Offset(lastLabelX, size.height - 14),
        KColors.textMuted);
  }

  void _label(Canvas canvas, String text, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: text, style: TextStyle(color: color, fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.trend != trend ||
      old.budgetTotal != budgetTotal ||
      old.toleranceBp != toleranceBp;
}

// ---------------------------------------------------------------------------
// New snapshot dialog
// ---------------------------------------------------------------------------

class _NewSnapshotDialog extends StatefulWidget {
  final String defaultPeriod;
  final bool hasBudget;
  final bool hasPrevious;

  const _NewSnapshotDialog({
    required this.defaultPeriod,
    required this.hasBudget,
    required this.hasPrevious,
  });

  @override
  State<_NewSnapshotDialog> createState() => _NewSnapshotDialogState();
}

class _NewSnapshotDialogState extends State<_NewSnapshotDialog> {
  late final TextEditingController _periodCtrl =
      TextEditingController(text: widget.defaultPeriod);
  late String _source = widget.hasPrevious
      ? 'previous'
      : widget.hasBudget
          ? 'budget'
          : 'empty';

  @override
  void dispose() {
    _periodCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Forecast Month'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _periodCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Month', hintText: 'YYYY-MM'),
            ),
            const SizedBox(height: 12),
            const Text('Start from',
                style: TextStyle(color: KColors.textDim, fontSize: 11)),
            if (widget.hasPrevious)
              _sourceOption('previous', 'Last month\'s forecast'),
            if (widget.hasBudget)
              _sourceOption('budget', 'Approved budget'),
            _sourceOption('empty', 'Empty'),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final period = _periodCtrl.text.trim();
            if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(period)) return;
            Navigator.of(context).pop((period, _source));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  Widget _sourceOption(String value, String label) {
    final selected = _source == value;
    return InkWell(
      onTap: () => setState(() => _source = value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 15,
              color: selected ? KColors.amber : KColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
