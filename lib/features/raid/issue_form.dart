import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';

class IssueFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Issue? issue;
  final bool startInViewMode;

  const IssueFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.issue,
    this.startInViewMode = false,
  });

  @override
  State<IssueFormDialog> createState() => _IssueFormDialogState();
}

class _IssueFormDialogState extends State<IssueFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _descCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _resolutionCtrl;
  late TextEditingController _sourceNoteCtrl;
  String? _dueDate;

  String _priority = 'medium';
  String _status = 'open';
  String _source = 'manual';

  late bool _isViewing;

  final _priorities = ['low', 'medium', 'high', 'critical'];
  final _statuses = ['open', 'in progress', 'resolved', 'closed'];
  final _sources = ['manual', 'inbox', 'document', 'observation', 'meeting'];

  @override
  void initState() {
    super.initState();
    final issue = widget.issue;
    _descCtrl = TextEditingController(text: issue?.description ?? '');
    _ownerCtrl = TextEditingController(text: issue?.owner ?? '');
    _resolutionCtrl = TextEditingController(text: issue?.resolution ?? '');
    _sourceNoteCtrl = TextEditingController(text: issue?.sourceNote ?? '');
    _dueDate = issue?.dueDate;
    _priority = issue?.priority ?? 'medium';
    _status = issue?.status ?? 'open';
    _source = issue?.source ?? 'manual';
    _isViewing = widget.startInViewMode && issue != null;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _ownerCtrl.dispose();
    _resolutionCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  String _nextRef(List<Issue> existing) {
    final nums = existing
        .where((i) => i.ref != null && i.ref!.startsWith('I'))
        .map((i) => int.tryParse(i.ref!.substring(1)) ?? 0)
        .toList()
      ..sort();
    return 'I${(nums.isEmpty ? 0 : nums.last) + 1}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final existing = await widget.db.raidDao.getIssuesForProject(widget.projectId);
    final String ref = widget.issue?.ref ?? _nextRef(existing);

    final id = widget.issue?.id ?? const Uuid().v4();
    await widget.db.raidDao.upsertIssue(
      IssuesCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(_descCtrl.text.trim()),
        owner: Value(
            _ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
        dueDate: Value(_dueDate),
        priority: Value(_priority),
        status: Value(_status),
        resolution: Value(_resolutionCtrl.text.trim().isEmpty
            ? null
            : _resolutionCtrl.text.trim()),
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
    final i = widget.issue!;
    return AlertDialog(
      title: Row(
        children: [
          if (i.ref != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KColors.amberDim,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(i.ref!,
                  style: const TextStyle(
                      color: KColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
          ],
          const Text('Issue'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _viewField('Description', i.description, large: true),
              Row(
                children: [
                  Expanded(child: _viewField('Priority', i.priority)),
                  Expanded(child: _viewField('Status', i.status)),
                ],
              ),
              Row(
                children: [
                  if (i.owner != null && i.owner!.isNotEmpty)
                    Expanded(child: _viewField('Owner', i.owner)),
                  if (i.dueDate != null)
                    Expanded(child: _viewField('Due Date', i.dueDate)),
                ],
              ),
              if (i.resolution != null && i.resolution!.isNotEmpty)
                _viewField('Resolution', i.resolution),
              Row(
                children: [
                  Expanded(child: _viewField('Source', i.source)),
                  if (i.sourceNote != null && i.sourceNote!.isNotEmpty)
                    Expanded(child: _viewField('Source Note', i.sourceNote)),
                ],
              ),
            ],
          ),
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

    final isEdit = widget.issue != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Issue' : 'New Issue'),
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
                      label: 'Priority',
                      value: _priority,
                      items: _priorities,
                      onChanged: (v) => setState(() => _priority = v!),
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
              TextFormField(
                controller: _resolutionCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Resolution'),
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
