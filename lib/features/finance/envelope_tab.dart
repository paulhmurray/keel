import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/finance/contingency_ledger.dart';
import '../../core/finance/programme_rollup.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/money.dart';
import 'contingency_movement_dialog.dart';
import 'finance_form.dart' show financeActor;
import 'funding_form_dialog.dart';

/// Programme Finance → ENVELOPE: what the programme was given, what it
/// has handed to each project, and the contingency ledger in the open.
class EnvelopeTab extends StatelessWidget {
  final AppDatabase db;
  final String programmeId;
  const EnvelopeTab({super.key, required this.db, required this.programmeId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: db.watchAnyChange(),
      builder: (context, _) => FutureBuilder<_Loaded>(
        future: _load(context),
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          return _body(context, d);
        },
      ),
    );
  }

  Future<_Loaded> _load(BuildContext context) async {
    final approvals = await db.financeDao.getFunding(programmeId);
    final movements = await db.financeDao.getMovements(programmeId);
    final settings = await db.financeDao.getFinanceSettings(programmeId);
    final decisions = await db.decisionsDao.getDecisionsForProject(programmeId);
    final links = await db.programmeLinksDao.getLinksForEntity(programmeId);
    final rollup = computeProgrammeFinance(
      categories: await db.financeDao.getCascadedCategories(programmeId),
      budgets: await db.financeDao.getCascadedBudgets(programmeId),
      budgetLines: await db.financeDao.getCascadedBudgetLines(programmeId),
      snapshots: const [],
      forecastLines: const [],
      actuals: const [],
      merges: const [],
    );
    return _Loaded(
      ledger: computeLedger(approvals: approvals, movements: movements),
      approvals: approvals,
      warnBp: settings?.contingencyWarnBp ?? 2000,
      decisions: {for (final d in decisions) d.id: d},
      linkedProjects: [
        for (final l in links)
          if (l.status == 'active' && l.partnerLocalId != null) l.partnerLocalId!,
      ],
      approvedBudgetBySource: {
        for (final r in rollup.projects) r.sourceId: r.budgetMinor,
      },
    );
  }

  String _name(BuildContext context, String id) => context
          .read<ProjectProvider>()
          .projects
          .cast<Project?>()
          .firstWhere((p) => p?.id == id, orElse: () => null)
          ?.name ??
      'Linked project';

  Widget _body(BuildContext context, _Loaded d) {
    final l = d.ledger;
    final cur = l.currency ?? 'AUD';
    final actor = financeActor(context);
    final projectIds = {...d.linkedProjects, for (final p in l.projects) p.linkedProjectId}
        .toList()
      ..sort((a, b) => _name(context, a).toLowerCase().compareTo(_name(context, b).toLowerCase()));
    final warn = l.fundingMinor > 0 && l.belowThreshold(d.warnBp);

    Future<void> movement(String kind, {String? projectId}) async {
      await showDialog(
        context: context,
        builder: (_) => ContingencyMovementDialog(
            db: db, programmeId: programmeId, initialKind: kind, initialProjectId: projectId),
      );
    }

    return ListView(children: [
      // ── Header stats ──
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KColors.surface,
          border: Border.all(color: warn ? KColors.red.withValues(alpha: 0.6) : KColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('FUNDING ENVELOPE',
                style: TextStyle(color: KColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Spacer(),
            if (l.currencyMismatch)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Text('Approvals disagree on currency',
                    style: TextStyle(color: KColors.amber, fontSize: 11)),
              ),
            if (warn)
              Text(
                l.balanceMinor < 0
                    ? 'Over-allocated'
                    : 'Contingency below ${Money.formatBp(d.warnBp).replaceAll('+', '')} of funding',
                style: const TextStyle(color: KColors.red, fontSize: 11, fontWeight: FontWeight.w700),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _stat('FUNDING', Money.formatMinorCompact(l.fundingMinor, cur)),
            _stat('ALLOCATED', Money.formatMinorCompact(l.allocatedMinor, cur)),
            _stat('DRAWN FROM CONTINGENCY', Money.formatMinorCompact(l.drawnMinor, cur),
                color: l.drawnMinor > 0 ? KColors.amber : KColors.text),
            _stat('RETURNED', Money.formatMinorCompact(l.returnedMinor, cur)),
            _stat(
              'CONTINGENCY BALANCE',
              '${Money.formatMinorCompact(l.balanceMinor, cur)}'
              '${l.balanceBp == null ? '' : '  ·  ${Money.formatBp(l.balanceBp).replaceAll('+', '')}'}',
              color: warn ? KColors.red : KColors.phosphor,
            ),
          ]),
          if (l.series.length > 1) ...[
            const SizedBox(height: 12),
            _BalanceBurn(series: l.series, funding: l.fundingMinor, warnBp: d.warnBp, currency: cur),
          ],
        ]),
      ),
      const SizedBox(height: 16),

      // ── Funding approvals ──
      _sectionHeader(context, 'FUNDING APPROVALS', action: OutlinedButton.icon(
        onPressed: () => showDialog(
            context: context,
            builder: (_) => FundingFormDialog(db: db, programmeId: programmeId)),
        icon: const Icon(Icons.add, size: 14),
        label: const Text('Add funding'),
      )),
      if (d.approvals.isEmpty)
        _empty('No funding recorded yet. Add the approved business case or tranche the programme was given.')
      else
        for (final a in d.approvals)
          _row(children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: const TextStyle(color: KColors.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (a.approvedOn != null) 'approved ${a.approvedOn}',
                    if (a.approvedBy != null) 'by ${a.approvedBy}',
                    if (a.decisionId != null && d.decisions[a.decisionId] != null)
                      d.decisions[a.decisionId]!.ref ?? 'decision',
                    if (a.notes != null) a.notes!,
                  ].join(' · '),
                  style: const TextStyle(color: KColors.textDim, fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            Text(Money.formatMinorCompact(a.amountMinor, a.currency), style: _money()),
            const SizedBox(width: 8),
            _iconButton(Icons.edit_outlined, 'Edit', () => showDialog(
                context: context,
                builder: (_) => FundingFormDialog(db: db, programmeId: programmeId, existing: a))),
            _iconButton(Icons.delete_outline, 'Remove', () async {
              final ok = await _confirm(context, 'Remove funding "${a.name}"?');
              if (ok) await db.financeDao.deleteFunding(a.id, changedBy: actor);
            }, color: KColors.red),
          ]),
      const SizedBox(height: 16),

      // ── Allocations by project ──
      _sectionHeader(context, 'ALLOCATIONS BY PROJECT', action: Row(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton.icon(
          onPressed: projectIds.isEmpty ? null : () => movement(kMovementAllocate),
          icon: const Icon(Icons.call_split, size: 14),
          label: const Text('Allocate'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: projectIds.isEmpty ? null : () => movement(kMovementDraw),
          icon: const Icon(Icons.south_east, size: 14),
          label: const Text('Draw'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: projectIds.isEmpty ? null : () => movement(kMovementReturn),
          icon: const Icon(Icons.north_west, size: 14),
          label: const Text('Return'),
        ),
      ])),
      if (projectIds.isEmpty)
        _empty('No linked projects yet. Link a project in Settings and its allocation appears here.')
      else ...[
        _tableHeader(const [('PROJECT', 3), ('ALLOCATED', 2), ('OF WHICH DRAWN', 2), ('APPROVED BUDGET', 2), ('BUDGET vs ALLOCATION', 2)]),
        for (final pid in projectIds) _allocationRow(context, d, pid, cur, movement),
      ],
      const SizedBox(height: 16),

      // ── Ledger ──
      _sectionHeader(context, 'CONTINGENCY LEDGER', action: _ThresholdControl(
        warnBp: d.warnBp,
        onChanged: (bp) => db.financeDao.setContingencyWarnBp(programmeId, bp, changedBy: actor),
      )),
      if (l.projects.every((p) => p.history.isEmpty))
        _empty('No movements yet. Allocate, draw or return to start the ledger.')
      else ...[
        _tableHeader(const [('DATE', 1), ('MOVEMENT', 2), ('PROJECT', 2), ('AMOUNT', 1), ('DECISION', 2), ('REASON', 3)]),
        for (final m in (l.projects.expand((p) => p.history).toList()
              ..sort((a, b) => b.movedOn.compareTo(a.movedOn))))
          _row(children: [
            Expanded(child: Text(m.movedOn, style: const TextStyle(color: KColors.textDim, fontSize: 11, fontFamily: 'monospace'))),
            Expanded(
              flex: 2,
              child: Text(movementLabel(m.kind),
                  style: TextStyle(
                      color: m.kind == kMovementDraw ? KColors.amber : m.kind == kMovementReturn ? KColors.phosphor : KColors.text,
                      fontSize: 12)),
            ),
            Expanded(flex: 2, child: Text(_name(context, m.linkedProjectId), style: const TextStyle(color: KColors.text, fontSize: 12), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Text(
                '${movementSign(m.kind) < 0 ? '−' : ''}${Money.formatMinorCompact(m.amountMinor, cur)}',
                textAlign: TextAlign.right,
                style: _money(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                m.decisionId == null
                    ? '—'
                    : '${d.decisions[m.decisionId]?.ref ?? ''} ${d.decisions[m.decisionId]?.description ?? '(decision)'}'.trim(),
                style: const TextStyle(color: KColors.amber, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(children: [
                Expanded(
                  child: Text(
                    [if (m.reason != null) m.reason!, if (m.enteredBy != null) '(${m.enteredBy})'].join(' '),
                    style: const TextStyle(color: KColors.textDim, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _iconButton(Icons.delete_outline, 'Remove this movement', () async {
                  final ok = await _confirm(context, 'Remove this ${movementLabel(m.kind).toLowerCase()} of ${Money.formatMinorCompact(m.amountMinor, cur)}?');
                  if (!ok) return;
                  await db.financeDao.deleteMovement(m.id, changedBy: actor);
                  if (context.mounted) {
                    // Re-send the corrected allocation.
                    // ignore: use_build_context_synchronously
                    await _repush(context, m.linkedProjectId);
                  }
                }, color: KColors.red),
              ]),
            ),
          ]),
      ],
      const SizedBox(height: 24),
    ]);
  }

  Future<void> _repush(BuildContext context, String linkedProjectId) =>
      buildCascadeService(context).pushAllocation(programmeId, linkedProjectId);

  Widget _allocationRow(BuildContext context, _Loaded d, String pid, String cur,
      Future<void> Function(String kind, {String? projectId}) movement) {
    final a = d.ledger.forProject(pid);
    final allocated = a?.allocatedMinor ?? 0;
    final budget = d.approvedBudgetBySource[pid];
    final over = budget != null && budget > allocated;
    return _row(children: [
      Expanded(
        flex: 3,
        child: Text(_name(context, pid),
            style: const TextStyle(color: KColors.text, fontSize: 12.5, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
      ),
      Expanded(flex: 2, child: Text(Money.formatMinorCompact(allocated, cur), textAlign: TextAlign.right, style: _money())),
      Expanded(
        flex: 2,
        child: Text(a == null || a.drawnMinor == 0 ? '—' : Money.formatMinorCompact(a.drawnMinor, cur),
            textAlign: TextAlign.right, style: _money(a != null && a.drawnMinor > 0 ? KColors.amber : KColors.textMuted)),
      ),
      Expanded(
        flex: 2,
        child: Text(budget == null ? 'none shared' : Money.formatMinorCompact(budget, cur),
            textAlign: TextAlign.right, style: _money(budget == null ? KColors.textMuted : KColors.text)),
      ),
      Expanded(
        flex: 2,
        child: Tooltip(
          message: over
              ? 'The project has approved more budget than the programme allocated it'
              : budget == null
                  ? 'The project has not shared an approved budget'
                  : 'Approved budget sits within the allocation',
          child: Text(
            budget == null ? '—' : Money.formatMinorCompact(budget - allocated, cur),
            textAlign: TextAlign.right,
            style: _money(over ? KColors.amber : KColors.textDim),
          ),
        ),
      ),
      const SizedBox(width: 6),
      _iconButton(Icons.south_east, 'Draw for this project', () => movement(kMovementDraw, projectId: pid)),
    ]);
  }

  // ── bits ──
  Widget _stat(String label, String value, {Color color = KColors.text}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: KColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 3),
          Text(value, style: _money(color, true).copyWith(fontSize: 15)),
        ]),
      );

  Widget _sectionHeader(BuildContext context, String title, {Widget? action}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(title, style: const TextStyle(color: KColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const Spacer(),
          ?action,
        ]),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(color: KColors.textDim, fontSize: 12)),
      );

  Widget _row({required List<Widget> children}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: KColors.border.withValues(alpha: 0.6)))),
        child: Row(children: children),
      );

  Widget _tableHeader(List<(String, int)> cols) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: KColors.border))),
        child: Row(children: [
          for (var i = 0; i < cols.length; i++)
            Expanded(
              flex: cols[i].$2,
              child: Text(cols[i].$1,
                  textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                  style: const TextStyle(color: KColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            ),
        ]),
      );

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap, {Color color = KColors.textMuted}) => IconButton(
        icon: Icon(icon, size: 15, color: color),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        onPressed: onTap,
      );

  Future<bool> _confirm(BuildContext context, String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColors.surface,
        content: Text(text, style: const TextStyle(color: KColors.text, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    return ok ?? false;
  }
}

TextStyle _money([Color color = KColors.text, bool bold = false]) =>
    TextStyle(color: color, fontSize: 12, fontFamily: 'monospace', fontWeight: bold ? FontWeight.w700 : FontWeight.w500);

class _Loaded {
  final ContingencyLedger ledger;
  final List<FundingApproval> approvals;
  final int warnBp;
  final Map<String, Decision> decisions;
  final List<String> linkedProjects;
  final Map<String, int> approvedBudgetBySource;
  const _Loaded({
    required this.ledger,
    required this.approvals,
    required this.warnBp,
    required this.decisions,
    required this.linkedProjects,
    required this.approvedBudgetBySource,
  });
}

/// The warning threshold, editable in place.
class _ThresholdControl extends StatelessWidget {
  final int warnBp;
  final ValueChanged<int> onChanged;
  const _ThresholdControl({required this.warnBp, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [1000, 1500, 2000, 2500, 3000];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Text('Warn below', style: TextStyle(color: KColors.textMuted, fontSize: 11)),
      const SizedBox(width: 6),
      DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: options.contains(warnBp) ? warnBp : null,
          hint: Text('${warnBp ~/ 100}%', style: const TextStyle(color: KColors.text, fontSize: 11)),
          dropdownColor: KColors.surface2,
          style: const TextStyle(color: KColors.text, fontSize: 11),
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text('${o ~/ 100}% of funding'))],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    ]);
  }
}

/// Balance over time as a thin bar chart; the warning line is drawn at
/// the threshold share of funding.
class _BalanceBurn extends StatelessWidget {
  final List<LedgerPoint> series;
  final int funding;
  final int warnBp;
  final String currency;
  const _BalanceBurn(
      {required this.series, required this.funding, required this.warnBp, required this.currency});

  @override
  Widget build(BuildContext context) {
    final maxV = [funding, ...series.map((p) => p.balanceMinor)].fold<int>(1, (m, v) => v > m ? v : m);
    final warnLine = funding * warnBp ~/ 10000;
    // Long ledgers: keep the last 36 points so bars stay readable.
    final shown = series.length > 36 ? series.sublist(series.length - 36) : series;
    return SizedBox(
      height: 54,
      child: LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth / shown.length).clamp(3.0, 60.0);
        return Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 12 + 42 * warnLine / maxV,
            child: Container(height: 1, color: KColors.red.withValues(alpha: 0.5)),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final p in shown)
              Tooltip(
                message: '${p.date}: ${Money.formatMinorCompact(p.balanceMinor, currency)}',
                child: Container(
                  width: (w - 2).clamp(1.0, w),
                  margin: const EdgeInsets.only(right: 2),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      height: (42 * (p.balanceMinor < 0 ? 0 : p.balanceMinor) / maxV).clamp(1, 42).toDouble(),
                      color: p.balanceMinor < warnLine ? KColors.red : KColors.phosphor,
                    ),
                    const SizedBox(height: 2),
                    Text(p.date.length >= 7 ? p.date.substring(2, 7) : p.date,
                        style: const TextStyle(color: KColors.textMuted, fontSize: 8),
                        overflow: TextOverflow.clip),
                  ]),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}
