import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/status_chip.dart';
import '../timeline/timeline_chart.dart';
import 'workstream_form.dart';

class ProgrammeView extends StatelessWidget {
  final VoidCallback? onNavigateToTimeline;

  const ProgrammeView({super.key, this.onNavigateToTimeline});

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;

    if (projectId == null) {
      return const Center(
        child: Text('Select a project to view programme details.',
            style: TextStyle(color: KColors.textDim)),
      );
    }

    return _ProgrammeContent(
      projectId: projectId,
      onNavigateToTimeline: onNavigateToTimeline,
    );
  }
}

class _ProgrammeContent extends StatelessWidget {
  final String projectId;
  final VoidCallback? onNavigateToTimeline;

  const _ProgrammeContent({
    required this.projectId,
    this.onNavigateToTimeline,
  });

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.dashboard, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'PROGRAMME OVERVIEW',
                  style: Theme.of(context).textTheme.headlineSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Programme Overview grid
          StreamBuilder<ProgrammeOverview?>(
            stream: db.programmeDao.watchOverviewForProject(projectId),
            builder: (context, snap) {
              return _OverviewSection(
                overview: snap.data,
                projectId: projectId,
                db: db,
              );
            },
          ),

          const SizedBox(height: 24),

          // Workstreams section
          Row(
            children: [
              const Flexible(child: _SectionLabel('WORKSTREAMS')),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _addWorkstream(context, projectId, db),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Workstream'),
              ),
            ],
          ),
          const SizedBox(height: 10),

          StreamBuilder<List<Workstream>>(
            stream: db.programmeDao.watchWorkstreamsForProject(projectId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final workstreams = snap.data!;
              if (workstreams.isEmpty) {
                return _EmptyWorkstreams(
                  onAdd: () => _addWorkstream(context, projectId, db),
                );
              }
              return Column(
                children: workstreams
                    .map((w) => _WorkstreamRow(
                          workstream: w,
                          db: db,
                          projectId: projectId,
                        ))
                    .toList(),
              );
            },
          ),

          const SizedBox(height: 24),
          _TimelineSummaryCard(
            projectId: projectId,
            db: db,
            onNavigateToTimeline: onNavigateToTimeline,
          ),
        ],
      ),
    );
  }

  void _addWorkstream(
      BuildContext context, String projectId, AppDatabase db) {
    showDialog(
      context: context,
      builder: (_) => WorkstreamFormDialog(projectId: projectId, db: db),
    );
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
    return Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: KColors.textMuted,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview Section — grid of _ProgCard + edit button
// ---------------------------------------------------------------------------

class _OverviewSection extends StatefulWidget {
  final ProgrammeOverview? overview;
  final String projectId;
  final AppDatabase db;

  const _OverviewSection(
      {required this.overview, required this.projectId, required this.db});

  @override
  State<_OverviewSection> createState() => _OverviewSectionState();
}

class _OverviewSectionState extends State<_OverviewSection> {
  bool _editing = false;
  late TextEditingController _visionCtrl;
  late TextEditingController _objectivesCtrl;
  late TextEditingController _scopeCtrl;
  late TextEditingController _sponsorCtrl;
  late TextEditingController _pmCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final o = widget.overview;
    _visionCtrl = TextEditingController(text: o?.vision ?? '');
    _objectivesCtrl = TextEditingController(text: o?.objectives ?? '');
    _scopeCtrl = TextEditingController(text: o?.scope ?? '');
    _sponsorCtrl = TextEditingController(text: o?.sponsor ?? '');
    _pmCtrl = TextEditingController(text: o?.programmeManager ?? '');
  }

  @override
  void didUpdateWidget(_OverviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overview != widget.overview && !_editing) {
      _initControllers();
    }
  }

  @override
  void dispose() {
    _visionCtrl.dispose();
    _objectivesCtrl.dispose();
    _scopeCtrl.dispose();
    _sponsorCtrl.dispose();
    _pmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = widget.overview?.id ?? const Uuid().v4();
    await widget.db.programmeDao.upsertOverview(
      ProgrammeOverviewsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        vision: Value(_visionCtrl.text.trim().isEmpty
            ? null
            : _visionCtrl.text.trim()),
        objectives: Value(_objectivesCtrl.text.trim().isEmpty
            ? null
            : _objectivesCtrl.text.trim()),
        scope: Value(_scopeCtrl.text.trim().isEmpty
            ? null
            : _scopeCtrl.text.trim()),
        sponsor: Value(_sponsorCtrl.text.trim().isEmpty
            ? null
            : _sponsorCtrl.text.trim()),
        programmeManager: Value(_pmCtrl.text.trim().isEmpty
            ? null
            : _pmCtrl.text.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Flexible(child: _SectionLabel('OVERVIEW')),
            const SizedBox(width: 8),
            if (_editing) ...[
              TextButton(
                onPressed: () => setState(() => _editing = false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ] else
              TextButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined, size: 12),
                label: const Text('Edit Overview'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_editing) ...[
          _OverviewField(label: 'Vision', controller: _visionCtrl),
          _OverviewField(
              label: 'Objectives',
              controller: _objectivesCtrl,
              maxLines: 3),
          _OverviewField(
              label: 'Scope', controller: _scopeCtrl, maxLines: 2),
          Row(
            children: [
              Expanded(
                child: _OverviewField(
                    label: 'Sponsor', controller: _sponsorCtrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OverviewField(
                    label: 'Programme Manager', controller: _pmCtrl),
              ),
            ],
          ),
        ] else
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth < 300 ? 1 : 2;
              final ratio = constraints.maxWidth < 300 ? 4.0 : 3.0;
              return GridView(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: ratio,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _ProgCard(label: 'Vision', value: widget.overview?.vision),
                  _ProgCard(label: 'Scope', value: widget.overview?.scope),
                  _ProgCard(
                      label: 'Sponsor', value: widget.overview?.sponsor),
                  _ProgCard(
                      label: 'Programme Manager',
                      value: widget.overview?.programmeManager),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ProgCard extends StatelessWidget {
  final String label;
  final String? value;

  const _ProgCard({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
              color: KColors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              value ?? '—',
              style: TextStyle(
                fontSize: 12,
                color: value != null ? KColors.text : KColors.textMuted,
                fontStyle:
                    value != null ? FontStyle.normal : FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;

  const _OverviewField(
      {required this.label, required this.controller, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Workstream Row
// ---------------------------------------------------------------------------

Color _wsColor(String status) {
  switch (status.toLowerCase()) {
    case 'green':
      return KColors.phosphor;
    case 'amber':
      return KColors.amber;
    case 'red':
      return KColors.red;
    default:
      return KColors.textDim;
  }
}

class _WorkstreamRow extends StatelessWidget {
  final Workstream workstream;
  final AppDatabase db;
  final String projectId;

  const _WorkstreamRow(
      {required this.workstream, required this.db, required this.projectId});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 28,
            color: _wsColor(workstream.status),
            margin: const EdgeInsets.only(right: 12),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(workstream.name,
                    style: const TextStyle(
                        fontSize: 12,
                        color: KColors.text,
                        fontWeight: FontWeight.w500)),
                if (workstream.notes != null &&
                    workstream.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(workstream.notes!,
                      style: const TextStyle(
                          fontSize: 10, color: KColors.textDim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (workstream.lead != null && workstream.lead!.isNotEmpty) ...[
            Flexible(
              child: Text('Lead: ${workstream.lead}',
                  style: const TextStyle(fontSize: 11, color: KColors.textDim),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 12),
          ],
          StatusChip(status: workstream.status),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                size: 16, color: KColors.textMuted),
            onSelected: (val) {
              if (val == 'edit') {
                showDialog(
                  context: context,
                  builder: (_) => WorkstreamFormDialog(
                    projectId: projectId,
                    db: db,
                    workstream: workstream,
                  ),
                );
              } else if (val == 'delete') {
                _confirmDelete(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Workstream'),
        content: Text('Delete "${workstream.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
            onPressed: () {
              db.programmeDao.deleteWorkstream(workstream.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EmptyWorkstreams extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyWorkstreams({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 36, color: KColors.textMuted),
            const SizedBox(height: 12),
            const Text('No workstreams yet',
                style: TextStyle(color: KColors.textDim)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Workstream'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline Summary Card
// ---------------------------------------------------------------------------

class _TimelineSummaryCard extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final VoidCallback? onNavigateToTimeline;

  const _TimelineSummaryCard({
    required this.projectId,
    required this.db,
    this.onNavigateToTimeline,
  });

  Future<List<TimelineEvent>> _loadEvents() async {
    final actions = await db.actionsDao.getActionsForProject(projectId);
    final decisions =
        await db.decisionsDao.getDecisionsForProject(projectId);
    final issues = await db.raidDao.getIssuesForProject(projectId);
    final dependencies =
        await db.raidDao.getDependenciesForProject(projectId);

    final events = <TimelineEvent>[];

    for (final a in actions) {
      if (a.status != 'open') continue;
      final d = a.dueDate;
      if (d == null || d.isEmpty) continue;
      events.add(TimelineEvent(
        title: a.description,
        ref: a.ref,
        date: DateTime.tryParse(d),
        type: TimelineEventType.action,
        owner: a.owner,
      ));
    }

    for (final dec in decisions) {
      if (dec.status != 'pending') continue;
      final d = dec.dueDate;
      if (d == null || d.isEmpty) continue;
      events.add(TimelineEvent(
        title: dec.description,
        ref: dec.ref,
        date: DateTime.tryParse(d),
        type: TimelineEventType.decision,
        owner: dec.decisionMaker,
      ));
    }

    for (final i in issues) {
      if (i.status != 'open') continue;
      final d = i.dueDate;
      if (d == null || d.isEmpty) continue;
      events.add(TimelineEvent(
        title: i.description,
        ref: i.ref,
        date: DateTime.tryParse(d),
        type: TimelineEventType.issue,
        owner: i.owner,
      ));
    }

    for (final dep in dependencies) {
      if (dep.status != 'open') continue;
      final d = dep.dueDate;
      if (d == null || d.isEmpty) continue;
      events.add(TimelineEvent(
        title: dep.description,
        ref: dep.ref,
        date: DateTime.tryParse(d),
        type: TimelineEventType.dependency,
        owner: dep.owner,
      ));
    }

    return events;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
              const Icon(Icons.calendar_month_outlined,
                  size: 14, color: KColors.amber),
              const SizedBox(width: 8),
              const Text(
                'UPCOMING — NEXT 14 DAYS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.15,
                  color: KColors.textMuted,
                ),
              ),
              const Spacer(),
              if (onNavigateToTimeline != null)
                TextButton(
                  onPressed: onNavigateToTimeline,
                  child: const Text('View all \u2192'),
                ),
            ],
          ),
          const Divider(height: 16),
          FutureBuilder<List<TimelineEvent>>(
            future: _loadEvents(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                );
              }

              final upcomingEvents = snap.data ?? [];

              if (upcomingEvents.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No upcoming deadlines — add due dates to actions, '
                    'decisions, issues or dependencies.',
                    style: TextStyle(
                      color: KColors.textDim,
                      fontSize: 12,
                    ),
                  ),
                );
              }

              return TimelineChart(
                events: upcomingEvents,
                height: 160,
                compact: true,
              );
            },
          ),
        ],
      ),
    );
  }
}
