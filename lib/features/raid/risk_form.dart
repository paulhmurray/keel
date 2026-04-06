import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';

class RiskFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final Risk? risk;
  final bool startInViewMode;

  const RiskFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.risk,
    this.startInViewMode = false,
  });

  @override
  State<RiskFormDialog> createState() => _RiskFormDialogState();
}

class _RiskFormDialogState extends State<RiskFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _descCtrl;
  late TextEditingController _mitigationCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _sourceNoteCtrl;

  String _likelihood = 'medium';
  String _impact = 'medium';
  String _status = 'open';
  String _source = 'manual';

  late bool _isViewing;

  final _levels = ['low', 'medium', 'high'];
  final _statuses = ['open', 'in progress', 'closed', 'accepted'];
  final _sources = ['manual', 'inbox', 'document', 'observation', 'meeting'];

  @override
  void initState() {
    super.initState();
    final r = widget.risk;
    _descCtrl = TextEditingController(text: r?.description ?? '');
    _mitigationCtrl = TextEditingController(text: r?.mitigation ?? '');
    _ownerCtrl = TextEditingController(text: r?.owner ?? '');
    _sourceNoteCtrl = TextEditingController(text: r?.sourceNote ?? '');
    _likelihood = r?.likelihood ?? 'medium';
    _impact = r?.impact ?? 'medium';
    _status = r?.status ?? 'open';
    _source = r?.source ?? 'manual';
    _isViewing = widget.startInViewMode && r != null;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _mitigationCtrl.dispose();
    _ownerCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  String _nextRef(List<Risk> existing) {
    final nums = existing
        .where((r) => r.ref != null && r.ref!.startsWith('R'))
        .map((r) {
          final n = int.tryParse(r.ref!.substring(1));
          return n ?? 0;
        })
        .toList();
    nums.sort();
    return 'R${(nums.isEmpty ? 0 : nums.last) + 1}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final String ref = widget.risk?.ref ??
        _nextRef(await widget.db.raidDao.getRisksForProject(widget.projectId));

    final id = widget.risk?.id ?? const Uuid().v4();
    await widget.db.raidDao.upsertRisk(
      RisksCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(_descCtrl.text.trim()),
        likelihood: Value(_likelihood),
        impact: Value(_impact),
        mitigation: Value(_mitigationCtrl.text.trim().isEmpty
            ? null
            : _mitigationCtrl.text.trim()),
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

  Widget _readView() {
    final r = widget.risk!;
    return AlertDialog(
      title: Row(
        children: [
          if (r.ref != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KColors.amberDim,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(r.ref!,
                  style: const TextStyle(
                      color: KColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
          ],
          const Text('Risk'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _viewField('Description', r.description, large: true),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: _viewField('Likelihood', r.likelihood)),
                  Expanded(child: _viewField('Impact', r.impact)),
                  Expanded(child: _viewField('Status', r.status)),
                ],
              ),
              if (r.owner != null && r.owner!.isNotEmpty)
                _viewField('Owner', r.owner),
              if (r.mitigation != null && r.mitigation!.isNotEmpty)
                _viewField('Mitigation', r.mitigation),
              Row(
                children: [
                  Expanded(child: _viewField('Source', r.source)),
                  if (r.sourceNote != null && r.sourceNote!.isNotEmpty)
                    Expanded(child: _viewField('Source Note', r.sourceNote)),
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

    final isEdit = widget.risk != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit Risk' : 'New Risk'),
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
                        label: 'Likelihood',
                        value: _likelihood,
                        items: _levels,
                        onChanged: (v) => setState(() => _likelihood = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownField(
                        label: 'Impact',
                        value: _impact,
                        items: _levels,
                        onChanged: (v) => setState(() => _impact = v!),
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
                TextFormField(
                  controller: _ownerCtrl,
                  decoration: const InputDecoration(labelText: 'Owner'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mitigationCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Mitigation'),
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
