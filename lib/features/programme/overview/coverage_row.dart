import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../core/programme/coverage_calculator.dart';
import '../../../shared/theme/keel_colors.dart';

class CoverageRow extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTapStakeholders;
  final VoidCallback? onTapTeam;
  final VoidCallback? onTapPlaybook;

  const CoverageRow({
    super.key,
    required this.projectId,
    required this.db,
    this.onTapStakeholders,
    this.onTapTeam,
    this.onTapPlaybook,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final useColumn = constraints.maxWidth < 500;
      final children = [
        _StakeholderGauge(
            projectId: projectId, db: db, onTap: onTapStakeholders),
        _TeamGauge(projectId: projectId, db: db, onTap: onTapTeam),
        _PlaybookGauge(projectId: projectId, db: db, onTap: onTapPlaybook),
      ];

      if (useColumn) {
        return Column(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              children[i],
            ]
          ],
        );
      }

      return Row(
        children: [
          Expanded(child: children[0]),
          const SizedBox(width: 8),
          Expanded(child: children[1]),
          const SizedBox(width: 8),
          Expanded(child: children[2]),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Gauges
// ---------------------------------------------------------------------------

class _StakeholderGauge extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;

  const _StakeholderGauge(
      {required this.projectId, required this.db, this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StakeholderRole>>(
      stream: db.stakeholderRoleDao.watchForProject(projectId),
      builder: (context, snap) {
        final result =
            CoverageCalculator.forStakeholders(snap.data ?? []);
        return _CoverageGauge(
          label: 'STAKEHOLDERS',
          result: result,
          onTap: onTap,
        );
      },
    );
  }
}

class _TeamGauge extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;

  const _TeamGauge(
      {required this.projectId, required this.db, this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TeamRole>>(
      stream: db.teamRoleDao.watchForProject(projectId),
      builder: (context, snap) {
        final result = CoverageCalculator.forTeam(snap.data ?? []);
        return _CoverageGauge(
          label: 'TEAM',
          result: result,
          onTap: onTap,
        );
      },
    );
  }
}

class _PlaybookGauge extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onTap;

  const _PlaybookGauge(
      {required this.projectId, required this.db, this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProjectPlaybook?>(
      stream: db.playbookDao.watchProjectPlaybook(projectId),
      builder: (context, ppSnap) {
        if (ppSnap.data == null) {
          return _CoverageGauge(
            label: 'PLAYBOOK',
            result: null,
            noDataMessage: 'No playbook attached.',
            onTap: onTap,
          );
        }
        return StreamBuilder<List<ProjectStageProgressesData>>(
          stream: db.playbookDao
              .watchProgressForProjectPlaybook(ppSnap.data!.id),
          builder: (context, pgSnap) {
            final progresses = pgSnap.data ?? [];
            final total = progresses.length;
            final done =
                progresses.where((p) => p.status == 'complete').length;
            final inProgress = progresses
                .where((p) => p.status == 'in_progress')
                .firstOrNull;
            final pct = total == 0 ? 0.0 : done / total;
            return _CoverageGauge(
              label: 'PLAYBOOK',
              result: CoverageResult(
                filled: done,
                applicable: total,
                percentage: pct,
                missingRoles: [],
              ),
              playbookStageInfo: inProgress != null
                  ? 'Stage ${done + 1} of $total in progress'
                  : done == total && total > 0
                      ? 'All $total stages complete'
                      : '$done of $total stages done',
              onTap: onTap,
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Generic gauge card
// ---------------------------------------------------------------------------

class _CoverageGauge extends StatelessWidget {
  final String label;
  final CoverageResult? result;
  final String? noDataMessage;
  final String? playbookStageInfo;
  final VoidCallback? onTap;

  const _CoverageGauge({
    required this.label,
    required this.result,
    this.noDataMessage,
    this.playbookStageInfo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
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
            if (r == null)
              Text(
                noDataMessage ?? '—',
                style: const TextStyle(
                    fontSize: 12,
                    color: KColors.textDim,
                    fontStyle: FontStyle.italic),
              )
            else ...[
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: r.percentage,
                  minHeight: 6,
                  backgroundColor: KColors.border2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    r.percentage >= 0.8
                        ? const Color(0xFF22c55e)
                        : r.percentage >= 0.5
                            ? KColors.amber
                            : KColors.red,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(r.percentage * 100).round()}%'
                '  (${r.filled}/${r.applicable})',
                style: const TextStyle(
                    fontSize: 12, color: KColors.text),
              ),
              if (playbookStageInfo != null) ...[
                const SizedBox(height: 4),
                Text(
                  playbookStageInfo!,
                  style: const TextStyle(
                      fontSize: 11, color: KColors.textDim),
                ),
              ] else if (r.missingRoles.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Missing: ${r.missingRoles.take(3).join(', ')}${r.missingRoles.length > 3 ? '…' : ''}',
                  style: const TextStyle(
                      fontSize: 11, color: KColors.textDim),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
