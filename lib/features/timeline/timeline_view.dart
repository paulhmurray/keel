import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../actions/action_form.dart';
import '../decisions/decision_form.dart';
import '../raid/issue_form.dart';
import '../raid/dependency_form.dart';
import 'timeline_chart.dart' show TimelineEvent, TimelineEventType, TimelineChart, parseHexColor;
import 'gantt_chart.dart';
import 'workstream_form.dart';
import 'milestone_form.dart';

// ---------------------------------------------------------------------------
// Internal model (list view)
// ---------------------------------------------------------------------------

enum _EventType { action, decision, issue, dependency, milestone }

class _TimelineEvent {
  final String? id;
  final String title;
  final String? ref;
  final String? dateIso;
  final _EventType type;
  final String? owner;
  final bool isOverdue;
  final Object item;
  final Color? categoryColor;
  final String? linkedActionId;

  const _TimelineEvent({
    this.id,
    required this.title,
    this.ref,
    this.dateIso,
    required this.type,
    this.owner,
    required this.isOverdue,
    required this.item,
    this.categoryColor,
    this.linkedActionId,
  });
}

// ---------------------------------------------------------------------------
// Conversion helper (actions/decisions/issues/deps → chart event)
// ---------------------------------------------------------------------------

TimelineEvent _toChartEvent(_TimelineEvent e) {
  final type = switch (e.type) {
    _EventType.action     => TimelineEventType.action,
    _EventType.decision   => TimelineEventType.decision,
    _EventType.issue      => TimelineEventType.issue,
    _EventType.dependency => TimelineEventType.dependency,
    _EventType.milestone  => TimelineEventType.action, // not used for chart
  };

  DateTime? date;
  if (e.dateIso != null && e.dateIso!.isNotEmpty) {
    date = DateTime.tryParse(e.dateIso!);
  }

  return TimelineEvent(
    id: e.id,
    title: e.title,
    ref: e.ref,
    date: date,
    type: type,
    owner: e.owner,
    item: e.item,
    categoryColor: e.categoryColor,
    linkedActionId: e.linkedActionId,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

IconData _iconForType(_EventType t) {
  switch (t) {
    case _EventType.action:     return Icons.check_circle_outline;
    case _EventType.decision:   return Icons.gavel_outlined;
    case _EventType.issue:      return Icons.warning_amber_outlined;
    case _EventType.dependency: return Icons.link;
    case _EventType.milestone:  return Icons.diamond_outlined;
  }
}

(Color bg, Color fg) _colorsForType(_EventType t) {
  switch (t) {
    case _EventType.action:     return (KColors.blueDim, KColors.blue);
    case _EventType.decision:   return (KColors.amberDim, KColors.amber);
    case _EventType.issue:      return (KColors.redDim, KColors.red);
    case _EventType.dependency: return (KColors.phosDim, KColors.phosphor);
    case _EventType.milestone:  return (KColors.redDim.withValues(alpha: 0.3), KColors.text);
  }
}

// ---------------------------------------------------------------------------
// Main widget
// ---------------------------------------------------------------------------

class TimelineView extends StatelessWidget {
  const TimelineView({super.key});

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(
        child: Text(
          'Select a project to view the timeline.',
          style: TextStyle(color: KColors.textDim),
        ),
      );
    }
    return _TimelineContent(projectId: projectId);
  }
}

class _TimelineContent extends StatefulWidget {
  final String projectId;
  const _TimelineContent({required this.projectId});

  @override
  State<_TimelineContent> createState() => _TimelineContentState();
}

class _TimelineContentState extends State<_TimelineContent> {
  bool _showChart = true;
  bool _loading = true;
  List<_TimelineEvent> _events = [];
  List<GanttWorkstream> _ganttWorkstreams = [];
  List<Workstream> _rawWorkstreams = [];
  List<GanttMilestone> _ganttMilestones = [];
  List<Milestone> _rawMilestones = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(_TimelineContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _reload();
  }

  Future<void> _reload() async {
    final db = context.read<AppDatabase>();
    setState(() => _loading = true);
    final events = await _loadEvents(db);
    final (raw, gantt) = await _loadWorkstreams(db);
    final (rawMs, ganttMs) = await _loadMilestones(db);
    if (!mounted) return;
    setState(() {
      _events = events;
      _rawWorkstreams = raw;
      _ganttWorkstreams = gantt;
      _rawMilestones = rawMs;
      _ganttMilestones = ganttMs;
      _loading = false;
    });
  }

  Future<(List<Workstream>, List<GanttWorkstream>)> _loadWorkstreams(
      AppDatabase db) async {
    final wsList = await db.workstreamsDao.getForProject(widget.projectId);
    final links =
        await db.workstreamsDao.getLinksForProject(widget.projectId);
    final allActivities =
        await db.workstreamActivitiesDao.getForProject(widget.projectId);
    final persons =
        await db.peopleDao.getPersonsForProject(widget.projectId);
    final personMap = {for (final p in persons) p.id: p};

    final actsByWs = <String, List<WorkstreamActivity>>{};
    for (final act in allActivities) {
      actsByWs.putIfAbsent(act.workstreamId, () => []).add(act);
    }

    final gantt = wsList.map((ws) {
      final dependsOnIds = links
          .where((l) => l.toId == ws.id)
          .map((l) => l.fromId)
          .toList();

      final rawActs = actsByWs[ws.id] ?? [];
      rawActs.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final ganttActs = rawActs
          .map((act) => GanttActivity(
                id: act.id,
                name: act.name,
                status: act.status,
                start: act.startDate.isNotEmpty
                    ? DateTime.tryParse(act.startDate)
                    : null,
                end: act.endDate.isNotEmpty
                    ? DateTime.tryParse(act.endDate)
                    : null,
                ownerName: act.ownerId != null
                    ? personMap[act.ownerId!]?.name
                    : null,
                sortOrder: act.sortOrder,
              ))
          .toList();

      return GanttWorkstream(
        id: ws.id,
        name: ws.name,
        lane: ws.lane,
        lead: ws.lead,
        status: ws.status,
        start: ws.startDate != null ? DateTime.tryParse(ws.startDate!) : null,
        end: ws.endDate != null ? DateTime.tryParse(ws.endDate!) : null,
        dependsOnIds: dependsOnIds,
        activities: ganttActs,
      );
    }).toList();

    return (wsList, gantt);
  }

  Future<(List<Milestone>, List<GanttMilestone>)> _loadMilestones(
      AppDatabase db) async {
    final rawMs =
        await db.milestonesDao.getForProject(widget.projectId);
    final persons =
        await db.peopleDao.getPersonsForProject(widget.projectId);
    final personMap = {for (final p in persons) p.id: p};

    final ganttMs = rawMs
        .map((ms) => GanttMilestone(
              id: ms.id,
              name: ms.name,
              date: ms.date,
              ownerName: ms.ownerId != null
                  ? personMap[ms.ownerId!]?.name
                  : null,
              status: ms.status,
              isHardDeadline: ms.isHardDeadline,
              notes: ms.notes,
              workstreamId: ms.workstreamId,
            ))
        .toList();

    return (rawMs, ganttMs);
  }

  void _openEventDetail(TimelineEvent ev) {
    final db = context.read<AppDatabase>();
    final item = ev.item;
    if (item == null) return;
    switch (ev.type) {
      case TimelineEventType.action:
        showDialog(
          context: context,
          builder: (_) => ActionFormDialog(
              projectId: widget.projectId,
              db: db,
              action: item as ProjectAction,
              startInViewMode: true),
        ).then((_) => _reload());
      case TimelineEventType.decision:
        showDialog(
          context: context,
          builder: (_) => DecisionFormDialog(
              projectId: widget.projectId,
              db: db,
              decision: item as Decision,
              startInViewMode: true),
        ).then((_) => _reload());
      case TimelineEventType.issue:
        showDialog(
          context: context,
          builder: (_) => IssueFormDialog(
              projectId: widget.projectId,
              db: db,
              issue: item as Issue,
              startInViewMode: true),
        ).then((_) => _reload());
      case TimelineEventType.dependency:
        showDialog(
          context: context,
          builder: (_) => DependencyFormDialog(
              projectId: widget.projectId,
              db: db,
              dependency: item as ProgramDependency,
              startInViewMode: true),
        ).then((_) => _reload());
    }
  }

  void _openMilestoneDetail(GanttMilestone gm) {
    final db = context.read<AppDatabase>();
    final ms = _rawMilestones.where((m) => m.id == gm.id).firstOrNull;
    showDialog(
      context: context,
      builder: (_) => MilestoneFormDialog(
          projectId: widget.projectId, db: db, milestone: ms),
    ).then((_) => _reload());
  }

  void _openActivityEdit(GanttActivity act, GanttWorkstream gws) {
    final db = context.read<AppDatabase>();
    final ws = _rawWorkstreams.where((w) => w.id == gws.id).firstOrNull;
    if (ws == null) return;
    showDialog(
      context: context,
      builder: (_) => WorkstreamFormDialog(
          projectId: widget.projectId, db: db, workstream: ws),
    ).then((_) => _reload());
  }

  void _addWorkstream() {
    final db = context.read<AppDatabase>();
    showDialog(
      context: context,
      builder: (_) =>
          WorkstreamFormDialog(projectId: widget.projectId, db: db),
    ).then((_) => _reload());
  }

  void _addMilestone() {
    final db = context.read<AppDatabase>();
    showDialog(
      context: context,
      builder: (_) =>
          MilestoneFormDialog(projectId: widget.projectId, db: db),
    ).then((_) => _reload());
  }

  void _editWorkstream(Workstream ws) {
    final db = context.read<AppDatabase>();
    showDialog(
      context: context,
      builder: (_) => WorkstreamFormDialog(
          projectId: widget.projectId, db: db, workstream: ws),
    ).then((_) => _reload());
  }

  Future<void> _deleteWorkstream(Workstream ws) async {
    final db = context.read<AppDatabase>();
    await db.workstreamsDao.deleteWorkstream(ws.id);
    _reload();
  }

  Future<List<_TimelineEvent>> _loadEvents(AppDatabase db) async {
    final today = du.toIsoDate(DateTime.now());

    final actions = await db.actionsDao.getActionsForProject(widget.projectId);
    final decisions =
        await db.decisionsDao.getDecisionsForProject(widget.projectId);
    final issues = await db.raidDao.getIssuesForProject(widget.projectId);
    final dependencies =
        await db.raidDao.getDependenciesForProject(widget.projectId);
    final milestones =
        await db.milestonesDao.getForProject(widget.projectId);
    final persons =
        await db.peopleDao.getPersonsForProject(widget.projectId);
    final categories =
        await db.actionCategoriesDao.getForProject(widget.projectId);
    final catMap = {for (final c in categories) c.id: c};
    final personMap = {for (final p in persons) p.id: p};

    final events = <_TimelineEvent>[];

    for (final a in actions) {
      if (a.status != 'open') continue;
      final overdue = a.dueDate != null &&
          a.dueDate!.isNotEmpty &&
          a.dueDate!.compareTo(today) < 0;
      final cat = a.categoryId != null ? catMap[a.categoryId!] : null;
      events.add(_TimelineEvent(
        id: a.id,
        title: a.description,
        ref: a.ref,
        dateIso: a.dueDate,
        type: _EventType.action,
        owner: a.owner,
        isOverdue: overdue,
        item: a,
        categoryColor: cat != null ? parseHexColor(cat.color) : null,
        linkedActionId: a.linkedActionId,
      ));
    }

    for (final d in decisions) {
      if (d.status != 'pending') continue;
      final overdue = d.dueDate != null &&
          d.dueDate!.isNotEmpty &&
          d.dueDate!.compareTo(today) < 0;
      events.add(_TimelineEvent(
        title: d.description,
        ref: d.ref,
        dateIso: d.dueDate,
        type: _EventType.decision,
        owner: d.decisionMaker,
        isOverdue: overdue,
        item: d,
      ));
    }

    for (final i in issues) {
      if (i.status != 'open') continue;
      final overdue = i.dueDate != null &&
          i.dueDate!.isNotEmpty &&
          i.dueDate!.compareTo(today) < 0;
      events.add(_TimelineEvent(
        title: i.description,
        ref: i.ref,
        dateIso: i.dueDate,
        type: _EventType.issue,
        owner: i.owner,
        isOverdue: overdue,
        item: i,
      ));
    }

    for (final dep in dependencies) {
      if (dep.status != 'open') continue;
      final overdue = dep.dueDate != null &&
          dep.dueDate!.isNotEmpty &&
          dep.dueDate!.compareTo(today) < 0;
      events.add(_TimelineEvent(
        title: dep.description,
        ref: dep.ref,
        dateIso: dep.dueDate,
        type: _EventType.dependency,
        owner: dep.owner,
        isOverdue: overdue,
        item: dep,
      ));
    }

    // Milestones in list view — exclude achieved milestones
    for (final ms in milestones) {
      if (ms.status == 'achieved') continue;
      final overdue = ms.date.isNotEmpty && ms.date.compareTo(today) < 0;
      final ownerName =
          ms.ownerId != null ? personMap[ms.ownerId!]?.name : null;
      events.add(_TimelineEvent(
        id: ms.id,
        title: ms.name,
        dateIso: ms.date,
        type: _EventType.milestone,
        owner: ownerName,
        isOverdue: overdue,
        item: ms,
      ));
    }

    return events;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final chartEvents = _events
        .where((e) =>
            e.type != _EventType.milestone &&
            e.dateIso != null &&
            e.dateIso!.isNotEmpty)
        .map(_toChartEvent)
        .toList();

    final today = du.toIsoDate(DateTime.now());
    final now = DateTime.now();
    final endOfWeek = du.toIsoDate(now.add(const Duration(days: 6)));
    final endOfMonth =
        du.toIsoDate(DateTime(now.year, now.month + 1, 0));

    final overdue = <_TimelineEvent>[];
    final thisWeek = <_TimelineEvent>[];
    final thisMonth = <_TimelineEvent>[];
    final future = <_TimelineEvent>[];
    final noDate = <_TimelineEvent>[];

    for (final e in _events) {
      final d = e.dateIso;
      if (d == null || d.isEmpty) {
        noDate.add(e);
      } else if (d.compareTo(today) < 0) {
        overdue.add(e);
      } else if (d.compareTo(endOfWeek) <= 0) {
        thisWeek.add(e);
      } else if (d.compareTo(endOfMonth) <= 0) {
        thisMonth.add(e);
      } else {
        future.add(e);
      }
    }

    int byDate(_TimelineEvent a, _TimelineEvent b) =>
        (a.dateIso ?? '').compareTo(b.dateIso ?? '');
    overdue.sort(byDate);
    thisWeek.sort(byDate);
    thisMonth.sort(byDate);
    future.sort(byDate);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.timeline, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('SCHEDULE',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 12),
              const Text(
                'Your operational view. What needs your attention today or this week.',
                style: TextStyle(color: KColors.textMuted, fontSize: 11),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _addWorkstream,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Workstream'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _addMilestone,
                icon: const Icon(Icons.diamond_outlined, size: 14),
                label: const Text('Add Milestone'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColors.surface2,
                  foregroundColor: KColors.text,
                  side: const BorderSide(color: KColors.border2),
                ),
              ),
              const SizedBox(width: 10),
              _ViewToggle(
                showChart: _showChart,
                onChanged: (v) => setState(() => _showChart = v),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Gantt chart ───────────────────────────────────────────────
          if (_showChart) ...[
            Container(
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
                      const Expanded(
                        child: Text('WORKSTREAMS & EVENTS',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.15,
                                color: KColors.textMuted)),
                      ),
                      _StatusLegend(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_ganttWorkstreams.isEmpty &&
                      _ganttMilestones.isEmpty)
                    _EmptyWorkstreams(
                      projectId: widget.projectId,
                      context: context,
                      chartEvents: chartEvents,
                      onAdd: _addWorkstream,
                    )
                  else
                    GanttChart(
                      workstreams: _ganttWorkstreams,
                      events: chartEvents,
                      milestones: _ganttMilestones,
                      onEventTap: _openEventDetail,
                      onMilestoneTap: _openMilestoneDetail,
                      onActivityTap: _openActivityEdit,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Workstream list (edit / delete) ────────────────────────
            if (_rawWorkstreams.isNotEmpty) ...[
              const _WorkstreamListHeader(),
              const SizedBox(height: 8),
              ..._rawWorkstreams.map((ws) => _WorkstreamRow(
                    workstream: ws,
                    onEdit: () => _editWorkstream(ws),
                    onDelete: () => _deleteWorkstream(ws),
                  )),
              const SizedBox(height: 24),
            ],

            // ── Milestones list ────────────────────────────────────────
            if (_rawMilestones.isNotEmpty) ...[
              const _MilestonesListHeader(),
              const SizedBox(height: 8),
              ..._rawMilestones.map((ms) => _MilestoneRow(
                    milestone: ms,
                    onTap: () {
                      final db = context.read<AppDatabase>();
                      showDialog(
                        context: context,
                        builder: (_) => MilestoneFormDialog(
                            projectId: widget.projectId,
                            db: db,
                            milestone: ms),
                      ).then((_) => _reload());
                    },
                  )),
              const SizedBox(height: 24),
            ],
          ],

          // ── Deadline list ─────────────────────────────────────────────
          if (_events.isEmpty && _ganttWorkstreams.isNotEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('No upcoming deadlines.',
                    style:
                        TextStyle(color: KColors.textDim, fontSize: 13)),
              ),
            )
          else if (_events.isEmpty && _ganttWorkstreams.isEmpty)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timeline_outlined,
                      size: 40, color: KColors.textMuted),
                  SizedBox(height: 16),
                  Text('No workstreams or deadlines yet.',
                      style: TextStyle(
                          color: KColors.textDim, fontSize: 14)),
                  SizedBox(height: 8),
                  Text(
                    'Add a workstream above, or add due dates\nto actions, decisions, issues and dependencies.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: KColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overdue.isNotEmpty) ...[
                  _SectionHeader(
                      label: 'OVERDUE', dotColor: KColors.red),
                  const SizedBox(height: 8),
                  ...overdue.map((e) => _EventRow(
                      event: e,
                      projectId: widget.projectId,
                      db: context.read<AppDatabase>())),
                  const SizedBox(height: 20),
                ],
                if (thisWeek.isNotEmpty) ...[
                  _SectionHeader(
                      label: 'THIS WEEK', dotColor: KColors.amber),
                  const SizedBox(height: 8),
                  ...thisWeek.map((e) => _EventRow(
                      event: e,
                      projectId: widget.projectId,
                      db: context.read<AppDatabase>())),
                  const SizedBox(height: 20),
                ],
                if (thisMonth.isNotEmpty) ...[
                  _SectionHeader(
                      label: 'THIS MONTH',
                      dotColor: KColors.textMuted),
                  const SizedBox(height: 8),
                  ...thisMonth.map((e) => _EventRow(
                      event: e,
                      projectId: widget.projectId,
                      db: context.read<AppDatabase>())),
                  const SizedBox(height: 20),
                ],
                if (future.isNotEmpty) ...[
                  _SectionHeader(
                      label: 'FUTURE', dotColor: KColors.textMuted),
                  const SizedBox(height: 8),
                  ...future.map((e) => _EventRow(
                      event: e,
                      projectId: widget.projectId,
                      db: context.read<AppDatabase>())),
                  const SizedBox(height: 20),
                ],
                if (noDate.isNotEmpty) ...[
                  _SectionHeader(
                      label: 'NO DATE', dotColor: KColors.textMuted),
                  const SizedBox(height: 8),
                  ...noDate.map((e) => _EventRow(
                      event: e,
                      projectId: widget.projectId,
                      db: context.read<AppDatabase>())),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty workstreams prompt
// ---------------------------------------------------------------------------

class _EmptyWorkstreams extends StatelessWidget {
  final String projectId;
  final BuildContext context;
  final List<TimelineEvent> chartEvents;
  final VoidCallback onAdd;

  const _EmptyWorkstreams({
    required this.projectId,
    required this.context,
    required this.chartEvents,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext ctx) {
    return Column(
      children: [
        if (chartEvents.isNotEmpty) ...[
          TimelineChart(events: chartEvents, height: 180, compact: false),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KColors.surface2,
            border: Border.all(color: KColors.border2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              const Icon(Icons.view_timeline_outlined,
                  size: 18, color: KColors.textMuted),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No workstreams yet',
                        style: TextStyle(
                            color: KColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text(
                      'Add workstreams to see swim lanes, Gantt bars and dependency arrows.',
                      style:
                          TextStyle(color: KColors.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Workstream'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Workstream list header + editable row
// ---------------------------------------------------------------------------

class _WorkstreamListHeader extends StatelessWidget {
  const _WorkstreamListHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('WORKSTREAMS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
              color: KColors.textMuted,
            )),
      ],
    );
  }
}

class _WorkstreamRow extends StatelessWidget {
  final Workstream workstream;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _WorkstreamRow({
    required this.workstream,
    required this.onEdit,
    required this.onDelete,
  });

  Color _statusColor(String s) {
    switch (s) {
      case 'in_progress': return KColors.amber;
      case 'complete':    return KColors.phosphor;
      case 'blocked':     return KColors.red;
      default:            return KColors.textMuted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'not_started': return 'Not started';
      case 'in_progress': return 'In progress';
      case 'complete':    return 'Complete';
      case 'blocked':     return 'Blocked';
      default:            return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(workstream.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(workstream.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                if (workstream.lead != null ||
                    workstream.lane.isNotEmpty)
                  Text(
                    [
                      if (workstream.lane.isNotEmpty) workstream.lane,
                      if (workstream.lead != null)
                        'Lead: ${workstream.lead}',
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 11, color: KColors.textDim),
                  ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _statusLabel(workstream.status),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: KColors.textDim,
            tooltip: 'Edit workstream',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            color: KColors.red,
            tooltip: 'Delete workstream',
            onPressed: onDelete,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Milestones list header + row
// ---------------------------------------------------------------------------

class _MilestonesListHeader extends StatelessWidget {
  const _MilestonesListHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text('MILESTONES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
              color: KColors.textMuted,
            )),
      ],
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final Milestone milestone;
  final VoidCallback onTap;

  const _MilestoneRow({required this.milestone, required this.onTap});

  Color _statusColor(String s, bool isHard) {
    if (isHard) return KColors.red;
    switch (s) {
      case 'achieved': return KColors.phosphor;
      case 'at_risk':  return KColors.amber;
      case 'missed':   return KColors.red;
      default:         return KColors.text;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'achieved': return 'Achieved';
      case 'at_risk':  return 'At Risk';
      case 'missed':   return 'Missed';
      default:         return 'Upcoming';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(milestone.status, milestone.isHardDeadline);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: KColors.surface,
          border: Border.all(color: KColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(Icons.diamond, size: 14, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(milestone.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(
                    [
                      milestone.date,
                      _statusLabel(milestone.status),
                      if (milestone.isHardDeadline) 'Hard Deadline',
                    ].join(' · '),
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined,
                size: 14, color: KColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status legend
// ---------------------------------------------------------------------------

class _StatusLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      ('Not started', KColors.textMuted),
      ('In progress', KColors.phosphor),
      ('Complete', KColors.phosphor),
      ('Blocked', KColors.red),
    ];
    return Wrap(
      spacing: 12,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: item.$2.withValues(alpha: 0.2),
                border: Border.all(color: item.$2, width: 1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(item.$1,
                style: const TextStyle(
                    color: KColors.textDim, fontSize: 10)),
          ],
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// View toggle
// ---------------------------------------------------------------------------

class _ViewToggle extends StatelessWidget {
  final bool showChart;
  final ValueChanged<bool> onChanged;

  const _ViewToggle({required this.showChart, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KColors.surface2,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: KColors.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            icon: Icons.bar_chart_outlined,
            label: 'Chart',
            active: showChart,
            onTap: () => onChanged(true),
            isFirst: true,
          ),
          _ToggleButton(
            icon: Icons.list_outlined,
            label: 'List',
            active: !showChart,
            onTap: () => onChanged(false),
            isFirst: false,
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool isFirst;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? KColors.amber.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(2) : Radius.zero,
            right: isFirst ? Radius.zero : const Radius.circular(2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: active ? KColors.amber : KColors.textDim),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? KColors.amber : KColors.textDim,
                fontSize: 11,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color dotColor;

  const _SectionHeader({required this.label, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          margin: const EdgeInsets.only(right: 6),
        ),
        Text(label,
            style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
            )),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Event row
// ---------------------------------------------------------------------------

class _EventRow extends StatelessWidget {
  final _TimelineEvent event;
  final String projectId;
  final AppDatabase db;

  const _EventRow({
    required this.event,
    required this.projectId,
    required this.db,
  });

  void _openDetail(BuildContext context) {
    final item = event.item;
    switch (event.type) {
      case _EventType.action:
        showDialog(
          context: context,
          builder: (_) => ActionFormDialog(
              projectId: projectId,
              db: db,
              action: item as ProjectAction,
              startInViewMode: true),
        );
      case _EventType.decision:
        showDialog(
          context: context,
          builder: (_) => DecisionFormDialog(
              projectId: projectId,
              db: db,
              decision: item as Decision,
              startInViewMode: true),
        );
      case _EventType.issue:
        showDialog(
          context: context,
          builder: (_) => IssueFormDialog(
              projectId: projectId,
              db: db,
              issue: item as Issue,
              startInViewMode: true),
        );
      case _EventType.dependency:
        showDialog(
          context: context,
          builder: (_) => DependencyFormDialog(
              projectId: projectId,
              db: db,
              dependency: item as ProgramDependency,
              startInViewMode: true),
        );
      case _EventType.milestone:
        showDialog(
          context: context,
          builder: (_) => MilestoneFormDialog(
              projectId: projectId,
              db: db,
              milestone: item as Milestone),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (typeBg, typeFg) = _colorsForType(event.type);
    final typeIcon = _iconForType(event.type);
    final isMilestone = event.type == _EventType.milestone;
    final ms = isMilestone ? event.item as Milestone : null;
    final milestoneColor = ms != null
        ? (ms.isHardDeadline
            ? KColors.red
            : switch (ms.status) {
                'achieved' => KColors.phosphor,
                'at_risk'  => KColors.amber,
                'missed'   => KColors.red,
                _          => KColors.text,
              })
        : typeFg;

    return InkWell(
      onTap: () => _openDetail(context),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: KColors.surface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: KColors.border),
        ),
        child: Row(
          children: [
            // Type icon box
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isMilestone
                    ? milestoneColor.withValues(alpha: 0.15)
                    : typeBg,
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: Icon(typeIcon,
                  size: 13,
                  color: isMilestone ? milestoneColor : typeFg),
            ),
            const SizedBox(width: 10),

            // Ref badge
            if (event.ref != null && event.ref!.isNotEmpty) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: typeBg,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(event.ref!,
                    style: TextStyle(
                        color: typeFg,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
            ],

            // Hard deadline badge
            if (ms != null && ms.isHardDeadline) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: KColors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Text('HARD',
                    style: TextStyle(
                        color: KColors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
            ],

            // Title
            Expanded(
              child: Text(
                event.title,
                style: const TextStyle(color: KColors.text, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Owner
            if (event.owner != null && event.owner!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  event.owner!,
                  style: const TextStyle(
                      color: KColors.textDim, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],

            // Due date chip
            if (event.dateIso != null && event.dateIso!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: event.isOverdue
                      ? KColors.redDim
                      : event.dateIso!.compareTo(du.toIsoDate(
                                  DateTime.now()
                                      .add(const Duration(days: 7)))) <=
                              0
                          ? KColors.amberDim
                          : KColors.surface2,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  du.formatDate(event.dateIso),
                  style: TextStyle(
                    color: event.isOverdue
                        ? KColors.red
                        : event.dateIso!.compareTo(du.toIsoDate(
                                    DateTime.now()
                                        .add(const Duration(days: 7)))) <=
                                0
                            ? KColors.amber
                            : KColors.textDim,
                    fontSize: 10,
                    fontWeight: event.isOverdue
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
