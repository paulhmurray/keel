import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import 'overview/programme_pulse_widget.dart';
import 'overview/velocity_row.dart';
import 'overview/pressures_section.dart';
import 'overview/coverage_row.dart';
import 'overview/overview_narrative_panel.dart';

class ProgrammeView extends StatelessWidget {
  final VoidCallback? onNavigateToTimeline;
  final VoidCallback? onNavigateToCharter;
  final VoidCallback? onNavigateToActions;
  final VoidCallback? onNavigateToDecisions;
  final VoidCallback? onNavigateToRaid;
  final VoidCallback? onNavigateToPeople;
  final VoidCallback? onNavigateToPlaybook;

  const ProgrammeView({
    super.key,
    this.onNavigateToTimeline,
    this.onNavigateToCharter,
    this.onNavigateToActions,
    this.onNavigateToDecisions,
    this.onNavigateToRaid,
    this.onNavigateToPeople,
    this.onNavigateToPlaybook,
  });

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;

    if (projectId == null) {
      return const Center(
        child: Text('Select a project to view programme details.',
            style: TextStyle(color: KColors.textDim)),
      );
    }

    return _OverviewBody(
      projectId: projectId,
      onNavigateToCharter: onNavigateToCharter,
      onNavigateToActions: onNavigateToActions,
      onNavigateToDecisions: onNavigateToDecisions,
      onNavigateToRaid: onNavigateToRaid,
      onNavigateToPeople: onNavigateToPeople,
      onNavigateToPlaybook: onNavigateToPlaybook,
    );
  }
}

class _OverviewBody extends StatelessWidget {
  final String projectId;
  final VoidCallback? onNavigateToCharter;
  final VoidCallback? onNavigateToActions;
  final VoidCallback? onNavigateToDecisions;
  final VoidCallback? onNavigateToRaid;
  final VoidCallback? onNavigateToPeople;
  final VoidCallback? onNavigateToPlaybook;

  const _OverviewBody({
    required this.projectId,
    this.onNavigateToCharter,
    this.onNavigateToActions,
    this.onNavigateToDecisions,
    this.onNavigateToRaid,
    this.onNavigateToPeople,
    this.onNavigateToPlaybook,
  });

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final projectName =
        context.watch<ProjectProvider>().currentProject?.name ?? 'Programme';

    return StreamBuilder<List<TimelineWorkPackage>>(
      stream: db.programmeGanttDao.watchWorkPackages(projectId),
      builder: (context, wpSnap) {
        final workPackages = wpSnap.data ?? [];

        return StreamBuilder<StatusSnapshot?>(
          stream: db.statusSnapshotDao
              .watchForProject(projectId)
              .map((list) => list.firstOrNull),
          builder: (context, snapSnap) {
            final lastSnapshot = snapSnap.data;

            return StreamBuilder<ProgrammeOverviewState?>(
              stream: db.programmeOverviewStateDao
                  .watchForProject(projectId),
              builder: (context, ovSnap) {
                final overviewState = ovSnap.data;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(Icons.dashboard,
                              color: KColors.amber, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'PROGRAMME OVERVIEW · $projectName',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Spacer(),
                          if (onNavigateToCharter != null)
                            TextButton.icon(
                              onPressed: onNavigateToCharter,
                              icon: const Icon(Icons.article_outlined,
                                  size: 13),
                              label: const Text('View Charter →',
                                  style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                  foregroundColor: KColors.textDim),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Section 1 — Pulse
                      _SectionLabel('PROGRAMME PULSE'),
                      const SizedBox(height: 8),
                      ProgrammePulseWidget(
                        projectId: projectId,
                        db: db,
                        workPackages: workPackages,
                        lastSnapshot: lastSnapshot,
                        overviewState: overviewState,
                        onEditNarrative: () {
                          // scroll to narrative section
                        },
                      ),
                      const SizedBox(height: 24),

                      // Section 2 — Velocity
                      _SectionLabel('VELOCITY  ·  last 7 days'),
                      const SizedBox(height: 8),
                      VelocityRow(
                        projectId: projectId,
                        db: db,
                        onTapActions: onNavigateToActions,
                        onTapDecisions: onNavigateToDecisions,
                        onTapRisks: onNavigateToRaid,
                        onTapDependencies: onNavigateToRaid,
                      ),
                      const SizedBox(height: 24),

                      // Section 3 — Pressures
                      PressuresSection(
                          projectId: projectId, db: db),
                      const SizedBox(height: 24),

                      // Section 4 — Coverage
                      _SectionLabel('COVERAGE'),
                      const SizedBox(height: 8),
                      CoverageRow(
                        projectId: projectId,
                        db: db,
                        onTapStakeholders: onNavigateToPeople,
                        onTapTeam: onNavigateToPeople,
                        onTapPlaybook: onNavigateToPlaybook,
                      ),
                      const SizedBox(height: 24),

                      // Section 5 — Narrative
                      OverviewNarrativePanel(
                        projectId: projectId,
                        db: db,
                        overviewState: overviewState,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: KColors.textMuted,
      ),
    );
  }
}
