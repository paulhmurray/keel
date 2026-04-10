import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';

class GlossaryFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final GlossaryEntry? entry;

  const GlossaryFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.entry,
  });

  @override
  State<GlossaryFormDialog> createState() => _GlossaryFormDialogState();
}

class _GlossaryFormDialogState extends State<GlossaryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _acronymCtrl;
  late TextEditingController _descriptionCtrl;
  late TextEditingController _ownerCtrl;
  String _type = 'term';
  String _environment = 'production';
  String _status = 'active';

  static const _environments = ['production', 'test', 'development', 'legacy', 'all'];
  static const _statuses = ['active', 'planned', 'decommissioned'];

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _acronymCtrl = TextEditingController(text: e?.acronym ?? '');
    _descriptionCtrl = TextEditingController(text: e?.description ?? '');
    _ownerCtrl = TextEditingController(text: e?.owner ?? '');
    _type = e?.type ?? 'term';
    _environment = e?.environment ?? 'production';
    _status = e?.status ?? 'active';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _acronymCtrl.dispose();
    _descriptionCtrl.dispose();
    _ownerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final id = widget.entry?.id ?? const Uuid().v4();
    await widget.db.glossaryDao.upsert(GlossaryEntriesCompanion(
      id: Value(id),
      projectId: Value(widget.projectId),
      type: Value(_type),
      name: Value(_nameCtrl.text.trim()),
      acronym: Value(_acronymCtrl.text.trim().isEmpty ? null : _acronymCtrl.text.trim()),
      description: Value(_descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim()),
      owner: Value(_type == 'system' && _ownerCtrl.text.trim().isNotEmpty
          ? _ownerCtrl.text.trim()
          : null),
      environment: Value(_type == 'system' ? _environment : null),
      status: Value(_type == 'system' ? _status : null),
      updatedAt: Value(DateTime.now()),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.entry != null;
    final isSystem = _type == 'system';

    return AlertDialog(
      title: Text(isEdit ? 'Edit Entry' : 'New Glossary Entry'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type toggle
                Row(
                  children: [
                    _TypeChip(
                      label: 'Term / Acronym',
                      selected: _type == 'term',
                      onTap: () => setState(() => _type = 'term'),
                    ),
                    const SizedBox(width: 8),
                    _TypeChip(
                      label: 'System',
                      selected: _type == 'system',
                      onTap: () => setState(() => _type = 'system'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Name + Acronym
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _nameCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: isSystem ? 'System name *' : 'Full term *',
                          hintText: isSystem ? 'e.g. SAP' : 'e.g. Programme Management Office',
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _acronymCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Acronym',
                          hintText: 'e.g. PMO',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Description
                TextFormField(
                  controller: _descriptionCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: isSystem ? 'What it does' : 'Definition',
                    hintText: isSystem
                        ? 'Brief description of what this system does'
                        : 'Plain English definition',
                  ),
                ),

                // System-only fields
                if (isSystem) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ownerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Owner / Team',
                      hintText: 'e.g. Finance',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownField(
                          label: 'Environment',
                          value: _environment,
                          items: _environments,
                          onChanged: (v) => setState(() => _environment = v!),
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
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? KColors.amberDim : KColors.surface2,
          border: Border.all(
            color: selected ? KColors.amber : KColors.border2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? KColors.amber : KColors.textDim,
          ),
        ),
      ),
    );
  }
}
