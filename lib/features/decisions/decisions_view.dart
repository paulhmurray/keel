import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cascade/cascade_service.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../core/raid/dependency_plan_link.dart';
import '../../core/raid/dependency_timeline.dart';
import '../../core/raid/raid_lifecycle.dart';
import '../../core/raid/raid_conversion_service.dart' show RaidKind;
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/cascaded_source_badge.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/source_badge.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../canvas/canvas_drag_source.dart';
import '../canvas/in_canvas_indicator.dart';
import '../programme/overdue_cascade_panel.dart';
import 'decision_form.dart';
import '../raid/dependency_slack_chip.dart';
import '../../shared/widgets/closed_toggle.dart';
import '../../core/programme/source_filter.dart';
import '../../shared/widgets/source_filter_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DecisionsView extends StatefulWidget {
  final bool triggerNew;

  const DecisionsView({super.key, this.triggerNew = false});

  @override
  State<DecisionsView> createState() => _DecisionsViewState();
}

class _DecisionsViewState extends State<DecisionsView> {
  // Plan context for the per-card slack chip — loaded once; plan dates
  // change rarely compared with the decision stream.
  Map<String, TimelineActivity> _activitiesById = const {};
  String? _month0Date;
  String? _loadedForProject;
  // Made decisions age out of the list two weeks after they were
  // decided; the toggle (per project) brings them back.
  bool _showClosed = false;
  SourceFilter _sourceFilter = SourceFilter.all;

  Future<void> _loadPrefs(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool('keel_decisions_show_closed_$projectId') ?? false;
    if (mounted) setState(() => _showClosed = v);
  }

  Future<void> _toggleShowClosed() async {
    setState(() => _showClosed = !_showClosed);
    final pid = _loadedForProject;
    if (pid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keel_decisions_show_closed_$pid', _showClosed);
  }

  Future<void> _loadPlan(String projectId) async {
    final db = context.read<AppDatabase>();
    final acts = await db.programmeGanttDao.getActivitiesForProject(projectId);
    final header = await db.programmeGanttDao.getHeader(projectId);
    if (!mounted) return;
    setState(() {
      _activitiesById = {for (final a in acts) a.id: a};
      _month0Date = header?.month0Date;
      _loadedForProject = projectId;
    });
  }

  DependencySlack? _slackFor(Decision d) {
    if (kDecisionMadeStatuses.contains(d.status)) return null;
    final a = d.planActivityId != null ? _activitiesById[d.planActivityId] : null;
    if (a == null) return null;
    return dependencySlack(
      dueDate: d.dueDate,
      dependencyType: 'inbound',
      activityStartDate: a.startDate,
      activityEndDate: a.endDate,
      activityStartMonth: a.startMonth,
      activityEndMonth: a.endMonth,
      month0Date: _month0Date,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.triggerNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final projectId = context.read<ProjectProvider>().currentProjectId;
        if (projectId == null) return;
        final db = context.read<AppDatabase>();
        showDialog(
          context: context,
          builder: (_) => DecisionFormDialog(projectId: projectId, db: db),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project to view decisions.',
          style: TextStyle(color: KColors.textDim)));
    }

    final db = context.read<AppDatabase>();
    if (_loadedForProject != projectId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadPlan(projectId);
        _loadPrefs(projectId);
      });
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.gavel, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('DECISIONS',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) =>
                      DecisionFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Decision'),
              ),
              const Spacer(),
              StreamBuilder<List<Decision>>(
                stream: db.decisionsDao.watchDecisionsForProject(projectId),
                builder: (_, snap) => ClosedToggle(
                  showClosed: _showClosed,
                  hiddenCount: partitionAgedOut<Decision>(
                    snap.data ?? const [],
                    kind: RaidKind.decision,
                    status: (d) => d.status,
                    closedAt: (d) => d.decidedAt,
                    updatedAt: (d) => d.updatedAt,
                    showClosed: false,
                  ).hidden.length,
                  onTap: _toggleShowClosed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Programme-only overdue-decisions roll-up. Quiet (renders
          // nothing) on project-kind installs and on programmes with
          // no overdue cascaded decisions.
          const OverdueCascadePanel(kind: OverdueCascadeKind.decision),
          SourceFilterBar(
            filter: _sourceFilter,
            padding: const EdgeInsets.only(bottom: 10),
            onChanged: (f) => setState(() => _sourceFilter = f),
          ),
          // List
          Expanded(
            child: StreamBuilder<List<Decision>>(
              stream: db.decisionsDao.watchDecisionsForProject(projectId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final part = partitionAgedOut<Decision>(
                  snap.data!,
                  kind: RaidKind.decision,
                  status: (d) => d.status,
                  closedAt: (d) => d.decidedAt,
                  updatedAt: (d) => d.updatedAt,
                  showClosed: _showClosed,
                );
                final items = _sourceFilter.apply(part.visible,
                    sourceProjectId: (d) => d.sourceProjectId,
                    escalatedAt: (d) => d.escalatedAt);
                if (items.isEmpty && part.hidden.isNotEmpty) {
                  return HiddenClosedNotice(
                      hiddenCount: part.hidden.length,
                      onShow: _toggleShowClosed);
                }
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.gavel_outlined,
                            size: 40, color: KColors.textMuted),
                        const SizedBox(height: 12),
                        const Text('No decisions yet.',
                            style: TextStyle(color: KColors.textDim)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => DecisionFormDialog(
                                projectId: projectId, db: db),
                          ),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Decision'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _DecisionCard(
                    decision: items[i],
                    db: db,
                    projectId: projectId,
                    slack: _slackFor(items[i]),
                    activityName: items[i].planActivityId != null
                        ? _activitiesById[items[i].planActivityId]?.name
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Color _decisionBarColor(String status) {
  switch (status.toLowerCase()) {
    case 'pending':
      return KColors.blue;
    case 'decided':
    case 'approved':
      return KColors.phosphor;
    default:
      return KColors.textMuted;
  }
}

class _DecisionCard extends StatelessWidget {
  final Decision decision;
  final AppDatabase db;
  final String projectId;
  final DependencySlack? slack;
  final String? activityName;

  const _DecisionCard({
    required this.decision,
    required this.db,
    required this.projectId,
    this.slack,
    this.activityName,
  });

  @override
  Widget build(BuildContext context) {
    return CanvasDragSource(
      itemType: 'decision',
      itemId: decision.id,
      title: decision.description,
      body: decision.rationale,
      child: Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => DecisionFormDialog(
              projectId: projectId, db: db, decision: decision,
              startInViewMode: true),
        ),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Colour bar
              Container(
                width: 2,
                height: 48,
                color: _decisionBarColor(decision.status),
                margin: const EdgeInsets.only(right: 12),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (decision.ref != null) ...[
                          Text(
                            decision.ref!,
                            style: const TextStyle(
                                color: KColors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            decision.description,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                                color: KColors.text),
                          ),
                        ),
                        StatusChip(status: decision.status),
                        const SizedBox(width: 6),
                        if (decision.escalatedAt != null &&
                            decision.sourceProjectId == null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: KColors.amberDim,
                              border: Border.all(
                                  color: KColors.amber, width: 0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Tooltip(
                              message:
                                  'Shared with linked programmes by the PM',
                              child: Text(
                                '↑ SHARED',
                                style: TextStyle(
                                  color: KColors.amber,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        if (decision.sourceProjectId != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: CascadedSourceBadge(
                                sourceProjectId: decision.sourceProjectId),
                          ),
                        if (decision.sourceProjectId == null)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert,
                                size: 16, color: KColors.textMuted),
                            onSelected: (val) async {
                              if (val == 'edit') {
                                await showDialog(
                                  context: context,
                                  builder: (_) => DecisionFormDialog(
                                      projectId: projectId,
                                      db: db,
                                      decision: decision),
                                );
                                if (context.mounted) {
                                  final fresh = await db.decisionsDao
                                      .getDecisionById(decision.id);
                                  if (fresh != null && context.mounted) {
                                    await _cascadeFor(context, db)
                                        .pushDecision(fresh);
                                  }
                                }
                              } else if (val == 'escalate') {
                                await db.decisionsDao
                                    .setDecisionEscalated(
                                        decision.id, true);
                                final fresh = await db.decisionsDao
                                    .getDecisionById(decision.id);
                                if (fresh != null && context.mounted) {
                                  await _cascadeFor(context, db)
                                      .pushDecision(fresh);
                                }
                              } else if (val == 'unescalate') {
                                await db.decisionsDao.setDecisionEscalated(decision.id, false);
                          // Re-push with the flag off: full-detail links keep
                          // the row unflagged, escalated-only links get a tombstone.
                          final fresh = await db.decisionsDao.getDecisionById(decision.id);
                          if (fresh != null && context.mounted) {
                            await _cascadeFor(context, db).pushDecision(fresh);
                          }
                              } else if (val == 'delete') {
                                if (context.mounted) {
                                  await _cascadeFor(context, db)
                                      .tombstoneRaidItem(
                                    projectId: projectId,
                                    itemKind: CascadeKinds.decision,
                                    itemId: decision.id,
                                  );
                                }
                                await DependencyPlanLink.remove(
                                    db, projectId, decision.id,
                                    kind: PlanLinkKind.decision);
                                await db.decisionsDao
                                    .deleteDecision(decision.id);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'edit', child: Text('Edit')),
                              if (decision.escalatedAt == null)
                                const PopupMenuItem(
                                    value: 'escalate',
                                    child:
                                        Text('Share with programme'))
                              else
                                const PopupMenuItem(
                                    value: 'unescalate',
                                    child: Text('Stop sharing')),
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete')),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (decision.decisionMaker != null &&
                                  decision.decisionMaker!.isNotEmpty) ...[
                                const Icon(Icons.person_outline,
                                    size: 11, color: KColors.textDim),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(decision.decisionMaker!,
                                      style: const TextStyle(
                                          color: KColors.textDim, fontSize: 11),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 10),
                              ],
                              if (decision.dueDate != null &&
                                  decision.dueDate!.isNotEmpty) ...[
                                const Icon(Icons.calendar_today_outlined,
                                    size: 11, color: KColors.textDim),
                                const SizedBox(width: 3),
                                Text(du.formatDate(decision.dueDate),
                                    style: const TextStyle(
                                        color: KColors.textDim, fontSize: 11)),
                                const SizedBox(width: 4),
                              ],
                            ],
                          ),
                        ),
                        SourceBadge(source: decision.source),
                        const SizedBox(width: 6),
                        InCanvasIndicator(
                          itemType: 'decision',
                          itemId: decision.id,
                        ),
                      ],
                    ),
                    if (activityName != null || slack != null) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (activityName != null)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.timeline,
                                  size: 11, color: KColors.textMuted),
                              const SizedBox(width: 3),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 260),
                                child: Text('Waiting: $activityName',
                                    style: const TextStyle(
                                        color: KColors.textDim, fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                          if (slack != null)
                            DependencySlackChip(slack: slack!, compact: true),
                        ],
                      ),
                    ],
                    if (decision.rationale != null &&
                        decision.rationale!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Rationale: ${decision.rationale}',
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 11)),
                    ],
                    if (decision.outcome != null &&
                        decision.outcome!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('Outcome: ${decision.outcome}',
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// CascadeService for the decision row's escalate / unescalate /
/// delete handlers.
CascadeService _cascadeFor(BuildContext context, AppDatabase db) =>
    buildCascadeService(context);
