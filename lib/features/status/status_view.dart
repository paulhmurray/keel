import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/status/status_calculator.dart';
import '../../core/status/status_snapshot_scheduler.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import 'pending_decisions_panel.dart';
import 'playbook_stage_summary.dart';
import 'programme_rag_widget.dart';
import 'status_counts_row.dart';
import 'status_export_dialog.dart';
import 'status_narrative_panel.dart';
import 'top_risks_panel.dart';
import 'upcoming_milestones_list.dart';
import 'workstream_health_table.dart';

class StatusView extends StatelessWidget {
  const StatusView({super.key});

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectProvider>().currentProject;
    if (project == null) {
      return const Center(
          child: Text('Select a project.',
              style: TextStyle(color: KColors.textDim)));
    }
    return _StatusContent(project: project);
  }
}

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

class _StatusContent extends StatefulWidget {
  final Project project;
  const _StatusContent({required this.project});

  @override
  State<_StatusContent> createState() => _StatusContentState();
}

class _StatusContentState extends State<_StatusContent> {
  bool _loading = true;
  ProgrammeStatusData? _data;
  List<String> _monthLabels = [];
  String? _narrative;
  String? _loadError;

  String get _projectId => widget.project.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_StatusContent old) {
    super.didUpdateWidget(old);
    if (old.project.id != widget.project.id) _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    setState(() { _loading = true; _loadError = null; });
    try {
      // Trigger snapshot if needed (fire and forget)
      StatusSnapshotScheduler.maybeCreateSnapshot(db, _projectId);

      final wps = await db.programmeGanttDao.getWorkPackages(_projectId);
      final allActs =
          await db.programmeGanttDao.getActivitiesForProject(_projectId);
      final risks    = await db.raidDao.getRisksForProject(_projectId);
      final decisions =
          await db.decisionsDao.getDecisionsForProject(_projectId);
      final actions  = await db.actionsDao.getActionsForProject(_projectId);
      final header   = await db.programmeGanttDao.getHeader(_projectId);

      // Parse month labels
      List<String> months = [];
      if (header?.monthLabels != null) {
        try {
          months =
              (jsonDecode(header!.monthLabels!) as List).cast<String>();
        } catch (_) {}
      }
      if (months.isEmpty) months = List.generate(24, (i) => 'M$i');

      // Snapshot for trend
      final lastSnapshot =
          await db.statusSnapshotDao.getMostRecent(_projectId);
      final prevWsRag = lastSnapshot != null
          ? StatusCalculator.parseWorkstreamRag(lastSnapshot.workstreamRag)
          : <String, String>{};
      final prevProgrammeRag = lastSnapshot != null
          ? ragFromString(lastSnapshot.programmeRag)
          : null;

      // Compute RAGs
      final programmeRag = StatusCalculator.computeProgrammeRag(wps);
      final programmeTrend =
          StatusCalculator.computeTrend(programmeRag, prevProgrammeRag);

      final wsStatuses = wps.map((wp) {
        final rag = ragFromString(wp.ragStatus);
        final prevRagStr = prevWsRag[wp.id];
        final prevRag =
            prevRagStr != null ? ragFromString(prevRagStr) : null;
        final trend = StatusCalculator.computeTrend(rag, prevRag);
        return WorkstreamRagStatus(
          wp: wp,
          rag: rag,
          trend: trend,
          previousRagLabel: prevRag?.label,
        );
      }).toList();

      // Upcoming milestones
      final upcoming = StatusCalculator.upcomingMilestones(
          allActs, months, days: 30);

      // Top risks
      final top = StatusCalculator.topRisks(risks, limit: 3);

      // Pending decisions (sorted by due date)
      final pending = decisions
          .where((d) => d.status == 'pending')
          .toList()
        ..sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });

      // Counts
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final overdueCount = actions.where((a) =>
          a.status == 'open' &&
          a.dueDate != null &&
          a.dueDate!.compareTo(today) < 0).length;
      final openCount = actions.where((a) => a.status == 'open').length;
      final openRisksCount = risks.where((r) => r.status == 'open').length;

      // Playbook
      final pp = await db.playbookDao.getProjectPlaybook(_projectId);
      PlaybookStage? currentStage;
      ProjectStageProgressesData? stageProgress;
      if (pp != null) {
        final progresses =
            await db.playbookDao.getProgressForProjectPlaybook(pp.id);
        // Find the first in-progress stage, or first not-started
        final inProgress = progresses
            .where((p) => p.status == 'in_progress')
            .toList();
        final notStarted = progresses
            .where((p) => p.status == 'not_started')
            .toList();
        final target = inProgress.isNotEmpty
            ? inProgress.first
            : (notStarted.isNotEmpty ? notStarted.first : null);
        if (target != null) {
          stageProgress = target;
          currentStage = await db.playbookDao.getStageById(target.stageId);
        }
      }

      if (!mounted) return;
      setState(() {
        _data = ProgrammeStatusData(
          programmeRag:        programmeRag,
          programmeTrend:      programmeTrend,
          previousRagLabel:    prevProgrammeRag?.label,
          workstreams:         wsStatuses,
          upcomingMilestones:  upcoming,
          topRisks:            top,
          pendingDecisions:    pending,
          overdueActionsCount: overdueCount,
          openActionsCount:    openCount,
          openRisksCount:      openRisksCount,
          projectPlaybook:     pp,
          currentStage:        currentStage,
          stageProgress:       stageProgress,
        );
        _monthLabels = months;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loadError = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final now      = DateTime.now();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
          child: Text('Error: $_loadError',
              style: const TextStyle(color: KColors.red)));
    }

    final data = _data!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Top bar ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(children: [
            const Icon(Icons.monitor_heart_outlined,
                color: KColors.amber, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('STATUS — ${widget.project.name}',
                      style: Theme.of(context).textTheme.headlineSmall,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    'Week of ${_formatDate(now)}  ·  '
                    'Weekly programme health',
                    style: const TextStyle(
                        color: KColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Snapshot now button
            OutlinedButton.icon(
              onPressed: () async {
                final db = context.read<AppDatabase>();
                await StatusSnapshotScheduler.createNow(db, _projectId);
                _load();
              },
              icon: const Icon(Icons.camera_alt_outlined, size: 14),
              label: const Text('Snapshot', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            // Export button
            ElevatedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => StatusExportDialog(
                  projectName: widget.project.name,
                  data:        data,
                  monthLabels: _monthLabels,
                  narrative:   _narrative,
                  weekOf:      now,
                ),
              ),
              icon: const Icon(Icons.file_download_outlined, size: 14),
              label: const Text('Export', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // ── Body ─────────────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Programme RAG
                _SectionLabel('PROGRAMME RAG'),
                ProgrammeRagWidget(
                  rag:              data.programmeRag,
                  trend:            data.programmeTrend,
                  previousRagLabel: data.previousRagLabel,
                  projectId:        _projectId,
                  db:               context.read<AppDatabase>(),
                  wps: data.workstreams.map((w) => w.wp).toList(),
                ),
                const SizedBox(height: 20),

                // Workstreams
                _SectionLabel('WORKSTREAMS'),
                WorkstreamHealthTable(workstreams: data.workstreams),
                const SizedBox(height: 20),

                // Upcoming milestones
                _SectionLabel('UPCOMING MILESTONES (NEXT 30 DAYS)'),
                UpcomingMilestonesList(
                  milestones:  data.upcomingMilestones,
                  monthLabels: _monthLabels,
                ),
                const SizedBox(height: 20),

                // Top risks
                _SectionLabel('TOP RISKS'),
                TopRisksPanel(risks: data.topRisks),
                const SizedBox(height: 20),

                // Pending decisions
                _SectionLabel('PENDING DECISIONS'),
                PendingDecisionsPanel(decisions: data.pendingDecisions),
                const SizedBox(height: 20),

                // Playbook stage
                _SectionLabel('CURRENT PLAYBOOK STAGE'),
                PlaybookStageSummary(
                  stage:    data.currentStage,
                  progress: data.stageProgress,
                ),
                const SizedBox(height: 20),

                // Counts
                _SectionLabel('COUNTS'),
                StatusCountsRow(
                  overdueActions:    data.overdueActionsCount,
                  openActions:       data.openActionsCount,
                  pendingDecisions:  data.pendingDecisionsCount,
                  openRisks:         data.openRisksCount,
                ),
                const SizedBox(height: 24),

                // Narrative
                _SectionLabel('STATUS NARRATIVE'),
                StatusNarrativePanel(
                  data:              data,
                  settings:          settings,
                  projectName:       widget.project.name,
                  initialNarrative:  _narrative,
                  onNarrativeChanged: (v) => setState(() => _narrative = v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15)),
    );
  }
}
