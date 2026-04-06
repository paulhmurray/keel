import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';

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
  late TextEditingController _leadCtrl;
  late TextEditingController _notesCtrl;
  String _status = 'green';

  @override
  void initState() {
    super.initState();
    final w = widget.workstream;
    _nameCtrl = TextEditingController(text: w?.name ?? '');
    _leadCtrl = TextEditingController(text: w?.lead ?? '');
    _notesCtrl = TextEditingController(text: w?.notes ?? '');
    _status = w?.status ?? 'green';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _leadCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final id = widget.workstream?.id ?? const Uuid().v4();
    await widget.db.programmeDao.upsertWorkstream(
      WorkstreamsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        name: Value(_nameCtrl.text.trim()),
        lead: Value(_leadCtrl.text.trim().isEmpty ? null : _leadCtrl.text.trim()),
        notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
        status: Value(_status),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.workstream != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Workstream' : 'New Workstream'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _leadCtrl,
                decoration: const InputDecoration(labelText: 'Lead'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Status (RAG)'),
                dropdownColor: KColors.surface2,
                items: const [
                  DropdownMenuItem(value: 'green', child: Text('Green')),
                  DropdownMenuItem(value: 'amber', child: Text('Amber')),
                  DropdownMenuItem(value: 'red', child: Text('Red')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'green'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
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
