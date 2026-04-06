import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';

class DependencyFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ProgramDependency? dependency;
  final bool startInViewMode;

  const DependencyFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.dependency,
    this.startInViewMode = false,
  });

  @override
  State<DependencyFormDialog> createState() => _DependencyFormDialogState();
}

class _DependencyFormDialogState extends State<DependencyFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _descCtrl;
  late TextEditingController _ownerCtrl;
  String? _dueDate;
  late TextEditingController _sourceNoteCtrl;

  String _dependencyType = 'inbound';
  String _status = 'open';
  String _source = 'manual';

  late bool _isViewing;

  final _types = ['inbound', 'outbound', 'bilateral'];
  final _statuses = ['open', 'in progress', 'resolved', 'closed', 'blocked'];
  final _sources = ['manual', 'inbox', 'document', 'observation', 'meeting'];

  @override
  void initState() {
    super.initState();
    final d = widget.dependency;
    _descCtrl = TextEditingController(text: d?.description ?? '');
    _ownerCtrl = TextEditingController(text: d?.owner ?? '');
    _dueDate = d?.dueDate;
    _sourceNoteCtrl = TextEditingController(text: d?.sourceNote ?? '');
    _dependencyType = d?.dependencyType ?? 'inbound';
    _status = d?.status ?? 'open';
    _source = d?.source ?? 'manual';
    _isViewing = widget.startInViewMode && d != null;
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

    final existing = await widget.db.raidDao.getDependenciesForProject(widget.projectId);
    final nums = existing
        .where((d) => d.ref != null && d.ref!.startsWith('D'))
        .map((d) => int.tryParse(d.ref!.substring(1)) ?? 0)
        .toList()
      ..sort();
    final String ref = widget.dependency?.ref ??
        'D${(nums.isEmpty ? 0 : nums.last) + 1}';

    final id = widget.dependency?.id ?? const Uuid().v4();
    await widget.db.raidDao.upsertDependency(
      ProgramDependenciesCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(_descCtrl.text.trim()),
        dependencyType: Value(_dependencyType),
        owner: Value(
            _ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
        status: Value(_status),
        dueDate: Value(_dueDate),
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
    final d = widget.dependency!;
    return AlertDialog(
      title: Row(
        children: [
          if (d.ref != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KColors.amberDim,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(d.ref!,
                  style: const TextStyle(
                      color: KColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
          ],
          const Text('Dependency'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _viewField('Description', d.description, large: true),
            Row(
              children: [
                Expanded(child: _viewField('Type', d.dependencyType)),
                Expanded(child: _viewField('Status', d.status)),
              ],
            ),
            Row(
              children: [
                if (d.owner != null && d.owner!.isNotEmpty)
                  Expanded(child: _viewField('Owner', d.owner)),
                if (d.dueDate != null)
                  Expanded(child: _viewField('Due Date', d.dueDate)),
              ],
            ),
            Row(
              children: [
                Expanded(child: _viewField('Source', d.source)),
                if (d.sourceNote != null && d.sourceNote!.isNotEmpty)
                  Expanded(child: _viewField('Source Note', d.sourceNote)),
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

    final isEdit = widget.dependency != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Dependency' : 'New Dependency'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _descCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Description *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownField(
                      label: 'Type',
                      value: _dependencyType,
                      items: _types,
                      onChanged: (v) => setState(() => _dependencyType = v!),
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
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ownerCtrl,
                      decoration: const InputDecoration(labelText: 'Owner'),
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

Widget _viewField(String label, String? value, {bool large = false}) {
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
            color: KColors.text,
            fontSize: large ? 14 : 12,
            height: 1.55,
          ),
        ),
      ],
    ),
  );
}
