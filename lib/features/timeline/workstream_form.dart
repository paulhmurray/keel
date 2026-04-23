import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/person_picker_field.dart';

// ---------------------------------------------------------------------------
// Activity edit model (in-memory during form editing)
// ---------------------------------------------------------------------------

class _ActivityDraft {
  String id;
  String name;
  String? startDate;
  String? endDate;
  String ownerName;
  String? ownerId;
  String status;
  String? notes;
  int sortOrder;
  bool isNew;

  _ActivityDraft({
    required this.id,
    required this.name,
    this.startDate,
    this.endDate,
    this.ownerName = '',
    this.ownerId,
    required this.status,
    this.notes,
    required this.sortOrder,
    this.isNew = false,
  });

  factory _ActivityDraft.fromDb(WorkstreamActivity act) => _ActivityDraft(
        id: act.id,
        name: act.name,
        startDate: act.startDate,
        endDate: act.endDate,
        ownerId: act.ownerId,
        status: act.status,
        notes: act.notes,
        sortOrder: act.sortOrder,
      );
}

// ---------------------------------------------------------------------------
// WorkstreamFormDialog
// ---------------------------------------------------------------------------

class WorkstreamFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Workstream? workstream;

  const WorkstreamFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.workstream,
  });

  @override
  State<WorkstreamFormDialog> createState() => _WorkstreamFormDialogState();
}

class _WorkstreamFormDialogState extends State<WorkstreamFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _laneCtrl;
  late TextEditingController _leadCtrl;
  late TextEditingController _notesCtrl;

  String _status = 'not_started';
  String? _startDate;
  String? _endDate;
  List<String> _dependsOnIds = [];

  List<Workstream> _otherWorkstreams = [];
  List<String> _existingLanes = [];
  List<Person> _persons = [];

  // Activities
  List<_ActivityDraft> _activities = [];
  Set<String> _deletedActivityIds = {};
  bool _showAddActivity = false;
  int? _editingActivityIndex;

  // Inline add/edit form controllers
  final _actNameCtrl = TextEditingController();
  final _actOwnerCtrl = TextEditingController();
  final _actNotesCtrl = TextEditingController();
  String _actStatus = 'not_started';
  String? _actStartDate;
  String? _actEndDate;

  static const _statuses = [
    'not_started',
    'in_progress',
    'complete',
    'blocked',
  ];

  static const _statusLabels = {
    'not_started': 'Not Started',
    'in_progress': 'In Progress',
    'complete': 'Complete',
    'blocked': 'Blocked',
  };

  @override
  void initState() {
    super.initState();
    final ws = widget.workstream;
    _nameCtrl = TextEditingController(text: ws?.name ?? '');
    _laneCtrl = TextEditingController(text: ws?.lane ?? 'General');
    _leadCtrl = TextEditingController(text: ws?.lead ?? '');
    _notesCtrl = TextEditingController(text: ws?.notes ?? '');
    _status = ws?.status ?? 'not_started';
    _startDate = ws?.startDate;
    _endDate = ws?.endDate;
    _loadData();
  }

  Future<void> _loadData() async {
    final all =
        await widget.db.workstreamsDao.getForProject(widget.projectId);
    final links =
        await widget.db.workstreamsDao.getLinksForProject(widget.projectId);
    final others = all.where((w) => w.id != widget.workstream?.id).toList();
    final lanes = all.map((w) => w.lane).toSet().toList()..sort();
    final persons =
        await widget.db.peopleDao.getPersonsForProject(widget.projectId);

    List<String> deps = [];
    if (widget.workstream != null) {
      deps = links
          .where((l) => l.toId == widget.workstream!.id)
          .map((l) => l.fromId)
          .toList();
    }

    // Load existing activities
    List<WorkstreamActivity> rawActivities = [];
    if (widget.workstream != null) {
      rawActivities = await widget.db.workstreamActivitiesDao
          .getForWorkstream(widget.workstream!.id);
    }

    final personMap = {for (final p in persons) p.id: p};
    final drafts = rawActivities.map((a) {
      final draft = _ActivityDraft.fromDb(a);
      if (a.ownerId != null) {
        draft.ownerName = personMap[a.ownerId!]?.name ?? '';
      }
      return draft;
    }).toList();

    if (mounted) {
      setState(() {
        _otherWorkstreams = others;
        _existingLanes = lanes;
        _dependsOnIds = deps;
        _persons = persons;
        if (_activities.isEmpty) _activities = drafts;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _laneCtrl.dispose();
    _leadCtrl.dispose();
    _notesCtrl.dispose();
    _actNameCtrl.dispose();
    _actOwnerCtrl.dispose();
    _actNotesCtrl.dispose();
    super.dispose();
  }

  String? _resolvePersonId(String name) {
    if (name.trim().isEmpty) return null;
    return _persons.where((p) => p.name == name.trim()).firstOrNull?.id;
  }

  void _beginAddActivity() {
    _actNameCtrl.clear();
    _actOwnerCtrl.text = _leadCtrl.text.trim();
    _actNotesCtrl.clear();
    _actStatus = 'not_started';
    _actStartDate = _startDate;
    _actEndDate = null;
    setState(() {
      _showAddActivity = true;
      _editingActivityIndex = null;
    });
  }

  void _beginEditActivity(int index) {
    final act = _activities[index];
    _actNameCtrl.text = act.name;
    _actOwnerCtrl.text = act.ownerName;
    _actNotesCtrl.text = act.notes ?? '';
    _actStatus = act.status;
    _actStartDate = act.startDate;
    _actEndDate = act.endDate;
    setState(() {
      _editingActivityIndex = index;
      _showAddActivity = false;
    });
  }

  void _cancelActivityForm() {
    setState(() {
      _showAddActivity = false;
      _editingActivityIndex = null;
    });
  }

  void _saveActivityForm() {
    if (_actNameCtrl.text.trim().isEmpty) return;

    if (_editingActivityIndex != null) {
      final draft = _activities[_editingActivityIndex!];
      draft.name = _actNameCtrl.text.trim();
      draft.startDate = _actStartDate;
      draft.endDate = _actEndDate;
      draft.ownerName = _actOwnerCtrl.text.trim();
      draft.ownerId = _resolvePersonId(_actOwnerCtrl.text);
      draft.status = _actStatus;
      draft.notes = _actNotesCtrl.text.trim().isEmpty
          ? null
          : _actNotesCtrl.text.trim();
      setState(() => _editingActivityIndex = null);
    } else {
      final draft = _ActivityDraft(
        id: const Uuid().v4(),
        name: _actNameCtrl.text.trim(),
        startDate: _actStartDate,
        endDate: _actEndDate,
        ownerName: _actOwnerCtrl.text.trim(),
        ownerId: _resolvePersonId(_actOwnerCtrl.text),
        status: _actStatus,
        notes: _actNotesCtrl.text.trim().isEmpty
            ? null
            : _actNotesCtrl.text.trim(),
        sortOrder: _activities.length,
        isNew: true,
      );
      setState(() {
        _activities.add(draft);
        _showAddActivity = false;
      });
    }
  }

  void _deleteActivity(int index) {
    final draft = _activities[index];
    if (!draft.isNew) _deletedActivityIds.add(draft.id);
    setState(() => _activities.removeAt(index));
  }

  Future<void> _save() async {
    // Auto-commit any open activity inline form before saving the workstream.
    // Handles the case where the user presses the outer Save button while the
    // activity form is still open.
    if (_showAddActivity || _editingActivityIndex != null) {
      if (_actNameCtrl.text.trim().isNotEmpty) {
        _saveActivityForm();
      } else {
        _cancelActivityForm();
      }
    }

    if (!_formKey.currentState!.validate()) return;

    final id = widget.workstream?.id ?? const Uuid().v4();
    final lane =
        _laneCtrl.text.trim().isEmpty ? 'General' : _laneCtrl.text.trim();
    final now = DateTime.now();

    await widget.db.workstreamsDao.upsert(WorkstreamsCompanion(
      id: Value(id),
      projectId: Value(widget.projectId),
      name: Value(_nameCtrl.text.trim()),
      lane: Value(lane),
      lead: Value(
          _leadCtrl.text.trim().isEmpty ? null : _leadCtrl.text.trim()),
      status: Value(_status),
      startDate: Value(_startDate),
      endDate: Value(_endDate),
      notes: Value(
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
      updatedAt: Value(now),
    ));

    // Sync dependency links
    await widget.db.workstreamsDao.deleteLinksForWorkstream(id);
    for (final fromId in _dependsOnIds) {
      await widget.db.workstreamsDao.upsertLink(WorkstreamLinksCompanion(
        id: Value(const Uuid().v4()),
        projectId: Value(widget.projectId),
        fromId: Value(fromId),
        toId: Value(id),
      ));
    }

    // Delete removed activities
    for (final actId in _deletedActivityIds) {
      await widget.db.workstreamActivitiesDao.deleteActivity(actId);
    }

    // Upsert remaining activities
    for (int i = 0; i < _activities.length; i++) {
      final draft = _activities[i];
      final ownerId = draft.ownerId ?? _resolvePersonId(draft.ownerName);
      await widget.db.workstreamActivitiesDao
          .upsert(WorkstreamActivitiesCompanion(
        id: Value(draft.id),
        workstreamId: Value(id),
        projectId: Value(widget.projectId),
        name: Value(draft.name),
        startDate: Value(draft.startDate ?? ''),
        endDate: Value(draft.endDate ?? ''),
        ownerId: Value(ownerId),
        status: Value(draft.status),
        notes: Value(draft.notes),
        sortOrder: Value(i),
        updatedAt: Value(now),
      ));
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.workstream != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Workstream' : 'New Workstream'),
      content: SizedBox(
        width: 540,
        height: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // Lane + Status
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _laneCtrl,
                        decoration: InputDecoration(
                          labelText: 'Lane / Group',
                          hintText: 'e.g. Engineering',
                          suffixIcon: _existingLanes.isNotEmpty
                              ? PopupMenuButton<String>(
                                  icon: const Icon(Icons.arrow_drop_down,
                                      size: 18),
                                  tooltip: 'Existing lanes',
                                  onSelected: (v) =>
                                      setState(() => _laneCtrl.text = v),
                                  itemBuilder: (_) => _existingLanes
                                      .map((l) => PopupMenuItem(
                                          value: l, child: Text(l)))
                                      .toList(),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownField(
                        label: 'Status',
                        value: _status,
                        items: _statuses,
                        labelOverrides: _statusLabels,
                        onChanged: (v) => setState(() => _status = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Start + End dates
                Row(
                  children: [
                    Expanded(
                      child: DatePickerField(
                        label: 'Start Date',
                        isoValue: _startDate,
                        onChanged: (v) => setState(() => _startDate = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DatePickerField(
                        label: 'End Date',
                        isoValue: _endDate,
                        onChanged: (v) => setState(() => _endDate = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Lead + Notes
                Row(
                  children: [
                    Expanded(
                      child: PersonPickerField(
                        controller: _leadCtrl,
                        label: 'Lead / Owner',
                        persons: _persons,
                        db: widget.db,
                        projectId: widget.projectId,
                        onPersonCreated: _loadData,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _notesCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Notes'),
                      ),
                    ),
                  ],
                ),

                // Dependencies
                if (_otherWorkstreams.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'DEPENDS ON',
                    style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'This workstream cannot start until the selected ones complete.',
                    style: TextStyle(color: KColors.textDim, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _otherWorkstreams.map((ws) {
                      final selected = _dependsOnIds.contains(ws.id);
                      return FilterChip(
                        label: Text(ws.name,
                            style: TextStyle(
                                fontSize: 11,
                                color: selected
                                    ? KColors.amber
                                    : KColors.textDim)),
                        selected: selected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _dependsOnIds = [..._dependsOnIds, ws.id];
                            } else {
                              _dependsOnIds = _dependsOnIds
                                  .where((id) => id != ws.id)
                                  .toList();
                            }
                          });
                        },
                        selectedColor: KColors.amberDim,
                        backgroundColor: KColors.surface2,
                        side: BorderSide(
                            color:
                                selected ? KColors.amber : KColors.border2),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                      );
                    }).toList(),
                  ),
                ],

                // ── Activities section ──────────────────────────────────
                const SizedBox(height: 24),
                const _SectionDivider(label: 'ACTIVITIES'),
                const SizedBox(height: 4),
                const Text(
                  'Add child activities within this workstream. They appear as thinner bars on the Gantt.',
                  style: TextStyle(color: KColors.textDim, fontSize: 11),
                ),
                const SizedBox(height: 10),

                // Reorderable activity list
                if (_activities.isNotEmpty)
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (oldIdx, newIdx) {
                      setState(() {
                        if (newIdx > oldIdx) newIdx--;
                        final item = _activities.removeAt(oldIdx);
                        _activities.insert(newIdx, item);
                      });
                    },
                    itemCount: _activities.length,
                    itemBuilder: (ctx, i) {
                      final act = _activities[i];
                      final isEditingThis = _editingActivityIndex == i;
                      return _ActivityListItem(
                        key: ValueKey(act.id),
                        draft: act,
                        isExpanded: isEditingThis,
                        persons: _persons,
                        db: widget.db,
                        projectId: widget.projectId,
                        actNameCtrl: isEditingThis ? _actNameCtrl : null,
                        actOwnerCtrl: isEditingThis ? _actOwnerCtrl : null,
                        actNotesCtrl: isEditingThis ? _actNotesCtrl : null,
                        actStatus: isEditingThis ? _actStatus : null,
                        actStartDate: isEditingThis ? _actStartDate : null,
                        actEndDate: isEditingThis ? _actEndDate : null,
                        onStatusChanged: isEditingThis
                            ? (v) => setState(() => _actStatus = v!)
                            : null,
                        onStartDateChanged: isEditingThis
                            ? (v) => setState(() => _actStartDate = v)
                            : null,
                        onEndDateChanged: isEditingThis
                            ? (v) => setState(() => _actEndDate = v)
                            : null,
                        onEdit: () => _beginEditActivity(i),
                        onDelete: () => _deleteActivity(i),
                        onSave: isEditingThis ? _saveActivityForm : null,
                        onCancel: isEditingThis ? _cancelActivityForm : null,
                        onPersonCreated: _loadData,
                      );
                    },
                  ),

                // Inline add-activity form
                if (_showAddActivity)
                  _ActivityInlineForm(
                    nameCtrl: _actNameCtrl,
                    ownerCtrl: _actOwnerCtrl,
                    notesCtrl: _actNotesCtrl,
                    status: _actStatus,
                    startDate: _actStartDate,
                    endDate: _actEndDate,
                    persons: _persons,
                    db: widget.db,
                    projectId: widget.projectId,
                    statusLabels: _statusLabels,
                    statuses: _statuses,
                    onStatusChanged: (v) => setState(() => _actStatus = v!),
                    onStartDateChanged: (v) =>
                        setState(() => _actStartDate = v),
                    onEndDateChanged: (v) => setState(() => _actEndDate = v),
                    onSave: _saveActivityForm,
                    onCancel: _cancelActivityForm,
                    onPersonCreated: _loadData,
                  ),

                const SizedBox(height: 8),
                if (!_showAddActivity && _editingActivityIndex == null)
                  TextButton.icon(
                    onPressed: _beginAddActivity,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add Activity',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Activity list item (collapsed + expanded states)
// ---------------------------------------------------------------------------

class _ActivityListItem extends StatelessWidget {
  final _ActivityDraft draft;
  final bool isExpanded;
  final List<Person> persons;
  final AppDatabase db;
  final String projectId;

  // Only non-null when isExpanded = true
  final TextEditingController? actNameCtrl;
  final TextEditingController? actOwnerCtrl;
  final TextEditingController? actNotesCtrl;
  final String? actStatus;
  final String? actStartDate;
  final String? actEndDate;
  final ValueChanged<String?>? onStatusChanged;
  final ValueChanged<String?>? onStartDateChanged;
  final ValueChanged<String?>? onEndDateChanged;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPersonCreated;

  static const _statuses = ['not_started', 'in_progress', 'complete', 'blocked'];
  static const _statusLabels = {
    'not_started': 'Not Started',
    'in_progress': 'In Progress',
    'complete': 'Complete',
    'blocked': 'Blocked',
  };

  const _ActivityListItem({
    required super.key,
    required this.draft,
    required this.isExpanded,
    required this.persons,
    required this.db,
    required this.projectId,
    this.actNameCtrl,
    this.actOwnerCtrl,
    this.actNotesCtrl,
    this.actStatus,
    this.actStartDate,
    this.actEndDate,
    this.onStatusChanged,
    this.onStartDateChanged,
    this.onEndDateChanged,
    this.onSave,
    this.onCancel,
    required this.onEdit,
    required this.onDelete,
    required this.onPersonCreated,
  });

  Color _statusColor(String s) {
    switch (s) {
      case 'in_progress': return KColors.amber;
      case 'complete': return KColors.phosphor;
      case 'blocked': return KColors.red;
      default: return KColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isExpanded && actNameCtrl != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.amber.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: _ActivityInlineForm(
          nameCtrl: actNameCtrl!,
          ownerCtrl: actOwnerCtrl!,
          notesCtrl: actNotesCtrl!,
          status: actStatus!,
          startDate: actStartDate,
          endDate: actEndDate,
          persons: persons,
          db: db,
          projectId: projectId,
          statuses: _statuses,
          statusLabels: _statusLabels,
          onStatusChanged: onStatusChanged!,
          onStartDateChanged: onStartDateChanged!,
          onEndDateChanged: onEndDateChanged!,
          onSave: onSave!,
          onCancel: onCancel!,
          onPersonCreated: onPersonCreated,
        ),
      );
    }

    // Collapsed row
    final color = _statusColor(draft.status);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_handle, size: 14, color: KColors.textMuted),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(draft.name,
                    style: const TextStyle(
                        color: KColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                if (draft.startDate != null || draft.ownerName.isNotEmpty)
                  Text(
                    [
                      if (draft.startDate != null && draft.endDate != null)
                        '${draft.startDate} → ${draft.endDate}',
                      if (draft.ownerName.isNotEmpty) draft.ownerName,
                    ].join(' · '),
                    style: const TextStyle(
                        color: KColors.textDim, fontSize: 10),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 14),
            color: KColors.textDim,
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 14),
            color: KColors.red,
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline activity form (shared by add and edit states)
// ---------------------------------------------------------------------------

class _ActivityInlineForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController ownerCtrl;
  final TextEditingController notesCtrl;
  final String status;
  final String? startDate;
  final String? endDate;
  final List<Person> persons;
  final AppDatabase db;
  final String projectId;
  final List<String> statuses;
  final Map<String, String> statusLabels;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onStartDateChanged;
  final ValueChanged<String?> onEndDateChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onPersonCreated;

  const _ActivityInlineForm({
    required this.nameCtrl,
    required this.ownerCtrl,
    required this.notesCtrl,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.persons,
    required this.db,
    required this.projectId,
    required this.statuses,
    required this.statusLabels,
    required this.onStatusChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.onSave,
    required this.onCancel,
    required this.onPersonCreated,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Activity name *', isDense: true),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DatePickerField(
                label: 'Start Date',
                isoValue: startDate,
                onChanged: onStartDateChanged,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DatePickerField(
                label: 'End Date',
                isoValue: endDate,
                onChanged: onEndDateChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: PersonPickerField(
                controller: ownerCtrl,
                label: 'Owner',
                persons: persons,
                db: db,
                projectId: projectId,
                onPersonCreated: onPersonCreated,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownField(
                label: 'Status',
                value: status,
                items: statuses,
                labelOverrides: statusLabels,
                onChanged: onStatusChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: notesCtrl,
          decoration: const InputDecoration(
              labelText: 'Notes (optional)', isDense: true),
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: onCancel,
              child: const Text('Cancel',
                  style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onSave,
              child: const Text('Save Activity',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section divider
// ---------------------------------------------------------------------------

class _SectionDivider extends StatelessWidget {
  final String label;

  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            )),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: KColors.border)),
      ],
    );
  }
}
