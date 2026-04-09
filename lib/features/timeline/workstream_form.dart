import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/dropdown_field.dart';

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

  static const _statuses = [
    'not_started',
    'in_progress',
    'complete',
    'blocked',
  ];

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
    final all = await widget.db.workstreamsDao.getForProject(widget.projectId);
    final links = await widget.db.workstreamsDao.getLinksForProject(widget.projectId);
    final others = all.where((w) => w.id != widget.workstream?.id).toList();
    final lanes = all.map((w) => w.lane).toSet().toList()..sort();

    // Load existing depends-on IDs for this workstream
    List<String> deps = [];
    if (widget.workstream != null) {
      deps = links
          .where((l) => l.toId == widget.workstream!.id)
          .map((l) => l.fromId)
          .toList();
    }

    if (mounted) {
      setState(() {
        _otherWorkstreams = others;
        _existingLanes = lanes;
        _dependsOnIds = deps;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _laneCtrl.dispose();
    _leadCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final id = widget.workstream?.id ?? const Uuid().v4();
    final lane = _laneCtrl.text.trim().isEmpty ? 'General' : _laneCtrl.text.trim();

    await widget.db.workstreamsDao.upsert(WorkstreamsCompanion(
      id: Value(id),
      projectId: Value(widget.projectId),
      name: Value(_nameCtrl.text.trim()),
      lane: Value(lane),
      lead: Value(_leadCtrl.text.trim().isEmpty ? null : _leadCtrl.text.trim()),
      status: Value(_status),
      startDate: Value(_startDate),
      endDate: Value(_endDate),
      notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
      updatedAt: Value(DateTime.now()),
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

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.workstream != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Workstream' : 'New Workstream'),
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
                      child: TextFormField(
                        controller: _leadCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Lead / Owner'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(labelText: 'Notes'),
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
                      fontSize: 9,
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
                        label: Text(
                          ws.name,
                          style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? KColors.amber
                                  : KColors.textDim),
                        ),
                        selected: selected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _dependsOnIds = [..._dependsOnIds, ws.id];
                            } else {
                              _dependsOnIds =
                                  _dependsOnIds.where((id) => id != ws.id).toList();
                            }
                          });
                        },
                        selectedColor: KColors.amberDim,
                        backgroundColor: KColors.surface2,
                        side: BorderSide(
                          color: selected ? KColors.amber : KColors.border2,
                        ),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                      );
                    }).toList(),
                  ),
                ],
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
