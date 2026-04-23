import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';

// ---------------------------------------------------------------------------
// Pressure model
// ---------------------------------------------------------------------------

enum _PressureIcon { warning, decision, milestone, stalled }

class _Pressure {
  final _PressureIcon icon;
  final String title;
  final String subtitle;
  final int priority; // lower = higher priority

  const _Pressure({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.priority,
  });
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class PressuresSection extends StatefulWidget {
  final String projectId;
  final AppDatabase db;

  const PressuresSection({
    super.key,
    required this.projectId,
    required this.db,
  });

  @override
  State<PressuresSection> createState() => _PressuresSectionState();
}

class _PressuresSectionState extends State<PressuresSection> {
  List<_Pressure>? _pressures;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PressuresSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _load();
  }

  Future<void> _load() async {
    final pressures = await _buildPressures(widget.db, widget.projectId);
    if (mounted) setState(() => _pressures = pressures);
  }

  static Future<List<_Pressure>> _buildPressures(
      AppDatabase db, String projectId) async {
    final today = DateTime.now();
    final todayIso =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final all = <_Pressure>[];

    // Priority 1: at-risk dependencies
    final deps = await db.raidDao.getDependenciesForProject(projectId);
    for (final d in deps.where((d) => d.status == 'at_risk')) {
      int? daysBlocked;
      if (d.dueDate != null && d.dueDate!.isNotEmpty) {
        final due = DateTime.tryParse(d.dueDate!);
        if (due != null && due.isBefore(today)) {
          daysBlocked = today.difference(due).inDays;
        }
      }
      all.add(_Pressure(
        icon: _PressureIcon.warning,
        title: d.description,
        subtitle: daysBlocked != null
            ? 'At-risk dependency · overdue ${daysBlocked}d'
            : 'At-risk dependency · ${d.owner ?? 'no owner'}',
        priority: 1,
      ));
    }

    // Priority 2: critical stakeholder gaps
    final stakeholders =
        await db.stakeholderRoleDao.getForProject(projectId);
    for (final s in stakeholders) {
      final isCritical = s.priority == 'critical';
      final hasGap = s.gapFlag;
      final notEngaged = s.engagementStatus == 'not_started' ||
          s.engagementStatus == 'not_engaged';
      if (isCritical && (hasGap || notEngaged) && s.personId == null) {
        all.add(_Pressure(
          icon: _PressureIcon.warning,
          title: 'Stakeholder gap: ${s.roleName}',
          subtitle: 'Critical role · not yet engaged',
          priority: 2,
        ));
      }
    }

    // Priority 3: overdue decisions
    final decisions =
        await db.decisionsDao.getDecisionsForProject(projectId);
    for (final d in decisions.where((d) =>
        d.status == 'pending' &&
        d.dueDate != null &&
        d.dueDate!.isNotEmpty &&
        d.dueDate!.compareTo(todayIso) < 0)) {
      final due = DateTime.tryParse(d.dueDate!)!;
      final daysOverdue = today.difference(due).inDays;
      all.add(_Pressure(
        icon: _PressureIcon.decision,
        title: d.description,
        subtitle:
            'Decision overdue ${daysOverdue}d · ${d.decisionMaker ?? 'no owner'}',
        priority: 3,
      ));
    }

    // Priority 4: upcoming milestones within 14 days
    final milestones =
        await db.milestonesDao.getForProject(projectId);
    for (final m in milestones.where((m) => m.status == 'upcoming')) {
      final due = DateTime.tryParse(m.date);
      if (due == null) continue;
      final daysUntil = due.difference(today).inDays;
      if (daysUntil >= 0 && daysUntil <= 14) {
        all.add(_Pressure(
          icon: _PressureIcon.milestone,
          title: m.name,
          subtitle: daysUntil == 0
              ? 'Milestone · due today'
              : 'Milestone · due in ${daysUntil}d',
          priority: m.isHardDeadline ? 3 : 4,
        ));
      }
    }

    // Priority 5: stalled playbook stage (no change in 14+ days)
    final pp = await db.playbookDao.getProjectPlaybook(projectId);
    if (pp != null) {
      final progresses =
          await db.playbookDao.getProgressForProjectPlaybook(pp.id);
      for (final p in progresses.where((p) => p.status == 'in_progress')) {
        final staleDays = today.difference(p.updatedAt).inDays;
        if (staleDays >= 14) {
          final stage = await db.playbookDao.getStageById(p.stageId);
          if (stage != null) {
            all.add(_Pressure(
              icon: _PressureIcon.stalled,
              title: 'Stalled playbook stage: ${stage.name}',
              subtitle: 'In progress · no change in ${staleDays}d',
              priority: 5,
            ));
          }
        }
      }
    }

    all.sort((a, b) => a.priority.compareTo(b.priority));
    return all.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ps = _pressures;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PRESSURES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
              color: KColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (ps == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ),
            )
          else if (ps.isEmpty)
            const Text(
              'No pressures detected. The programme is running clean.',
              style: TextStyle(
                color: KColors.textDim,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            for (int i = 0; i < ps.length; i++) ...[
              if (i > 0)
                const Divider(height: 16, color: KColors.border),
              _PressureRow(pressure: ps[i]),
            ],
        ],
      ),
    );
  }
}

class _PressureRow extends StatelessWidget {
  final _Pressure pressure;

  const _PressureRow({required this.pressure});

  IconData get _iconData {
    switch (pressure.icon) {
      case _PressureIcon.warning:
        return Icons.warning_amber_outlined;
      case _PressureIcon.decision:
        return Icons.help_outline;
      case _PressureIcon.milestone:
        return Icons.diamond_outlined;
      case _PressureIcon.stalled:
        return Icons.pause_circle_outline;
    }
  }

  Color get _iconColor {
    switch (pressure.priority) {
      case 1:
      case 2:
        return KColors.red;
      case 3:
        return KColors.amber;
      default:
        return KColors.textDim;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1, right: 10),
          child: Icon(_iconData, size: 14, color: _iconColor),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pressure.title,
                style: const TextStyle(
                  fontSize: 13,
                  color: KColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                pressure.subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: KColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
