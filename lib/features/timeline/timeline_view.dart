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
import 'timeline_chart.dart';

// ---------------------------------------------------------------------------
// Internal model (list view only)
// ---------------------------------------------------------------------------

enum _EventType { action, decision, issue, dependency }

class _TimelineEvent {
  final String title;
  final String? ref;
  final String? dateIso;
  final _EventType type;
  final String? owner;
  final bool isOverdue;
  final Object item; // original DB object for opening the detail dialog

  const _TimelineEvent({
    required this.title,
    this.ref,
    this.dateIso,
    required this.type,
    this.owner,
    required this.isOverdue,
    required this.item,
  });
}

// ---------------------------------------------------------------------------
// Conversion helper
// ---------------------------------------------------------------------------

TimelineEvent _toChartEvent(_TimelineEvent e) {
  final type = switch (e.type) {
    _EventType.action => TimelineEventType.action,
    _EventType.decision => TimelineEventType.decision,
    _EventType.issue => TimelineEventType.issue,
    _EventType.dependency => TimelineEventType.dependency,
  };

  DateTime? date;
  if (e.dateIso != null && e.dateIso!.isNotEmpty) {
    date = DateTime.tryParse(e.dateIso!);
  }

  return TimelineEvent(
    title: e.title,
    ref: e.ref,
    date: date,
    type: type,
    owner: e.owner,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

IconData _iconForType(_EventType t) {
  switch (t) {
    case _EventType.action:
      return Icons.check_circle_outline;
    case _EventType.decision:
      return Icons.gavel_outlined;
    case _EventType.issue:
      return Icons.warning_amber_outlined;
    case _EventType.dependency:
      return Icons.link;
  }
}

(Color bg, Color fg) _colorsForType(_EventType t) {
  switch (t) {
    case _EventType.action:
      return (KColors.blueDim, KColors.blue);
    case _EventType.decision:
      return (KColors.amberDim, KColors.amber);
    case _EventType.issue:
      return (KColors.redDim, KColors.red);
    case _EventType.dependency:
      return (KColors.phosDim, KColors.phosphor);
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

  Future<List<_TimelineEvent>> _loadEvents(AppDatabase db) async {
    final today = du.toIsoDate(DateTime.now());

    final actions =
        await db.actionsDao.getActionsForProject(widget.projectId);
    final decisions =
        await db.decisionsDao.getDecisionsForProject(widget.projectId);
    final issues =
        await db.raidDao.getIssuesForProject(widget.projectId);
    final dependencies =
        await db.raidDao.getDependenciesForProject(widget.projectId);

    final events = <_TimelineEvent>[];

    for (final a in actions) {
      if (a.status != 'open') continue;
      final overdue = a.dueDate != null &&
          a.dueDate!.isNotEmpty &&
          a.dueDate!.compareTo(today) < 0;
      events.add(_TimelineEvent(
        title: a.description,
        ref: a.ref,
        dateIso: a.dueDate,
        type: _EventType.action,
        owner: a.owner,
        isOverdue: overdue,
        item: a,
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

    return events;
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();

    return FutureBuilder<List<_TimelineEvent>>(
      future: _loadEvents(db),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'Error loading timeline: ${snap.error}',
              style: const TextStyle(color: KColors.red),
            ),
          );
        }

        final events = snap.data ?? [];

        if (events.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timeline_outlined,
                    size: 40, color: KColors.textMuted),
                SizedBox(height: 16),
                Text(
                  'No upcoming deadlines',
                  style:
                      TextStyle(color: KColors.textDim, fontSize: 14),
                ),
                SizedBox(height: 8),
                Text(
                  'Open actions, decisions, issues and dependencies\nwith due dates will appear here.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: KColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final chartEvents = events
            .where((e) => e.dateIso != null && e.dateIso!.isNotEmpty)
            .map(_toChartEvent)
            .toList();

        final today = du.toIsoDate(DateTime.now());
        final now = DateTime.now();
        final endOfWeek =
            du.toIsoDate(now.add(const Duration(days: 6)));
        final endOfMonth =
            du.toIsoDate(DateTime(now.year, now.month + 1, 0));

        final overdue = <_TimelineEvent>[];
        final thisWeek = <_TimelineEvent>[];
        final thisMonth = <_TimelineEvent>[];
        final future = <_TimelineEvent>[];
        final noDate = <_TimelineEvent>[];

        for (final e in events) {
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

        Widget listSection = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (overdue.isNotEmpty) ...[
              _SectionHeader(
                label: 'OVERDUE',
                dotColor: KColors.red,
              ),
              const SizedBox(height: 8),
              ...overdue.map((e) => _EventRow(event: e, projectId: widget.projectId, db: db)),
              const SizedBox(height: 20),
            ],
            if (thisWeek.isNotEmpty) ...[
              _SectionHeader(
                label: 'THIS WEEK',
                dotColor: KColors.amber,
              ),
              const SizedBox(height: 8),
              ...thisWeek.map((e) => _EventRow(event: e, projectId: widget.projectId, db: db)),
              const SizedBox(height: 20),
            ],
            if (thisMonth.isNotEmpty) ...[
              _SectionHeader(
                label: 'THIS MONTH',
                dotColor: KColors.textMuted,
              ),
              const SizedBox(height: 8),
              ...thisMonth.map((e) => _EventRow(event: e, projectId: widget.projectId, db: db)),
              const SizedBox(height: 20),
            ],
            if (future.isNotEmpty) ...[
              _SectionHeader(
                label: 'FUTURE',
                dotColor: KColors.textMuted,
              ),
              const SizedBox(height: 8),
              ...future.map((e) => _EventRow(event: e, projectId: widget.projectId, db: db)),
              const SizedBox(height: 20),
            ],
            if (noDate.isNotEmpty) ...[
              _SectionHeader(
                label: 'NO DATE',
                dotColor: KColors.textMuted,
              ),
              const SizedBox(height: 8),
              ...noDate.map((e) => _EventRow(event: e, projectId: widget.projectId, db: db)),
            ],
          ],
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.timeline, color: KColors.amber, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'TIMELINE',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  _ViewToggle(
                    showChart: _showChart,
                    onChanged: (v) => setState(() => _showChart = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),

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
                      const Text(
                        'VISUAL TIMELINE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.15,
                          color: KColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TimelineChart(
                        events: chartEvents,
                        height: 260,
                        compact: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              listSection,
            ],
          ),
        );
      },
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
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? KColors.amber.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst
                ? const Radius.circular(2)
                : Radius.zero,
            right:
                isFirst ? Radius.zero : const Radius.circular(2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? KColors.amber : KColors.textDim,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? KColors.amber : KColors.textDim,
                fontSize: 11,
                fontWeight: active
                    ? FontWeight.w600
                    : FontWeight.normal,
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

  const _SectionHeader({
    required this.label,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration:
              BoxDecoration(color: dotColor, shape: BoxShape.circle),
          margin: const EdgeInsets.only(right: 6),
        ),
        Text(
          label,
          style: const TextStyle(
            color: KColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
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
            startInViewMode: true,
          ),
        );
      case _EventType.decision:
        showDialog(
          context: context,
          builder: (_) => DecisionFormDialog(
            projectId: projectId,
            db: db,
            decision: item as Decision,
            startInViewMode: true,
          ),
        );
      case _EventType.issue:
        showDialog(
          context: context,
          builder: (_) => IssueFormDialog(
            projectId: projectId,
            db: db,
            issue: item as Issue,
            startInViewMode: true,
          ),
        );
      case _EventType.dependency:
        showDialog(
          context: context,
          builder: (_) => DependencyFormDialog(
            projectId: projectId,
            db: db,
            dependency: item as ProgramDependency,
            startInViewMode: true,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (typeBg, typeFg) = _colorsForType(event.type);
    final typeIcon = _iconForType(event.type);

    return InkWell(
      onTap: () => _openDetail(context),
      borderRadius: BorderRadius.circular(3),
      child: Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              color: typeBg,
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.center,
            child: Icon(typeIcon, size: 13, color: typeFg),
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
              child: Text(
                event.ref!,
                style: TextStyle(
                  color: typeFg,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Title
          Expanded(
            child: Text(
              event.title,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Owner
          if (event.owner != null && event.owner!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              event.owner!,
              style: const TextStyle(
                color: KColors.textDim,
                fontSize: 11,
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
                    : event.dateIso!.compareTo(
                                du.toIsoDate(DateTime.now().add(
                                    const Duration(days: 7)))) <=
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
                      : event.dateIso!.compareTo(
                                  du.toIsoDate(DateTime.now().add(
                                      const Duration(days: 7)))) <=
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
