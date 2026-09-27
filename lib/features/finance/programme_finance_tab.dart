import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/finance/programme_rollup.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';

/// Programme-side finance roll-up over the cascaded copies of linked
/// projects' finance. Two lenses: BY PROJECT (one row per project,
/// portfolio totals, drill-in to the read-only lines) and BY CATEGORY
/// (categories inherited and grouped by name, merged where two projects
/// name the same thing differently).
enum ProgrammeFinanceLens { byProject, byCategory }

class ProgrammeFinanceTab extends StatefulWidget {
  final AppDatabase db;
  final String programmeId;
  final ProgrammeFinanceLens lens;
  final String? actor;

  const ProgrammeFinanceTab({
    super.key,
    required this.db,
    required this.programmeId,
    required this.lens,
    this.actor,
  });

  @override
  State<ProgrammeFinanceTab> createState() => _ProgrammeFinanceTabState();
}

class _Loaded {
  final ProgrammeFinance finance;
  final List<CostCategory> categories;
  final List<CategoryMerge> merges;
  final List<BudgetLine> budgetLines;
  final List<ForecastLine> forecastLines;
  final List<ActualLine> actuals;
  const _Loaded(this.finance, this.categories, this.merges, this.budgetLines,
      this.forecastLines, this.actuals);
}

class _ProgrammeFinanceTabState extends State<ProgrammeFinanceTab> {
  final Set<String> _expanded = {};

  Future<_Loaded> _load() async {
    final dao = widget.db.financeDao;
    final pid = widget.programmeId;
    final categories = await dao.getCascadedCategories(pid);
    final merges = await dao.getMerges(pid);
    final budgetLines = await dao.getCascadedBudgetLines(pid);
    final forecastLines = await dao.getCascadedForecastLines(pid);
    final actuals = await dao.getCascadedActuals(pid);
    final finance = computeProgrammeFinance(
      categories: categories,
      budgets: await dao.getCascadedBudgets(pid),
      budgetLines: budgetLines,
      snapshots: await dao.getCascadedSnapshots(pid),
      forecastLines: forecastLines,
      actuals: actuals,
      merges: merges,
    );
    return _Loaded(
        finance, categories, merges, budgetLines, forecastLines, actuals);
  }

  @override
  Widget build(BuildContext context) {
    // Any write (a pull landing, a merge) re-reads the roll-up.
    return StreamBuilder<void>(
      stream: widget.db.watchAnyChange(),
      builder: (context, _) => FutureBuilder<_Loaded>(
        future: _load(),
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (data.finance.isEmpty) return _empty();
          return widget.lens == ProgrammeFinanceLens.byProject
              ? _byProject(context, data)
              : _byCategory(context, data);
        },
      ),
    );
  }

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No finance has arrived from linked projects yet.\n'
            'A project shares its approved budget, submitted forecasts and '
            'actuals over a full-detail link.',
            textAlign: TextAlign.center,
            style: TextStyle(color: KColors.textDim, fontSize: 12, height: 1.4),
          ),
        ),
      );

  String _nameFor(BuildContext context, String id) {
    final projects = context.read<ProjectProvider>().projects;
    return projects
            .cast<Project?>()
            .firstWhere((p) => p?.id == id, orElse: () => null)
            ?.name ??
        'Linked project';
  }

  // ── BY PROJECT ────────────────────────────────────────────────────────

  Widget _byProject(BuildContext context, _Loaded data) {
    final f = data.finance;
    final cur = f.currency ?? 'AUD';
    final rows = f.projects.toList()
      ..sort((a, b) => _nameFor(context, a.sourceId)
          .toLowerCase()
          .compareTo(_nameFor(context, b.sourceId).toLowerCase()));
    return ListView(
      children: [
        _Totals(finance: f),
        const SizedBox(height: 12),
        _tableHeader(const [
          ('PROJECT', 3),
          ('BUDGET', 2),
          ('FORECAST', 2),
          ('ACTUALS', 2),
          ('VARIANCE', 2),
        ]),
        for (final r in rows) ...[
          _ProjectRow(
            name: _nameFor(context, r.sourceId),
            row: r,
            currency: cur,
            expanded: _expanded.contains(r.sourceId),
            onTap: () => setState(() {
              if (!_expanded.remove(r.sourceId)) _expanded.add(r.sourceId);
            }),
          ),
          if (_expanded.contains(r.sourceId))
            _ProjectDetail(row: r, data: data, currency: r.currency ?? cur),
        ],
      ],
    );
  }

  // ── BY CATEGORY ───────────────────────────────────────────────────────

  Widget _byCategory(BuildContext context, _Loaded data) {
    final f = data.finance;
    final cur = f.currency ?? 'AUD';
    final mergedIds = {for (final m in data.merges) m.sourceCategoryId};
    final buckets = rollupCategories(data.categories, data.merges);
    return ListView(
      children: [
        Row(children: [
          const Expanded(
            child: Text(
              'Categories arrive from each project and roll up by name. '
              'Merge two rows when they mean the same thing.',
              style: TextStyle(color: KColors.textDim, fontSize: 11),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: buckets.length < 2
                ? null
                : () => _showMerge(context, buckets),
            icon: const Icon(Icons.call_merge, size: 14),
            label: const Text('Merge…'),
          ),
        ]),
        const SizedBox(height: 12),
        _tableHeader([
          ('CATEGORY', 3),
          for (final fy in f.financialYears) (fy.toUpperCase(), 1),
          ('BUDGET', 2),
          ('FORECAST', 2),
          ('ACTUALS', 2),
        ]),
        for (var i = 0; i < f.categories.length; i++)
          _CategoryRow(
            row: f.categories[i],
            bucket: buckets[i],
            financialYears: f.financialYears,
            currency: cur,
            hasMerges: buckets[i].categoryIds.any(mergedIds.contains),
            projectNames: {
              for (final c in data.categories)
                if (c.sourceProjectId != null)
                  c.id: _nameFor(context, c.sourceProjectId!)
            },
            categoryNames: {for (final c in data.categories) c.id: c.name},
            onUnmerge: () async {
              for (final id in buckets[i].categoryIds) {
                if (mergedIds.contains(id)) {
                  await widget.db.financeDao.unmergeCategory(
                      widget.programmeId, id,
                      changedBy: widget.actor);
                }
              }
            },
          ),
      ],
    );
  }

  Future<void> _showMerge(
      BuildContext context, List<CategoryBucket> buckets) async {
    final result = await showDialog<(Set<int>, String)>(
      context: context,
      builder: (_) => _MergeDialog(buckets: buckets),
    );
    if (result == null || !mounted) return;
    final (picked, target) = result;
    final ids = <String>[
      for (final i in picked) ...buckets[i].categoryIds,
    ];
    await widget.db.financeDao.mergeCategories(
      programmeId: widget.programmeId,
      sourceCategoryIds: ids,
      targetName: target,
      changedBy: widget.actor,
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────

Widget _tableHeader(List<(String, int)> cols) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Row(children: [
        for (var i = 0; i < cols.length; i++)
          Expanded(
            flex: cols[i].$2,
            child: Text(cols[i].$1,
                textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                style: const TextStyle(
                    color: KColors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
          ),
      ]),
    );

TextStyle _money([Color color = KColors.text, bool bold = false]) => TextStyle(
      color: color,
      fontSize: 12,
      fontFamily: 'monospace',
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );

Color _varianceColor(int? bp, int tol) => bp == null
    ? KColors.textMuted
    : bp.abs() > tol
        ? KColors.red
        : bp > 0
            ? KColors.amber
            : KColors.phosphor;

class _Totals extends StatelessWidget {
  final ProgrammeFinance finance;
  const _Totals({required this.finance});

  @override
  Widget build(BuildContext context) {
    final f = finance;
    final cur = f.currency ?? 'AUD';
    final breaches = f.breaches.length;
    final mismatches = f.projects.where((p) => p.currencyMismatch).length;
    Widget stat(String label, String value, {Color color = KColors.text}) =>
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    color: KColors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
            const SizedBox(height: 3),
            Text(value, style: _money(color, true).copyWith(fontSize: 15)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('PORTFOLIO · ${f.projects.length} '
              '${f.projects.length == 1 ? 'PROJECT' : 'PROJECTS'}',
              style: const TextStyle(
                  color: KColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          const Spacer(),
          if (breaches > 0)
            Text('$breaches beyond tolerance',
                style: const TextStyle(
                    color: KColors.red, fontSize: 11, fontWeight: FontWeight.w700)),
          if (mismatches > 0) ...[
            const SizedBox(width: 12),
            Text('$mismatches in another currency (excluded)',
                style: const TextStyle(color: KColors.amber, fontSize: 11)),
          ],
        ]),
        const SizedBox(height: 10),
        Row(children: [
          stat('BUDGET', Money.formatMinorCompact(f.budgetMinor, cur)),
          stat('FORECAST', Money.formatMinorCompact(f.forecastMinor, cur)),
          stat('ACTUALS', Money.formatMinorCompact(f.actualsMinor, cur)),
          stat('VARIANCE', Money.formatBp(f.varianceBp),
              color: _varianceColor(f.varianceBp, 500)),
        ]),
      ]),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  final String name;
  final ProjectFinanceRow row;
  final String currency;
  final bool expanded;
  final VoidCallback onTap;
  const _ProjectRow({
    required this.name,
    required this.row,
    required this.currency,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cur = row.currency ?? currency;
    Widget cell(String text, {Color color = KColors.text, String? sub}) =>
        Expanded(
          flex: 2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(text, style: _money(color)),
            if (sub != null)
              Text(sub,
                  style: const TextStyle(color: KColors.textMuted, fontSize: 9.5)),
          ]),
        );
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: KColors.border.withValues(alpha: 0.6))),
        ),
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Row(children: [
              Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14, color: KColors.textDim),
              const SizedBox(width: 6),
              Flexible(
                child: Text(name,
                    style: const TextStyle(
                        color: KColors.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              if (row.breach) ...[
                const SizedBox(width: 6),
                const Tooltip(
                  message: 'Forecast beyond this project\'s tolerance',
                  child: Icon(Icons.warning_amber_rounded,
                      size: 13, color: KColors.red),
                ),
              ],
              if (row.currencyMismatch) ...[
                const SizedBox(width: 6),
                Text(cur,
                    style: const TextStyle(color: KColors.amber, fontSize: 9.5)),
              ],
            ]),
          ),
          cell(
            row.budget == null ? '—' : Money.formatMinorCompact(row.budgetMinor, cur),
            sub: row.budget?.name,
          ),
          cell(
            row.forecastMinor == null
                ? 'no forecast'
                : Money.formatMinorCompact(row.forecastMinor, cur),
            color: row.forecastMinor == null ? KColors.textMuted : KColors.text,
            sub: row.latestSnapshot?.period,
          ),
          cell(Money.formatMinorCompact(row.actualsMinor, cur)),
          cell(
            Money.formatBp(row.varianceBp),
            color: _varianceColor(row.varianceBp, row.toleranceBp),
            sub: '±${Money.formatBp(row.toleranceBp).replaceAll('+', '')}',
          ),
        ]),
      ),
    );
  }
}

/// Read-only drill-in: the project's budget lines, latest submitted
/// forecast lines and actuals, as compact tables.
class _ProjectDetail extends StatelessWidget {
  final ProjectFinanceRow row;
  final _Loaded data;
  final String currency;
  const _ProjectDetail(
      {required this.row, required this.data, required this.currency});

  @override
  Widget build(BuildContext context) {
    final names = {for (final c in data.categories) c.id: c.name};
    String cat(String id) => names[id] ?? 'Unknown';

    final budgetLines = row.budget == null
        ? const <BudgetLine>[]
        : data.budgetLines.where((l) => l.budgetId == row.budget!.id).toList();
    final forecastLines = row.latestSnapshot == null
        ? const <ForecastLine>[]
        : data.forecastLines
            .where((l) => l.snapshotId == row.latestSnapshot!.id)
            .toList();
    final actuals =
        data.actuals.where((a) => a.sourceProjectId == row.sourceId).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 6, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        children: [
          _LinesBlock(
            title: 'BUDGET · ${row.budget?.name ?? '—'}',
            columns: _fys(budgetLines.map((l) => l.financialYear)),
            rows: _pivot(budgetLines.map(
                (l) => (cat(l.costCategoryId), l.financialYear, l.amountMinor))),
            currency: currency,
          ),
          _LinesBlock(
            title: 'FORECAST · ${row.latestSnapshot?.period ?? 'none submitted'}',
            columns: _fys(forecastLines.map((l) => l.financialYear)),
            rows: _pivot(forecastLines.map(
                (l) => (cat(l.costCategoryId), l.financialYear, l.amountMinor))),
            currency: currency,
          ),
          _LinesBlock(
            title: 'ACTUALS',
            columns: _fys(actuals.map((a) => a.period)),
            rows: _pivot(actuals
                .map((a) => (cat(a.costCategoryId), a.period, a.amountMinor))),
            currency: currency,
          ),
        ],
      ),
    );
  }

  static List<String> _fys(Iterable<String> keys) =>
      keys.toSet().toList()..sort();

  /// category → column → amount (ints summed).
  static Map<String, Map<String, int>> _pivot(
      Iterable<(String, String, int)> cells) {
    final out = <String, Map<String, int>>{};
    for (final (cat, col, minor) in cells) {
      final m = out.putIfAbsent(cat, () => {});
      m[col] = (m[col] ?? 0) + minor;
    }
    return out;
  }
}

class _LinesBlock extends StatelessWidget {
  final String title;
  final List<String> columns;
  final Map<String, Map<String, int>> rows;
  final String currency;
  const _LinesBlock({
    required this.title,
    required this.columns,
    required this.rows,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final cats = rows.keys.toList()..sort();
    final colTotals = <String, int>{};
    for (final r in rows.values) {
      for (final e in r.entries) {
        colTotals[e.key] = (colTotals[e.key] ?? 0) + e.value;
      }
    }
    Widget num(int? v, {bool bold = false}) => SizedBox(
          width: 96,
          child: Text(v == null ? '' : Money.formatMinorCompact(v, currency),
              textAlign: TextAlign.right,
              style: _money(KColors.text, bold).copyWith(fontSize: 11)),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 260),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: KColors.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
        const SizedBox(height: 6),
        if (rows.isEmpty)
          const Text('—', style: TextStyle(color: KColors.textMuted, fontSize: 11))
        else ...[
          Row(children: [
            const SizedBox(width: 130),
            for (final c in columns)
              SizedBox(
                width: 96,
                child: Text(c,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: KColors.textMuted, fontSize: 9.5)),
              ),
          ]),
          for (final cat in cats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(
                  width: 130,
                  child: Text(cat,
                      style: const TextStyle(color: KColors.textDim, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
                for (final c in columns) num(rows[cat]![c]),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              const SizedBox(
                width: 130,
                child: Text('Total',
                    style: TextStyle(
                        color: KColors.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              for (final c in columns) num(colTotals[c], bold: true),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final CategoryFinanceRow row;
  final CategoryBucket bucket;
  final List<String> financialYears;
  final String currency;
  final bool hasMerges;
  final Map<String, String> projectNames;
  final Map<String, String> categoryNames;
  final Future<void> Function() onUnmerge;
  const _CategoryRow({
    required this.row,
    required this.bucket,
    required this.financialYears,
    required this.currency,
    required this.hasMerges,
    required this.projectNames,
    required this.categoryNames,
    required this.onUnmerge,
  });

  @override
  Widget build(BuildContext context) {
    final sources = bucket.categoryIds
        .map((id) => '${categoryNames[id] ?? '?'} (${projectNames[id] ?? '?'})')
        .join(', ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: KColors.border.withValues(alpha: 0.6))),
      ),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Tooltip(
            message: sources,
            waitDuration: const Duration(milliseconds: 400),
            child: Row(children: [
              Flexible(
                child: Text(row.name,
                    style: const TextStyle(
                        color: KColors.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              Text('${bucket.categoryIds.length}',
                  style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
              if (hasMerges) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onUnmerge,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: KColors.amberDim,
                      border: Border.all(color: KColors.amber, width: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Tooltip(
                      message: 'Merged — click to undo',
                      child: Text('MERGED',
                          style: TextStyle(
                              color: KColors.amber,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6)),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
        for (final fy in financialYears)
          Expanded(
            child: Text(
              row.budgetByFy[fy] == null
                  ? ''
                  : Money.formatMinorCompact(row.budgetByFy[fy], currency),
              textAlign: TextAlign.right,
              style: _money(KColors.textDim).copyWith(fontSize: 11),
            ),
          ),
        Expanded(
          flex: 2,
          child: Text(Money.formatMinorCompact(row.budgetMinor, currency),
              textAlign: TextAlign.right, style: _money()),
        ),
        Expanded(
          flex: 2,
          child: Text(Money.formatMinorCompact(row.forecastMinor, currency),
              textAlign: TextAlign.right, style: _money()),
        ),
        Expanded(
          flex: 2,
          child: Text(Money.formatMinorCompact(row.actualsMinor, currency),
              textAlign: TextAlign.right, style: _money()),
        ),
      ]),
    );
  }
}

class _MergeDialog extends StatefulWidget {
  final List<CategoryBucket> buckets;
  const _MergeDialog({required this.buckets});

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  final Set<int> _picked = {};
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text.trim();
    final ok = _picked.length >= 2 && name.isNotEmpty;
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Merge categories',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Pick the rows that mean the same thing and give them one name. '
            'Future arrivals with these names roll up here too.',
            style: TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < widget.buckets.length; i++)
                  CheckboxListTile(
                    dense: true,
                    value: _picked.contains(i),
                    title: Text(widget.buckets[i].name,
                        style: const TextStyle(color: KColors.text, fontSize: 12)),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _picked.add(i);
                        if (_nameCtrl.text.isEmpty) {
                          _nameCtrl.text = widget.buckets[i].name;
                        }
                      } else {
                        _picked.remove(i);
                      }
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: KColors.text, fontSize: 13),
            decoration: const InputDecoration(
                labelText: 'Roll up as', isDense: true),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: ok ? () => Navigator.of(context).pop((_picked, name)) : null,
          child: const Text('Merge'),
        ),
      ],
    );
  }
}
