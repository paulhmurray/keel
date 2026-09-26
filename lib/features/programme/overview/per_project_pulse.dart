import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/cascade/cascade_service.dart';
import '../../../core/database/database.dart';
import '../../../core/status/status_calculator.dart';
import '../../../providers/project_provider.dart';
import '../../../shared/theme/keel_colors.dart';

/// Portfolio breakdown under the programme roll-up RAG: one row per linked
/// project with its own RAG + escalated-risk / overdue counts / last
/// status date. All derived from data that already cascades. Renders
/// nothing when there are no linked projects (plain project / empty
/// programme), so it's safe to always mount on the overview.
class PerProjectPulse extends StatelessWidget {
  final String programmeId;
  final AppDatabase db;
  final List<TimelineWorkPackage> workPackages;

  const PerProjectPulse({
    super.key,
    required this.programmeId,
    required this.db,
    required this.workPackages,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PulseData>(
      future: _load(),
      builder: (context, snap) {
        final data = snap.data;
        if (data == null || data.rows.isEmpty) return const SizedBox.shrink();
        final projectsById = {
          for (final p in context.watch<ProjectProvider>().projects) p.id: p
        };
        String nameFor(String id) => projectsById[id]?.name ?? 'Linked project';

        final rows = data.rows.toList()
          ..sort((a, b) {
            // Worst RAG first, then most overdue, then name.
            final r = _ragWeight(b.rag).compareTo(_ragWeight(a.rag));
            if (r != 0) return r;
            final o = b.overdue.compareTo(a.overdue);
            if (o != 0) return o;
            return nameFor(a.sourceId)
                .toLowerCase()
                .compareTo(nameFor(b.sourceId).toLowerCase());
          });

        return Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: KColors.surface,
            border: Border.all(color: KColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('BY PROJECT',
                      style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                ),
              ),
              for (var i = 0; i < rows.length; i++)
                _ProjectPulseRow(
                  label: nameFor(rows[i].sourceId),
                  row: rows[i],
                  isLast: i == rows.length - 1,
                ),
            ],
          ),
        );
      },
    );
  }

  static int _ragWeight(Rag r) => switch (r) {
        Rag.red => 3,
        Rag.amber => 2,
        Rag.green => 1,
        Rag.notStarted => 0,
      };

  Future<_PulseData> _load() async {
    final rows = computePerProjectPulse(
      workPackages: workPackages,
      risks: await db.raidDao.getRisksForProject(programmeId),
      issues: await db.raidDao.getIssuesForProject(programmeId),
      overdueActions:
          await db.actionsDao.getOverdueCascadedActionsForProgramme(programmeId),
      overdueDecisions: await db.decisionsDao
          .getOverdueCascadedDecisionsForProgramme(programmeId),
      reports: await db.reportsDao.getReportsForProject(programmeId),
      activities: await db.programmeGanttDao.getActivitiesForProject(programmeId),
      links: await db.programmeLinksDao.getLinksForEntity(programmeId),
    );
    return _PulseData(rows);
  }
}

/// Pure per-project pulse aggregation. Given the programme-side cascaded
/// feeds, produces one [ProjectPulseStat] per source project (any project
/// that shows up in any feed). Exposed for unit testing.
List<ProjectPulseStat> computePerProjectPulse({
  required List<TimelineWorkPackage> workPackages,
  required List<Risk> risks,
  required List<Issue> issues,
  required List<ProjectAction> overdueActions,
  required List<Decision> overdueDecisions,
  required List<StatusReport> reports,
  List<TimelineActivity> activities = const [],
  List<ProgrammeLink> links = const [],
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final todayIso = '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  // Share level per source: the programme-side link row for that partner.
  final shareBySource = <String, String>{
    for (final l in links)
      if (l.status == 'active' && l.partnerLocalId != null)
        l.partnerLocalId!: l.shareLevel,
  };
  // Next dated milestone/gate/deadline still open, per source project.
  TimelineActivity? nextMilestone(String src) {
    TimelineActivity? best;
    for (final a in activities) {
      if (a.sourceProjectId != src) continue;
      if (a.status == 'complete') continue;
      if (a.activityType != 'milestone' &&
          a.activityType != 'gate' &&
          a.activityType != 'hard_deadline') {
        continue;
      }
      final d = a.startDate ?? a.endDate;
      if (d == null || d.compareTo(todayIso) < 0) continue;
      if (best == null || d.compareTo(best.startDate ?? best.endDate!) < 0) {
        best = a;
      }
    }
    return best;
  }
  final wpsBySource = <String, List<TimelineWorkPackage>>{};
  for (final wp in workPackages) {
    final src = wp.sourceProjectId;
    if (src == null) continue;
    wpsBySource.putIfAbsent(src, () => []).add(wp);
  }

  int riskCount(String src) =>
      risks.where((r) => r.sourceProjectId == src && r.status != 'closed').length +
      issues.where((i) => i.sourceProjectId == src && i.status != 'closed').length;
  int overdueCount(String src) =>
      overdueActions.where((a) => a.sourceProjectId == src).length +
      overdueDecisions.where((d) => d.sourceProjectId == src).length;
  DateTime? lastStatus(String src) {
    DateTime? latest;
    for (final r in reports) {
      if (r.sourceProjectId != src || r.reportDate == null) continue;
      if (latest == null || r.reportDate!.isAfter(latest)) latest = r.reportDate;
    }
    return latest;
  }

  final sources = <String>{
    ...wpsBySource.keys,
    for (final r in risks)
      if (r.sourceProjectId != null) r.sourceProjectId!,
    for (final i in issues)
      if (i.sourceProjectId != null) i.sourceProjectId!,
    for (final a in overdueActions)
      if (a.sourceProjectId != null) a.sourceProjectId!,
    for (final d in overdueDecisions)
      if (d.sourceProjectId != null) d.sourceProjectId!,
    for (final r in reports)
      if (r.sourceProjectId != null) r.sourceProjectId!,
    for (final a in activities)
      if (a.sourceProjectId != null) a.sourceProjectId!,
  };

  return [
    for (final src in sources)
      ProjectPulseStat(
        sourceId: src,
        rag: (wpsBySource[src] == null || wpsBySource[src]!.isEmpty)
            ? Rag.notStarted
            : StatusCalculator.computeProgrammeRag(wpsBySource[src]!),
        risks: riskCount(src),
        overdue: overdueCount(src),
        lastStatus: lastStatus(src),
        shareLevel: shareBySource[src],
        nextMilestone: nextMilestone(src),
      ),
  ];
}

class _PulseData {
  final List<ProjectPulseStat> rows;
  const _PulseData(this.rows);
}

class ProjectPulseStat {
  final String sourceId;
  final Rag rag;
  final int risks;
  final int overdue;
  final DateTime? lastStatus;
  /// 'full' | 'escalated' | null when the link isn't local.
  final String? shareLevel;
  final TimelineActivity? nextMilestone;
  const ProjectPulseStat({
    required this.sourceId,
    required this.rag,
    required this.risks,
    required this.overdue,
    required this.lastStatus,
    this.shareLevel,
    this.nextMilestone,
  });

  bool get isFullShare => CascadeShareLevels.isFull(shareLevel);
}

class _ProjectPulseRow extends StatelessWidget {
  final String label;
  final ProjectPulseStat row;
  final bool isLast;

  const _ProjectPulseRow({
    required this.label,
    required this.row,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Row(children: [
        _RagChip(row.rag),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Flexible(
                  child: Text(label,
                      style: const TextStyle(
                          color: KColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                if (row.shareLevel != null) ...[
                  const SizedBox(width: 8),
                  _ShareTag(full: row.isFullShare),
                ],
              ]),
              if (row.nextMilestone != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '◆ ${row.nextMilestone!.name} · '
                    '${_shortDate(row.nextMilestone!.startDate ?? row.nextMilestone!.endDate)}',
                    style: const TextStyle(
                        color: KColors.textDim, fontSize: 10.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        _metric('▲', '${row.risks}',
            row.isFullShare
                ? 'open ${row.risks == 1 ? 'risk' : 'risks'}'
                : 'escalated',
            row.risks > 0 ? KColors.amber : KColors.textMuted),
        const SizedBox(width: 14),
        _metric('⏰', '${row.overdue}', 'overdue',
            row.overdue > 0 ? KColors.red : KColors.textMuted),
        const SizedBox(width: 14),
        SizedBox(
          width: 62,
          child: Text(_ago(row.lastStatus),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: KColors.textMuted, fontSize: 11)),
        ),
      ]),
    );
  }

  Widget _metric(String icon, String value, String unit, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$icon$value',
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(width: 3),
      Text(unit,
          style: const TextStyle(color: KColors.textMuted, fontSize: 10)),
    ]);
  }

  static String _shortDate(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  static String _ago(DateTime? d) {
    if (d == null) return 'no status';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (days <= 0) return 'today';
    if (days == 1) return '1d ago';
    return '${days}d ago';
  }
}

class _RagChip extends StatelessWidget {
  final Rag rag;
  const _RagChip(this.rag);

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (rag) {
      Rag.green => (const Color(0xFF22c55e), const Color(0xFF0d3325)),
      Rag.amber => (KColors.amber, KColors.amberDim),
      Rag.red => (KColors.red, KColors.redDim),
      Rag.notStarted => (KColors.textMuted, KColors.surface2),
    };
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: fg, width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(rag.label.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: fg, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}

/// "FULL" / "ESC" — how much of the project this programme receives.
class _ShareTag extends StatelessWidget {
  final bool full;
  const _ShareTag({required this.full});

  @override
  Widget build(BuildContext context) {
    final colour = full ? KColors.phosphor : KColors.amber;
    return Tooltip(
      message: full
          ? 'Full detail: whole RAID, all actions and decisions, plan to '
              'task level'
          : 'Escalated only: the project PM chooses what you see',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          border: Border.all(color: colour.withValues(alpha: 0.6), width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(full ? 'FULL' : 'ESC',
            style: TextStyle(
                color: colour,
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6)),
      ),
    );
  }
}
