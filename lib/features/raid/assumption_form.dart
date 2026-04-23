import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';

class AssumptionFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Assumption? assumption;
  final bool startInViewMode;

  const AssumptionFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.assumption,
    this.startInViewMode = false,
  });

  @override
  State<AssumptionFormDialog> createState() => _AssumptionFormDialogState();
}

class _AssumptionFormDialogState extends State<AssumptionFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _descCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _sourceNoteCtrl;

  String _status = 'open';
  String _source = 'manual';

  late bool _isViewing;

  final _statuses = ['open', 'validated', 'invalidated', 'closed'];
  final _sources = ['manual', 'inbox', 'document', 'observation', 'meeting'];

  @override
  void initState() {
    super.initState();
    final a = widget.assumption;
    _descCtrl = TextEditingController(text: a?.description ?? '');
    _ownerCtrl = TextEditingController(text: a?.owner ?? '');
    _sourceNoteCtrl = TextEditingController(text: a?.sourceNote ?? '');
    _status = a?.status ?? 'open';
    _source = a?.source ?? 'manual';
    _isViewing = widget.startInViewMode && a != null;
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

    String ref = widget.assumption?.ref ??
        _nextRef(await widget.db.raidDao.getAssumptionsForProject(widget.projectId));

    final id = widget.assumption?.id ?? const Uuid().v4();
    await widget.db.raidDao.upsertAssumption(
      AssumptionsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(_descCtrl.text.trim()),
        owner: Value(
            _ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
        status: Value(_status),
        source: Value(_source),
        sourceNote: Value(_sourceNoteCtrl.text.trim().isEmpty
            ? null
            : _sourceNoteCtrl.text.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (mounted) Navigator.of(context).pop();
  }

  String _nextRef(List<Assumption> existing) {
    final nums = existing
        .where((a) => a.ref != null && a.ref!.startsWith('A'))
        .map((a) => int.tryParse(a.ref!.substring(1)) ?? 0)
        .toList()
      ..sort();
    return 'A${(nums.isEmpty ? 0 : nums.last) + 1}';
  }

  Widget _readView() {
    final a = widget.assumption!;
    return AlertDialog(
      title: Row(
        children: [
          if (a.ref != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          const Text('Assumption'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _viewField('Description', a.description, large: true),
            Row(
              children: [
                Expanded(child: _viewField('Status', a.status)),
                Expanded(child: _viewField('Source', a.source)),
              ],
            ),
            if (a.owner != null && a.owner!.isNotEmpty)
              _viewField('Owner', a.owner),
            if (a.sourceNote != null && a.sourceNote!.isNotEmpty)
              _viewField('Source Note', a.sourceNote),
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

    final isEdit = widget.assumption != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Assumption' : 'New Assumption'),
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
              TextFormField(
                controller: _ownerCtrl,
                decoration: const InputDecoration(labelText: 'Owner'),
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
                      label: 'Source',
                      value: _source,
                      items: _sources,
                      onChanged: (v) => setState(() => _source = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sourceNoteCtrl,
                decoration: const InputDecoration(labelText: 'Source Note'),
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
            fontSize: 10,
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
