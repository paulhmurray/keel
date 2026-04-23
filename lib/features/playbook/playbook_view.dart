import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../../shared/widgets/person_picker_field.dart';
import 'checklist_widget.dart';
import 'playbook_setup_view.dart';

Color _statusColor(String status) => switch (status) {
      'complete' => KColors.phosphor,
      'in_progress' => KColors.amber,
      'blocked' => KColors.red,
      'pending_approval' => KColors.blue,
      _ => KColors.textMuted,
    };

IconData _statusIcon(String status) => switch (status) {
      'complete' => Icons.check_circle,
      'in_progress' => Icons.play_circle_outline,
      'blocked' => Icons.block_outlined,
      'pending_approval' => Icons.hourglass_empty_outlined,
      _ => Icons.radio_button_unchecked,
    };

String _statusLabel(String status) => switch (status) {
      'complete' => 'COMPLETE',
      'in_progress' => 'IN PROGRESS',
      'blocked' => 'BLOCKED',
      'pending_approval' => 'PENDING APPROVAL',
      _ => 'NOT STARTED',
    };

// ---------------------------------------------------------------------------
// PlaybookView
// ---------------------------------------------------------------------------

class PlaybookView extends StatefulWidget {
  const PlaybookView({super.key});

  @override
  State<PlaybookView> createState() => _PlaybookViewState();
}

class _PlaybookViewState extends State<PlaybookView> {
  String? _expandedStageId;

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(
        child: Text('Select a project to view its playbook.',
            style: TextStyle(color: KColors.textDim)),
      );
    }

    final db = context.read<AppDatabase>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('PLAYBOOK',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PlaybookSetupView(db: db)),
                ),
                icon: const Icon(Icons.tune, size: 14),
                label: const Text('Manage playbooks'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KColors.textDim,
                  side: const BorderSide(color: KColors.border2),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<ProjectPlaybook?>(
              stream: db.playbookDao.watchProjectPlaybook(projectId),
              builder: (context, ppSnap) {
                if (!ppSnap.hasData || ppSnap.data == null) {
                  return _NoPlaybookWidget(projectId: projectId, db: db);
                }
                return _PlaybookProgress(
                  projectPlaybook: ppSnap.data!,
                  db: db,
                  expandedStageId: _expandedStageId,
                  onExpand: (id) => setState(
                      () => _expandedStageId = _expandedStageId == id ? null : id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// No playbook attached
// ---------------------------------------------------------------------------

class _NoPlaybookWidget extends StatefulWidget {
  final String projectId;
  final AppDatabase db;

  const _NoPlaybookWidget({required this.projectId, required this.db});

  @override
  State<_NoPlaybookWidget> createState() => _NoPlaybookWidgetState();
}

class _NoPlaybookWidgetState extends State<_NoPlaybookWidget> {
  List<Playbook> _playbooks = [];
  List<Organisation> _orgs = [];
  String? _selectedPlaybookId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final orgs = await widget.db.playbookDao.getAllOrganisations();
    final books = <Playbook>[];
    for (final org in orgs) {
      books.addAll(await widget.db.playbookDao.getPlaybooksForOrg(org.id));
    }
    if (mounted) setState(() { _orgs = orgs; _playbooks = books; });
  }

  @override
  Widget build(BuildContext context) {
    if (_orgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined, size: 48, color: KColors.textMuted),
            const SizedBox(height: 16),
            const Text('No playbooks set up yet.',
                style: TextStyle(color: KColors.textDim, fontSize: 14)),
            const SizedBox(height: 8),
            const Text('Set up your organisation and delivery sequence first.',
                style: TextStyle(color: KColors.textMuted, fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PlaybookSetupView(db: widget.db)));
                _load();
              },
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Set up organisation & playbook'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.link_outlined, size: 40, color: KColors.textMuted),
            const SizedBox(height: 16),
            const Text('Attach a playbook to this project',
                style: TextStyle(color: KColors.text, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Choose the delivery sequence that applies to this project.',
                style: TextStyle(color: KColors.textDim, fontSize: 12)),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: KColors.surface2,
                border: Border.all(color: KColors.border2),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedPlaybookId,
                  isExpanded: true,
                  dropdownColor: KColors.surface2,
                  hint: const Text('Select playbook…',
                      style: TextStyle(color: KColors.textDim, fontSize: 13)),
                  items: _playbooks
                      .map((pb) => DropdownMenuItem<String?>(
                            value: pb.id,
                            child: Text(pb.name,
                                style: const TextStyle(color: KColors.text, fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedPlaybookId = v),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _selectedPlaybookId == null
                      ? null
                      : () => _attach(_selectedPlaybookId!),
                  child: const Text('Attach playbook'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => PlaybookSetupView(db: widget.db)));
                    _load();
                  },
                  child: const Text('Manage playbooks',
                      style: TextStyle(color: KColors.textDim, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attach(String playbookId) async {
    await widget.db.playbookDao.attachPlaybookToProject(
      projectId: widget.projectId,
      playbookId: playbookId,
    );
  }
}

// ---------------------------------------------------------------------------
// Progress stepper
// ---------------------------------------------------------------------------

class _PlaybookProgress extends StatefulWidget {
  final ProjectPlaybook projectPlaybook;
  final AppDatabase db;
  final String? expandedStageId;
  final ValueChanged<String> onExpand;

  const _PlaybookProgress({
    required this.projectPlaybook,
    required this.db,
    required this.expandedStageId,
    required this.onExpand,
  });

  @override
  State<_PlaybookProgress> createState() => _PlaybookProgressState();
}

class _PlaybookProgressState extends State<_PlaybookProgress> {
  List<Person> _persons = [];

  @override
  void initState() {
    super.initState();
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final persons = await widget.db.peopleDao
        .getPersonsForProject(widget.projectPlaybook.projectId);
    if (mounted) setState(() => _persons = persons);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Playbook?>(
      future: widget.db.playbookDao.getPlaybookById(widget.projectPlaybook.playbookId),
      builder: (context, pbSnap) {
        final playbook = pbSnap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (playbook != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: KColors.surface,
                  border: Border.all(color: KColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_outlined, size: 13, color: KColors.amber),
                    const SizedBox(width: 6),
                    Text(playbook.name,
                        style: const TextStyle(
                            color: KColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                    if (playbook.version != null) ...[
                      const SizedBox(width: 8),
                      _Chip(label: playbook.version!, color: KColors.textDim),
                    ],
                    const Spacer(),
                    TextButton(
                      onPressed: () => _confirmDetach(context),
                      child: const Text('Detach',
                          style: TextStyle(color: KColors.textMuted, fontSize: 11)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: StreamBuilder<List<PlaybookStage>>(
                stream: widget.db.playbookDao
                    .watchStagesForPlaybook(widget.projectPlaybook.playbookId),
                builder: (context, stagesSnap) {
                  final stages = stagesSnap.data ?? [];
                  return StreamBuilder<List<ProjectStageProgressesData>>(
                    stream: widget.db.playbookDao
                        .watchProgressForProjectPlaybook(widget.projectPlaybook.id),
                    builder: (context, progressSnap) {
                      final progressList = progressSnap.data ?? [];
                      final progressMap = <String, ProjectStageProgressesData>{
                        for (final p in progressList) p.stageId: p
                      };

                      if (stages.isEmpty) {
                        return const Center(
                          child: Text(
                            'This playbook has no stages yet. Edit the playbook to add stages.',
                            style: TextStyle(color: KColors.textDim, fontSize: 12),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: stages.length,
                        itemBuilder: (_, i) => _StageRow(
                          stage: stages[i],
                          progress: progressMap[stages[i].id],
                          stageIndex: i,
                          isLast: i == stages.length - 1,
                          expanded: widget.expandedStageId == stages[i].id,
                          projectPlaybookId: widget.projectPlaybook.id,
                          projectId: widget.projectPlaybook.projectId,
                          db: widget.db,
                          persons: _persons,
                          onPersonCreated: _loadPersons,
                          onExpand: () => widget.onExpand(stages[i].id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmDetach(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Detach playbook?'),
        content: const Text(
          'This will remove the playbook attachment and all stage progress for this project. '
          'The playbook itself will not be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.db.playbookDao
                  .detachPlaybook(widget.projectPlaybook.projectId);
            },
            child: const Text('Detach'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stage row
// ---------------------------------------------------------------------------

class _StageRow extends StatefulWidget {
  final PlaybookStage stage;
  final ProjectStageProgressesData? progress;
  final int stageIndex;
  final bool isLast;
  final bool expanded;
  final String projectPlaybookId;
  final String projectId;
  final AppDatabase db;
  final List<Person> persons;
  final VoidCallback onPersonCreated;
  final VoidCallback onExpand;

  const _StageRow({
    required this.stage,
    required this.progress,
    required this.stageIndex,
    required this.isLast,
    required this.expanded,
    required this.projectPlaybookId,
    required this.projectId,
    required this.db,
    required this.persons,
    required this.onPersonCreated,
    required this.onExpand,
  });

  @override
  State<_StageRow> createState() => _StageRowState();
}

class _StageRowState extends State<_StageRow> {
  late final TextEditingController _approvedByCtrl;
  late final TextEditingController _approvalNotesCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _approvedByCtrl = TextEditingController(text: widget.progress?.approvedBy ?? '');
    _approvalNotesCtrl = TextEditingController(text: widget.progress?.approvalNotes ?? '');
    _notesCtrl = TextEditingController(text: widget.progress?.notes ?? '');
    _lastSavedApprovedBy = widget.progress?.approvedBy?.trim() ?? '';
    _approvedByCtrl.addListener(_onApprovedByChanged);
  }

  late String _lastSavedApprovedBy;

  void _onApprovedByChanged() {
    // Save when the picker selects a value (text changes without the field being
    // focused, i.e. selection came from the dropdown). We debounce by comparing
    // against the last saved value to avoid unnecessary writes on every keystroke.
    final val = _approvedByCtrl.text.trim();
    if (val != _lastSavedApprovedBy) {
      _lastSavedApprovedBy = val;
      _upsertProgress(approvedBy: val.isEmpty ? null : val);
    }
  }

  @override
  void didUpdateWidget(_StageRow old) {
    super.didUpdateWidget(old);
    // Sync controllers when progress updates externally (don't disrupt active edits)
    if (old.progress?.approvedBy != widget.progress?.approvedBy &&
        !_approvedByCtrl.selection.isValid) {
      _approvedByCtrl.text = widget.progress?.approvedBy ?? '';
    }
  }

  @override
  void dispose() {
    _approvedByCtrl.removeListener(_onApprovedByChanged);
    _approvedByCtrl.dispose();
    _approvalNotesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _status => widget.progress?.status ?? 'not_started';

  Future<void> _upsertProgress({
    String? status,
    String? checklist,
    bool? gateMet,
    String? approvedBy,
    DateTime? approvedAt,
    String? approvalNotes,
    String? notes,
  }) async {
    final now = DateTime.now();
    final e = widget.progress;
    await widget.db.playbookDao.upsertProgress(
      ProjectStageProgressesCompanion(
        id: Value(e?.id ?? const Uuid().v4()),
        projectPlaybookId: Value(widget.projectPlaybookId),
        stageId: Value(widget.stage.id),
        status: Value(status ?? e?.status ?? 'not_started'),
        gateMet: Value(gateMet ?? e?.gateMet ?? false),
        approvedBy: Value(approvedBy ?? e?.approvedBy),
        approvedAt: Value(approvedAt ?? e?.approvedAt),
        approvalNotes: Value(approvalNotes ?? e?.approvalNotes),
        checklist: Value(checklist ?? e?.checklist),
        notes: Value(notes ?? e?.notes),
        createdAt: Value(e?.createdAt ?? now),
        updatedAt: Value(now),
      ),
    );
  }

  int get _checkedCount {
    try {
      final items = jsonDecode(widget.progress?.checklist ?? '[]') as List;
      return items.where((e) => (e as Map)['checked'] == true).length;
    } catch (_) { return 0; }
  }

  int get _totalCount {
    try {
      return (jsonDecode(widget.progress?.checklist ?? '[]') as List).length;
    } catch (_) { return 0; }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final color = _statusColor(status);
    final complete = status == 'complete';

    return Stack(
      children: [
        // Timeline vertical connector line (drawn behind everything)
        if (!widget.isLast)
          Positioned(
            left: 19,
            top: 28,
            bottom: 0,
            width: 2,
            child: Container(color: KColors.border),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Timeline spine circle
          SizedBox(
            width: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 1.5),
                  ),
                  child: Center(
                    child: Icon(_statusIcon(status), size: 14, color: color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.isLast ? 0 : 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Collapsed header
                  GestureDetector(
                    onTap: widget.onExpand,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: KColors.surface,
                        border: Border.all(
                          color: widget.expanded ? color : KColors.border,
                          width: widget.expanded ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(4),
                          topRight: const Radius.circular(4),
                          bottomLeft: Radius.circular(widget.expanded ? 0 : 4),
                          bottomRight: Radius.circular(widget.expanded ? 0 : 4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Stage ${widget.stageIndex + 1}: ${widget.stage.name}',
                                      style: TextStyle(
                                        color: complete ? KColors.textDim : KColors.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    _Chip(label: _statusLabel(status), color: color),
                                  ],
                                ),
                                if (!widget.expanded && _totalCount > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_checkedCount of $_totalCount checklist items done',
                                    style: const TextStyle(color: KColors.textMuted, fontSize: 11),
                                  ),
                                ],
                                if (!widget.expanded && widget.progress?.approvedBy != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Approved by: ${widget.progress!.approvedBy}'
                                    '${widget.progress?.approvedAt != null ? ' · ${du.formatDate(widget.progress!.approvedAt!.toIso8601String().substring(0, 10))}' : ''}',
                                    style: const TextStyle(color: KColors.textMuted, fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(widget.expanded ? Icons.expand_less : Icons.expand_more,
                              size: 18, color: KColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  // Expanded detail panel
                  if (widget.expanded)
                    Container(
                      decoration: BoxDecoration(
                        color: KColors.surface2,
                        border: Border(
                          left: BorderSide(color: color, width: 1.5),
                          right: BorderSide(color: color, width: 1.5),
                          bottom: BorderSide(color: color, width: 1.5),
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.stage.description != null) ...[
                            Text(widget.stage.description!,
                                style: const TextStyle(color: KColors.textDim, fontSize: 12)),
                            const SizedBox(height: 12),
                          ],
                          // Gate + approver info
                          if (widget.stage.gateCondition != null || widget.stage.approverRole != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: KColors.surface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.stage.gateCondition != null)
                                    _LabelValue(label: 'Gate', value: widget.stage.gateCondition!),
                                  if (widget.stage.approverRole != null)
                                    _LabelValue(label: 'Approver', value: widget.stage.approverRole!),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          // Checklist
                          ChecklistWidget(
                            checklistJson: widget.progress?.checklist,
                            onChanged: (json) => _upsertProgress(checklist: json),
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: KColors.border, height: 1),
                          const SizedBox(height: 12),
                          // Approval
                          const _SectionLabel('APPROVAL'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: PersonPickerField(
                                  controller: _approvedByCtrl,
                                  label: 'Approved by',
                                  persons: widget.persons,
                                  db: widget.db,
                                  projectId: widget.projectId,
                                  onPersonCreated: widget.onPersonCreated,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Row(
                                children: [
                                  Checkbox(
                                    value: widget.progress?.gateMet ?? false,
                                    onChanged: (v) => _upsertProgress(gateMet: v ?? false),
                                    activeColor: KColors.phosphor,
                                  ),
                                  const Text('Gate met',
                                      style: TextStyle(color: KColors.textDim, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _approvalNotesCtrl,
                            maxLines: 2,
                            style: const TextStyle(color: KColors.text, fontSize: 12),
                            decoration: const InputDecoration(
                              labelText: 'Approval notes',
                              labelStyle: TextStyle(color: KColors.textDim, fontSize: 11),
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onEditingComplete: () => _upsertProgress(
                              approvalNotes: _approvalNotesCtrl.text.trim().isEmpty
                                  ? null
                                  : _approvalNotesCtrl.text.trim(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Stage notes (institutional knowledge)
                          if (widget.stage.notes != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: KColors.amberDim,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.lightbulb_outline, size: 13, color: KColors.amber),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(widget.stage.notes!,
                                        style: const TextStyle(color: KColors.amber, fontSize: 11)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          // Progress notes
                          TextField(
                            controller: _notesCtrl,
                            maxLines: 2,
                            style: const TextStyle(color: KColors.text, fontSize: 12),
                            decoration: const InputDecoration(
                              labelText: 'Notes',
                              labelStyle: TextStyle(color: KColors.textDim, fontSize: 11),
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            onEditingComplete: () => _upsertProgress(
                              notes: _notesCtrl.text.trim().isEmpty
                                  ? null
                                  : _notesCtrl.text.trim(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Divider(color: KColors.border, height: 1),
                          const SizedBox(height: 12),
                          // Status actions
                          _StatusActions(currentStatus: status, onSetStatus: (s) => _upsertProgress(status: s)),
                        ],
                      ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status action buttons
// ---------------------------------------------------------------------------

class _StatusActions extends StatelessWidget {
  final String currentStatus;
  final Future<void> Function(String) onSetStatus;

  const _StatusActions({required this.currentStatus, required this.onSetStatus});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (currentStatus != 'in_progress')
          _ActionBtn(label: 'Mark In Progress', color: KColors.amber,
              onTap: () => onSetStatus('in_progress')),
        if (currentStatus != 'blocked')
          _ActionBtn(label: 'Mark Blocked', color: KColors.red,
              onTap: () => onSetStatus('blocked')),
        if (currentStatus != 'pending_approval')
          _ActionBtn(label: 'Pending Approval', color: KColors.blue,
              onTap: () => onSetStatus('pending_approval')),
        if (currentStatus != 'complete')
          _ActionBtn(label: 'Mark Complete', color: KColors.phosphor,
              onTap: () => onSetStatus('complete')),
        if (currentStatus != 'not_started')
          _ActionBtn(label: 'Reset', color: KColors.textDim,
              onTap: () => onSetStatus('not_started')),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

// ---------------------------------------------------------------------------
// Utility widgets
// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;
  const _LabelValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text('$label:',
                style: const TextStyle(
                    color: KColors.textDim, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: KColors.text, fontSize: 11))),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: KColors.textDim, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.12));
  }
}
