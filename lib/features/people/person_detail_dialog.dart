import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../core/export/pdf_exporter.dart';
import '../../core/people/person_workload.dart';
import '../../providers/project_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;

/// One person, everything pinned on them, and a way to hand it to them.
///
/// The lower half is driven entirely by [PersonWorkload] so the screen
/// and the exported brief agree on what counts as "theirs".
class PersonDetailDialog extends StatefulWidget {
  final Person person;
  final AppDatabase db;
  final String projectId;

  const PersonDetailDialog({
    super.key,
    required this.person,
    required this.db,
    required this.projectId,
  });

  @override
  State<PersonDetailDialog> createState() => _PersonDetailDialogState();
}

class _PersonDetailDialogState extends State<PersonDetailDialog> {
  late Future<PersonWorkload> _workload;
  PersonWorkload? _last;
  bool _showClosed = false;

  Person get person => widget.person;
  AppDatabase get db => widget.db;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _workload = PersonWorkload.load(db, person)
        ..then((w) {
          if (mounted) setState(() => _last = w);
        });
    });
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _export(PersonWorkload workload) async {
    final projectName =
        context.read<ProjectProvider>().currentProject?.name ?? 'Project';
    final myName = context.read<SettingsProvider>().settings.myName;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ExportBriefDialog(
        personName: person.name,
        openCount: workload.openCount,
        closedCount: workload.all.length - workload.openCount,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final path = await PdfExporter.exportPersonBrief(
        workload: workload,
        projectName: projectName,
        preparedBy: myName,
        includeClosed: result,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Brief saved: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: KColors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 760,
        child: FutureBuilder<PersonWorkload>(
          future: _workload,
          builder: (context, snap) {
            // Fall back to the previous result while a reload is in
            // flight so a mark-closed doesn't flash the spinner.
            final workload = snap.data ?? _last;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, workload),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._contactAndProfile(),
                        if (workload == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                                child: CircularProgressIndicator()),
                          )
                        else
                          _WorkloadPanel(
                            workload: workload,
                            db: db,
                            showClosed: _showClosed,
                            onToggleClosed: (v) =>
                                setState(() => _showClosed = v),
                            onChanged: _reload,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, PersonWorkload? workload) {
    final canExport = workload != null && !workload.isEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: KColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: KColors.blueDim,
            radius: 28,
            child: Text(
              _initials(person.name),
              style: const TextStyle(
                  color: KColors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                if ((person.role ?? '').isNotEmpty)
                  Text(person.role!,
                      style: const TextStyle(
                          color: KColors.textDim, fontSize: 13)),
                if ((person.organisation ?? '').isNotEmpty)
                  Text(person.organisation!,
                      style: const TextStyle(
                          color: KColors.textDim, fontSize: 13)),
              ],
            ),
          ),
          Tooltip(
            message: canExport
                ? 'Save a PDF of everything assigned to ${person.name}, '
                    'ready to send them'
                : 'Nothing is assigned to ${person.name} yet',
            child: OutlinedButton.icon(
              onPressed: canExport ? () => _export(workload) : null,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Export brief'),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  List<Widget> _contactAndProfile() {
    final hasContact = (person.email ?? '').isNotEmpty ||
        (person.phone ?? '').isNotEmpty ||
        (person.teamsHandle ?? '').isNotEmpty;
    return [
      if (hasContact) ...[
        const _SectionHeader('Contact'),
        const SizedBox(height: 8),
        if ((person.email ?? '').isNotEmpty)
          _InfoRow(Icons.email_outlined, person.email!),
        if ((person.phone ?? '').isNotEmpty)
          _InfoRow(Icons.phone_outlined, person.phone!),
        if ((person.teamsHandle ?? '').isNotEmpty)
          _InfoRow(Icons.chat_outlined, person.teamsHandle!),
        const SizedBox(height: 16),
      ],
      if (person.isStakeholder)
        FutureBuilder<StakeholderProfile?>(
          future: db.peopleDao.getStakeholderByPersonId(person.id),
          builder: (ctx, snap) {
            final p = snap.data;
            if (p == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader('Stakeholder Profile'),
                const SizedBox(height: 8),
                if (p.influence != null)
                  _InfoRow(Icons.trending_up_outlined,
                      'Influence: ${p.influence}'),
                if (p.stance != null)
                  _InfoRow(Icons.sentiment_satisfied_outlined,
                      'Stance: ${p.stance}'),
                if ((p.engagementStrategy ?? '').isNotEmpty)
                  _LabelledText('Engagement strategy', p.engagementStrategy!),
                if ((p.notes ?? '').isNotEmpty) _LabelledText('Notes', p.notes!),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      if (person.personType == 'colleague')
        FutureBuilder<ColleagueProfile?>(
          future: db.peopleDao.getColleagueByPersonId(person.id),
          builder: (ctx, snap) {
            final p = snap.data;
            if (p == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader('Colleague Profile'),
                const SizedBox(height: 8),
                if ((p.team ?? '').isNotEmpty)
                  _InfoRow(Icons.group_outlined, 'Team: ${p.team}'),
                if (p.directReport)
                  const _InfoRow(Icons.person_pin_outlined, 'Direct report'),
                if ((p.workingStyle ?? '').isNotEmpty)
                  _LabelledText('Working style', p.workingStyle!),
                if ((p.notes ?? '').isNotEmpty) _LabelledText('Notes', p.notes!),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Workload panel — one collapsible section per populated register
// ---------------------------------------------------------------------------

class _WorkloadPanel extends StatelessWidget {
  final PersonWorkload workload;
  final AppDatabase db;
  final bool showClosed;
  final ValueChanged<bool> onToggleClosed;
  final VoidCallback onChanged;

  const _WorkloadPanel({
    required this.workload,
    required this.db,
    required this.showClosed,
    required this.onToggleClosed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final overdue = workload.overdueCount(today);
    final closedTotal = workload.all.length - workload.openCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _SectionHeader('Assigned to them')),
            const SizedBox(width: 12),
            if (closedTotal > 0)
              InkWell(
                onTap: () => onToggleClosed(!showClosed),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        showClosed
                            ? Icons.check_box_outlined
                            : Icons.check_box_outline_blank,
                        size: 14,
                        color: KColors.textDim,
                      ),
                      const SizedBox(width: 6),
                      Text('Show completed ($closedTotal)',
                          style: const TextStyle(
                              color: KColors.textDim, fontSize: 11)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          workload.isEmpty
              ? 'Nothing in this project is assigned to ${workload.person.name}.'
              : [
                  '${workload.openCount} open',
                  if (overdue > 0) '$overdue overdue',
                ].join(' · '),
          style: TextStyle(
              color: overdue > 0 ? KColors.red : KColors.textDim,
              fontSize: 12),
        ),
        const SizedBox(height: 10),
        for (final kind in workload.populatedKinds)
          _WorkloadSection(
            kind: kind,
            buckets: workload.buckets(kind, today),
            showClosed: showClosed,
            db: db,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _WorkloadSection extends StatelessWidget {
  final WorkloadKind kind;
  final WorkloadBuckets buckets;
  final bool showClosed;
  final AppDatabase db;
  final VoidCallback onChanged;

  const _WorkloadSection({
    required this.kind,
    required this.buckets,
    required this.showClosed,
    required this.db,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (buckets.activeCount == 0 && !(showClosed && buckets.closed.isNotEmpty)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(kind), size: 14, color: KColors.textDim),
              const SizedBox(width: 6),
              Text(
                kind.label.toUpperCase(),
                style: const TextStyle(
                    color: KColors.textDim,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6),
              ),
              const SizedBox(width: 6),
              Text('${buckets.activeCount}',
                  style: const TextStyle(
                      color: KColors.textMuted, fontSize: 11)),
              if (buckets.overdue.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('${buckets.overdue.length} overdue',
                    style: const TextStyle(
                        color: KColors.red,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          for (final i in buckets.overdue)
            _WorkloadRow(item: i, tone: _Tone.overdue, db: db, onChanged: onChanged),
          for (final i in buckets.open)
            _WorkloadRow(item: i, tone: _Tone.open, db: db, onChanged: onChanged),
          if (showClosed)
            for (final i in buckets.closed)
              _WorkloadRow(item: i, tone: _Tone.closed, db: db, onChanged: onChanged),
        ],
      ),
    );
  }

  static IconData _iconFor(WorkloadKind kind) => switch (kind) {
        WorkloadKind.risk => Icons.warning_amber_outlined,
        WorkloadKind.issue => Icons.error_outline,
        WorkloadKind.assumption => Icons.help_outline,
        WorkloadKind.dependency => Icons.link_outlined,
        WorkloadKind.action => Icons.task_alt_outlined,
        WorkloadKind.decision => Icons.gavel_outlined,
        WorkloadKind.milestone => Icons.flag_outlined,
        WorkloadKind.planActivity => Icons.view_timeline_outlined,
        WorkloadKind.workstream => Icons.account_tree_outlined,
        WorkloadKind.workstreamActivity => Icons.checklist_outlined,
        WorkloadKind.contribution => Icons.group_work_outlined,
      };
}

enum _Tone { overdue, open, closed }

class _WorkloadRow extends StatelessWidget {
  final WorkloadItem item;
  final _Tone tone;
  final AppDatabase db;
  final VoidCallback onChanged;

  const _WorkloadRow({
    required this.item,
    required this.tone,
    required this.db,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final closed = tone == _Tone.closed;
    final colour = switch (tone) {
      _Tone.overdue => KColors.red,
      _Tone.open => null,
      _Tone.closed => KColors.textDim,
    };
    final meta = <String>[
      if ((item.ref ?? '').isNotEmpty) item.ref!,
      if (item.role != WorkloadRole.owner) item.role.label,
      if ((item.qualifier ?? '').isNotEmpty)
        item.kind == WorkloadKind.contribution
            ? 'Owner: ${item.qualifier}'
            : item.qualifier!,
      item.status.replaceAll('_', ' '),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              closed ? Icons.check_circle_outline : Icons.radio_button_unchecked,
              size: 15,
              color: closed
                  ? KColors.phosphor
                  : tone == _Tone.overdue
                      ? KColors.red
                      : KColors.textDim,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 13,
                    color: colour,
                    decoration: closed ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  meta.join(' · '),
                  style: const TextStyle(
                      color: KColors.textMuted, fontSize: 11),
                ),
                if ((item.detail ?? '').isNotEmpty && !closed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: KColors.textDim, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          if (item.dueDate != null) ...[
            const SizedBox(width: 12),
            Text(
              du.formatDate(item.dueDate),
              style: TextStyle(
                fontSize: 11,
                color: tone == _Tone.overdue ? KColors.red : KColors.textDim,
              ),
            ),
          ],
          if (item.kind == WorkloadKind.action && !closed)
            SizedBox(
              height: 24,
              width: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.check, size: 16),
                tooltip: 'Mark closed',
                onPressed: () async {
                  final current = await db.actionsDao.getActionById(item.id);
                  if (current == null) return;
                  await db.actionsDao.upsertAction(ProjectActionsCompanion(
                    id: Value(current.id),
                    projectId: Value(current.projectId),
                    description: Value(current.description),
                    status: const Value('closed'),
                    updatedAt: Value(DateTime.now()),
                  ));
                  onChanged();
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Export options
// ---------------------------------------------------------------------------

class _ExportBriefDialog extends StatefulWidget {
  final String personName;
  final int openCount;
  final int closedCount;
  const _ExportBriefDialog({
    required this.personName,
    required this.openCount,
    required this.closedCount,
  });

  @override
  State<_ExportBriefDialog> createState() => _ExportBriefDialogState();
}

class _ExportBriefDialogState extends State<_ExportBriefDialog> {
  bool _includeClosed = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Text('Export brief for ${widget.personName}',
          style: const TextStyle(color: KColors.text, fontSize: 14)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A print-styled PDF listing the ${widget.openCount} open items '
            'assigned to ${widget.personName} in this project: what each '
            'one is, its status, due date and the current note. Stakeholder '
            'profile, engagement notes and journal entries are never '
            'included.',
            style: const TextStyle(color: KColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _includeClosed,
            onChanged: widget.closedCount == 0
                ? null
                : (v) => setState(() => _includeClosed = v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Include completed items (${widget.closedCount})',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(_includeClosed),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: const Text('Save PDF'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: KColors.amber,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: KColors.border)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: KColors.textDim),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _LabelledText extends StatelessWidget {
  final String label;
  final String text;
  const _LabelledText(this.label, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: KColors.textDim, fontSize: 12)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
