import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class _VelocityData {
  final int actionsOpenedThisWeek;
  final int actionsClosedThisWeek;
  final int decisionsMadeThisWeek;
  final int decisionsPending;
  final int risksNewThisWeek;
  final int risksResolvedThisWeek;
  final int depsAtRisk;
  final int depsConfirmedThisWeek;

  const _VelocityData({
    this.actionsOpenedThisWeek = 0,
    this.actionsClosedThisWeek = 0,
    this.decisionsMadeThisWeek = 0,
    this.decisionsPending = 0,
    this.risksNewThisWeek = 0,
    this.risksResolvedThisWeek = 0,
    this.depsAtRisk = 0,
    this.depsConfirmedThisWeek = 0,
  });

  static Future<_VelocityData> load(
      AppDatabase db, String projectId) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));

    final actions = await db.actionsDao.getActionsForProject(projectId);
    final actionsOpenedThisWeek = actions
        .where((a) => a.createdAt.isAfter(cutoff))
        .length;
    final actionsClosedThisWeek = actions
        .where((a) =>
            a.status == 'complete' && a.updatedAt.isAfter(cutoff))
        .length;

    final decisions =
        await db.decisionsDao.getDecisionsForProject(projectId);
    final decisionsMadeThisWeek = decisions
        .where((d) =>
            d.status == 'complete' && d.updatedAt.isAfter(cutoff))
        .length;
    final decisionsPending =
        decisions.where((d) => d.status == 'pending').length;

    final risks = await db.raidDao.getRisksForProject(projectId);
    final risksNewThisWeek =
        risks.where((r) => r.createdAt.isAfter(cutoff)).length;
    final risksResolvedThisWeek = risks
        .where((r) =>
            (r.status == 'mitigated' || r.status == 'closed') &&
            r.updatedAt.isAfter(cutoff))
        .length;

    final deps =
        await db.raidDao.getDependenciesForProject(projectId);
    final depsAtRisk =
        deps.where((d) => d.status == 'at_risk').length;
    final depsConfirmedThisWeek = deps
        .where((d) =>
            d.status == 'confirmed' && d.updatedAt.isAfter(cutoff))
        .length;

    return _VelocityData(
      actionsOpenedThisWeek: actionsOpenedThisWeek,
      actionsClosedThisWeek: actionsClosedThisWeek,
      decisionsMadeThisWeek: decisionsMadeThisWeek,
      decisionsPending: decisionsPending,
      risksNewThisWeek: risksNewThisWeek,
      risksResolvedThisWeek: risksResolvedThisWeek,
      depsAtRisk: depsAtRisk,
      depsConfirmedThisWeek: depsConfirmedThisWeek,
    );
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class VelocityRow extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTapActions;
  final VoidCallback? onTapDecisions;
  final VoidCallback? onTapRisks;
  final VoidCallback? onTapDependencies;

  const VelocityRow({
    super.key,
    required this.projectId,
    required this.db,
    this.onTapActions,
    this.onTapDecisions,
    this.onTapRisks,
    this.onTapDependencies,
  });

  @override
  State<VelocityRow> createState() => _VelocityRowState();
}

class _VelocityRowState extends State<VelocityRow> {
  _VelocityData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VelocityRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _load();
  }

  Future<void> _load() async {
    final d = await _VelocityData.load(widget.db, widget.projectId);
    if (mounted) setState(() => _data = d);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return const SizedBox(
        height: 96,
        child: Center(
            child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5))),
      );
    }

    final actionsNet = d.actionsOpenedThisWeek - d.actionsClosedThisWeek;
    final risksNet = d.risksNewThisWeek - d.risksResolvedThisWeek;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWrap = constraints.maxWidth < 500;
        if (useWrap) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: (constraints.maxWidth - 8) / 2,
                child: _VelocityCard(
                  label: 'ACTIONS',
                  rows: [
                    _StatRow('opened', d.actionsOpenedThisWeek),
                    _StatRow('closed', d.actionsClosedThisWeek),
                  ],
                  net: actionsNet,
                  onTap: widget.onTapActions,
                ),
              ),
              SizedBox(
                width: (constraints.maxWidth - 8) / 2,
                child: _VelocityCard(
                  label: 'DECISIONS',
                  rows: [
                    _StatRow('made', d.decisionsMadeThisWeek),
                    _StatRow('pending', d.decisionsPending),
                  ],
                  net: null,
                  netLabel: d.decisionsPending > 0
                      ? 'backlog ${d.decisionsPending}'
                      : 'clear',
                  onTap: widget.onTapDecisions,
                ),
              ),
              SizedBox(
                width: (constraints.maxWidth - 8) / 2,
                child: _VelocityCard(
                  label: 'RISKS',
                  rows: [
                    _StatRow('new', d.risksNewThisWeek),
                    _StatRow('resolved', d.risksResolvedThisWeek),
                  ],
                  net: risksNet,
                  onTap: widget.onTapRisks,
                ),
              ),
              SizedBox(
                width: (constraints.maxWidth - 8) / 2,
                child: _VelocityCard(
                  label: 'DEPENDENCIES',
                  rows: [
                    _StatRow('at risk', d.depsAtRisk),
                    _StatRow('confirmed', d.depsConfirmedThisWeek),
                  ],
                  net: null,
                  netLabel: d.depsAtRisk > 0
                      ? '${d.depsAtRisk} at risk'
                      : 'clear',
                  onTap: widget.onTapDependencies,
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _VelocityCard(
                label: 'ACTIONS',
                rows: [
                  _StatRow('opened', d.actionsOpenedThisWeek),
                  _StatRow('closed', d.actionsClosedThisWeek),
                ],
                net: actionsNet,
                onTap: widget.onTapActions,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _VelocityCard(
                label: 'DECISIONS',
                rows: [
                  _StatRow('made', d.decisionsMadeThisWeek),
                  _StatRow('pending', d.decisionsPending),
                ],
                net: null,
                netLabel: d.decisionsPending > 0
                    ? 'backlog ${d.decisionsPending}'
                    : 'clear',
                onTap: widget.onTapDecisions,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _VelocityCard(
                label: 'RISKS',
                rows: [
                  _StatRow('new', d.risksNewThisWeek),
                  _StatRow('resolved', d.risksResolvedThisWeek),
                ],
                net: risksNet,
                onTap: widget.onTapRisks,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _VelocityCard(
                label: 'DEPENDENCIES',
                rows: [
                  _StatRow('at risk', d.depsAtRisk),
                  _StatRow('confirmed', d.depsConfirmedThisWeek),
                ],
                net: null,
                netLabel: d.depsAtRisk > 0
                    ? '${d.depsAtRisk} at risk'
                    : 'clear',
                onTap: widget.onTapDependencies,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatRow {
  final String label;
  final int value;
  const _StatRow(this.label, this.value);
}

class _VelocityCard extends StatelessWidget {
  final String label;
  final List<_StatRow> rows;
  final int? net;
  final String? netLabel;
  final VoidCallback? onTap;

  const _VelocityCard({
    required this.label,
    required this.rows,
    this.net,
    this.netLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    String netText;
    Color netColor;
    if (net != null) {
      final n = net!;
      if (n > 0) {
        netText = 'net +$n ↑';
        netColor = KColors.amber;
      } else if (n < 0) {
        netText = 'net $n ↓';
        netColor = KColors.phosphor;
      } else {
        netText = 'net 0 →';
        netColor = KColors.textDim;
      }
    } else {
      netText = netLabel ?? '';
      netColor = KColors.textDim;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: KColors.surface,
          border: Border.all(color: KColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
                color: KColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            for (final row in rows) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(row.label,
                      style: const TextStyle(
                          fontSize: 12, color: KColors.textDim)),
                  Text(
                    '${row.value}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: KColors.text),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 4),
            Text(
              netText,
              style: TextStyle(fontSize: 11, color: netColor),
            ),
          ],
        ),
      ),
    );
  }
}
