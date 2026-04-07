import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/utils/date_utils.dart' as du;

class ActionFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ProjectAction? action;
  final bool startInViewMode;

  const ActionFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.action,
    this.startInViewMode = false,
  });

  @override
  State<ActionFormDialog> createState() => _ActionFormDialogState();
}

class _ActionFormDialogState extends State<ActionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descCtrl;
  late TextEditingController _ownerCtrl;
  String? _dueDate;
  late TextEditingController _sourceNoteCtrl;

  String _status = 'open';
  String _priority = 'medium';
  String _source = 'manual';

  late bool _isViewing;

  List<Person> _persons = [];

  final _statuses = ['open', 'in progress', 'closed', 'blocked'];
  final _priorities = ['low', 'medium', 'high', 'critical'];
  final _sources = ['manual', 'inbox', 'document', 'observation', 'meeting'];

  @override
  void initState() {
    super.initState();
    final a = widget.action;
    _descCtrl = TextEditingController(text: a?.description ?? '');
    _ownerCtrl = TextEditingController(text: a?.owner ?? '');
    _dueDate = a?.dueDate;
    _sourceNoteCtrl = TextEditingController(text: a?.sourceNote ?? '');
    _status = a?.status ?? 'open';
    _priority = a?.priority ?? 'medium';
    _source = a?.source ?? 'manual';
    _isViewing = widget.startInViewMode && a != null;
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final persons =
        await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = persons);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _ownerCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final existing =
        await widget.db.actionsDao.getActionsForProject(widget.projectId);
    final nums = existing
        .where((a) => a.ref != null && a.ref!.startsWith('AC'))
        .map((a) => int.tryParse(a.ref!.substring(2)) ?? 0)
        .toList()
      ..sort();
    final String ref = widget.action?.ref ??
        'AC${(nums.isEmpty ? 0 : nums.last) + 1}';

    final id = widget.action?.id ?? const Uuid().v4();
    await widget.db.actionsDao.upsertAction(
      ProjectActionsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(_descCtrl.text.trim()),
        owner: Value(
            _ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
        dueDate: Value(_dueDate),
        status: Value(_status),
        priority: Value(_priority),
        source: Value(_source),
        sourceNote: Value(_sourceNoteCtrl.text.trim().isEmpty
            ? null
            : _sourceNoteCtrl.text.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (mounted) Navigator.of(context).pop();
  }

  Widget _readView() {
    final a = widget.action!;
    final isOverdue = a.dueDate != null &&
        a.status != 'closed' &&
        a.dueDate!
                .compareTo(DateTime.now().toIso8601String().substring(0, 10)) <
            0;
    return AlertDialog(
      title: Row(
        children: [
          if (a.ref != null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KColors.amberDim,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(a.ref!,
                  style: const TextStyle(
                      color: KColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
          ],
          const Text('Action'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _viewField('Description', a.description, large: true),
            Row(
              children: [
                Expanded(child: _viewField('Status', a.status)),
                Expanded(child: _viewField('Priority', a.priority)),
              ],
            ),
            Row(
              children: [
                if (a.owner != null && a.owner!.isNotEmpty)
                  Expanded(child: _viewField('Owner', a.owner)),
                if (a.dueDate != null)
                  Expanded(
                    child: _viewField(
                      'Due Date',
                      du.formatDate(a.dueDate),
                      valueColor: isOverdue ? KColors.red : null,
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(child: _viewField('Source', a.source)),
                if (a.sourceNote != null && a.sourceNote!.isNotEmpty)
                  Expanded(child: _viewField('Source Note', a.sourceNote)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: () => setState(() => _isViewing = false),
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Edit'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isViewing) return _readView();

    final isEdit = widget.action != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Action' : 'New Action'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _descCtrl,
                autofocus: true,
                decoration:
                    const InputDecoration(labelText: 'Description *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownField(
                      label: 'Status',
                      value: _status,
                      items: _statuses,
                      onChanged: (v) => setState(() => _status = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownField(
                      label: 'Priority',
                      value: _priority,
                      items: _priorities,
                      onChanged: (v) => setState(() => _priority = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value:
                          _ownerCtrl.text.isEmpty ? null : _ownerCtrl.text,
                      decoration:
                          const InputDecoration(labelText: 'Owner'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— none —')),
                        ..._persons.map((p) => DropdownMenuItem(
                              value: p.name,
                              child: Text(p.name),
                            )),
                      ],
                      onChanged: (v) =>
                          setState(() => _ownerCtrl.text = v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DatePickerField(
                      label: 'Due Date',
                      isoValue: _dueDate,
                      onChanged: (v) => setState(() => _dueDate = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownField(
                      label: 'Source',
                      value: _source,
                      items: _sources,
                      onChanged: (v) => setState(() => _source = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sourceNoteCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Source Note'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.startInViewMode)
          TextButton(
            onPressed: () => setState(() => _isViewing = true),
            child: const Text('Cancel'),
          )
        else
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

Widget _viewField(String label, String? value,
    {bool large = false, Color? valueColor}) {
  if (value == null || value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: KColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? KColors.text,
            fontSize: large ? 14 : 12,
            height: 1.55,
          ),
        ),
      ],
    ),
  );
}
