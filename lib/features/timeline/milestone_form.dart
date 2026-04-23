import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/person_picker_field.dart';

class MilestoneFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Milestone? milestone;

  const MilestoneFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.milestone,
  });

  @override
  State<MilestoneFormDialog> createState() => _MilestoneFormDialogState();
}

class _MilestoneFormDialogState extends State<MilestoneFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _notesCtrl;

  String _status = 'upcoming';
  String? _date;
  bool _isHardDeadline = false;
  String? _workstreamId;

  List<Person> _persons = [];
  List<Workstream> _workstreams = [];

  static const _statuses = [
    'upcoming',
    'achieved',
    'at_risk',
    'missed',
  ];

  static const _statusLabels = {
    'upcoming': 'Upcoming',
    'achieved': 'Achieved',
    'at_risk': 'At Risk',
    'missed': 'Missed',
  };

  @override
  void initState() {
    super.initState();
    final ms = widget.milestone;
    _nameCtrl = TextEditingController(text: ms?.name ?? '');
    _notesCtrl = TextEditingController(text: ms?.notes ?? '');
    _ownerCtrl = TextEditingController();
    _status = ms?.status ?? 'upcoming';
    _date = ms?.date;
    _isHardDeadline = ms?.isHardDeadline ?? false;
    _workstreamId = ms?.workstreamId;
    _loadData(ownerId: ms?.ownerId);
  }

  Future<void> _loadData({String? ownerId}) async {
    final persons =
        await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    final workstreams =
        await widget.db.workstreamsDao.getForProject(widget.projectId);
    if (mounted) {
      setState(() {
        _persons = persons;
        _workstreams = workstreams;
        if (ownerId != null) {
          final match = persons.where((p) => p.id == ownerId).firstOrNull;
          _ownerCtrl.text = match?.name ?? '';
        }
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ownerCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _resolveOwnerId() {
    final name = _ownerCtrl.text.trim();
    if (name.isEmpty) return null;
    return _persons.where((p) => p.name == name).firstOrNull?.id;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Date is required')),
      );
      return;
    }

    final id = widget.milestone?.id ?? const Uuid().v4();
    final now = DateTime.now();

    await widget.db.milestonesDao.upsert(MilestonesCompanion(
      id: Value(id),
      projectId: Value(widget.projectId),
      name: Value(_nameCtrl.text.trim()),
      date: Value(_date!),
      ownerId: Value(_resolveOwnerId()),
      status: Value(_status),
      isHardDeadline: Value(_isHardDeadline),
      notes: Value(
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
      workstreamId: Value(_workstreamId),
      updatedAt: Value(now),
    ));

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColors.surface,
        title: const Text('Delete Milestone',
            style: TextStyle(color: KColors.text, fontSize: 14)),
        content: Text(
            'Delete "${widget.milestone!.name}"? This cannot be undone.',
            style: const TextStyle(color: KColors.textDim, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: KColors.red,
                foregroundColor: KColors.bg),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.db.milestonesDao.deleteMilestone(widget.milestone!.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.milestone != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Milestone' : 'New Milestone'),
      content: SizedBox(
        width: 520,
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

                // Date + Status
                Row(
                  children: [
                    Expanded(
                      child: DatePickerField(
                        label: 'Date *',
                        isoValue: _date,
                        onChanged: (v) => setState(() => _date = v),
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

                // Owner + Hard Deadline toggle
                Row(
                  children: [
                    Expanded(
                      child: PersonPickerField(
                        controller: _ownerCtrl,
                        label: 'Owner',
                        persons: _persons,
                        db: widget.db,
                        projectId: widget.projectId,
                        onPersonCreated: () => _loadData(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Switch(
                            value: _isHardDeadline,
                            onChanged: (v) =>
                                setState(() => _isHardDeadline = v),
                            activeColor: KColors.red,
                          ),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text('Hard Deadline',
                                style: TextStyle(
                                    color: KColors.textDim, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Workstream association
                _WorkstreamDropdown(
                  workstreams: _workstreams,
                  value: _workstreamId,
                  onChanged: (v) => setState(() => _workstreamId = v),
                ),
                const SizedBox(height: 12),

                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (isEdit)
          TextButton(
            onPressed: _delete,
            style:
                TextButton.styleFrom(foregroundColor: KColors.red),
            child: const Text('Delete'),
          ),
        const Spacer(),
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
// Workstream association dropdown
// ---------------------------------------------------------------------------

class _WorkstreamDropdown extends StatelessWidget {
  final List<Workstream> workstreams;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _WorkstreamDropdown({
    required this.workstreams,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: KColors.border2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          isExpanded: true,
          style:
              const TextStyle(color: KColors.text, fontSize: 12),
          dropdownColor: KColors.surface2,
          hint: const Text('Associate with workstream (optional)',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('None — show in Key Dates row',
                  style: TextStyle(color: KColors.textDim, fontSize: 12)),
            ),
            ...workstreams.map((ws) => DropdownMenuItem<String?>(
                  value: ws.id,
                  child: Text('${ws.lane} › ${ws.name}',
                      style: const TextStyle(
                          color: KColors.text, fontSize: 12)),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
