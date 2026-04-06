import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';

class DecisionFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Decision? decision;
  final bool startInViewMode;

  const DecisionFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.decision,
    this.startInViewMode = false,
  });

  @override
  State<DecisionFormDialog> createState() => _DecisionFormDialogState();
}

class _DecisionFormDialogState extends State<DecisionFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _descCtrl;
  late TextEditingController _decisionMakerCtrl;
  String? _dueDate;
  late TextEditingController _rationaleCtrl;
  late TextEditingController _outcomeCtrl;
  late TextEditingController _sourceNoteCtrl;

  String _status = 'pending';
  String _source = 'manual';

  late bool _isViewing;

  final _statuses = ['pending', 'approved', 'rejected', 'deferred', 'closed'];
  final _sources = ['manual', 'inbox', 'document', 'observation', 'meeting'];

  @override
  void initState() {
    super.initState();
    final d = widget.decision;
    _descCtrl = TextEditingController(text: d?.description ?? '');
    _decisionMakerCtrl =
        TextEditingController(text: d?.decisionMaker ?? '');
    _dueDate = d?.dueDate;
    _rationaleCtrl = TextEditingController(text: d?.rationale ?? '');
    _outcomeCtrl = TextEditingController(text: d?.outcome ?? '');
    _sourceNoteCtrl = TextEditingController(text: d?.sourceNote ?? '');
    _status = d?.status ?? 'pending';
    _source = d?.source ?? 'manual';
    _isViewing = widget.startInViewMode && d != null;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _decisionMakerCtrl.dispose();
    _rationaleCtrl.dispose();
    _outcomeCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final existing = await widget.db.decisionsDao.getDecisionsForProject(widget.projectId);
    final nums = existing
        .where((d) => d.ref != null && d.ref!.startsWith('DC'))
        .map((d) => int.tryParse(d.ref!.substring(2)) ?? 0)
        .toList()
      ..sort();
    final String ref = widget.decision?.ref ??
        'DC${(nums.isEmpty ? 0 : nums.last) + 1}';

    final id = widget.decision?.id ?? const Uuid().v4();
    await widget.db.decisionsDao.upsertDecision(
      DecisionsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(_descCtrl.text.trim()),
        status: Value(_status),
        decisionMaker: Value(_decisionMakerCtrl.text.trim().isEmpty
            ? null
            : _decisionMakerCtrl.text.trim()),
        dueDate: Value(_dueDate),
        rationale: Value(_rationaleCtrl.text.trim().isEmpty
            ? null
            : _rationaleCtrl.text.trim()),
        outcome: Value(_outcomeCtrl.text.trim().isEmpty
            ? null
            : _outcomeCtrl.text.trim()),
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
    final d = widget.decision!;
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
          const Text('Decision'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _viewField('Description', d.description, large: true),
              Row(
                children: [
                  Expanded(child: _viewField('Status', d.status)),
                  if (d.decisionMaker != null && d.decisionMaker!.isNotEmpty)
                    Expanded(child: _viewField('Decision Maker', d.decisionMaker)),
                ],
              ),
              if (d.dueDate != null) _viewField('Due Date', d.dueDate),
              if (d.rationale != null && d.rationale!.isNotEmpty)
                _viewField('Rationale', d.rationale),
              if (d.outcome != null && d.outcome!.isNotEmpty)
                _viewField('Outcome', d.outcome),
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

    final isEdit = widget.decision != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Decision' : 'New Decision'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
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
                        label: 'Status',
                        value: _status,
                        items: _statuses,
                        onChanged: (v) => setState(() => _status = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _decisionMakerCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Decision Maker'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DatePickerField(
                  label: 'Due Date',
                  isoValue: _dueDate,
                  onChanged: (v) => setState(() => _dueDate = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _rationaleCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Rationale'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _outcomeCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Outcome'),
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
