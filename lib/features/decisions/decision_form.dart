import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';

// Sentinel value used in the autocomplete options list
const _kAddSentinel = '\x00__add__';

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
  List<Person> _persons = [];

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
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final persons = await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = persons);
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
                      child: _PersonPickerField(
                        controller: _decisionMakerCtrl,
                        label: 'Decision Maker',
                        persons: _persons,
                        db: widget.db,
                        projectId: widget.projectId,
                        onPersonCreated: _loadPersons,
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

// ---------------------------------------------------------------------------
// Person picker autocomplete field
// ---------------------------------------------------------------------------

class _PersonPickerField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final List<Person> persons;
  final AppDatabase db;
  final String projectId;
  final VoidCallback onPersonCreated;

  const _PersonPickerField({
    required this.controller,
    required this.label,
    required this.persons,
    required this.db,
    required this.projectId,
    required this.onPersonCreated,
  });

  @override
  State<_PersonPickerField> createState() => _PersonPickerFieldState();
}

class _PersonPickerFieldState extends State<_PersonPickerField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  List<String> _optionsFor(String query) {
    final q = query.toLowerCase().trim();
    final matches = widget.persons
        .where((p) => p.name.toLowerCase().contains(q))
        .map((p) => p.name)
        .take(6)
        .toList();
    if (q.isNotEmpty) matches.add(_kAddSentinel);
    return matches;
  }

  Future<void> _handleAddNew(String query) async {
    final result = await showDialog<_NewPersonResult>(
      context: context,
      builder: (_) => _AddPersonDialog(name: query),
    );
    if (result != null && mounted) {
      final id = const Uuid().v4();
      final now = DateTime.now();
      await widget.db.peopleDao.upsertPerson(PersonsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        name: Value(result.name),
        role: Value(result.role),
        organisation: Value(result.organisation),
        personType: Value(result.personType),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      widget.controller.text = result.name;
      widget.onPersonCreated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (v) => _optionsFor(v.text),
      displayStringForOption: (opt) =>
          opt == _kAddSentinel ? widget.controller.text : opt,
      fieldViewBuilder: (ctx, ctrl, focusNode, onSubmitted) => TextFormField(
        controller: ctrl,
        focusNode: focusNode,
        decoration: InputDecoration(labelText: widget.label),
        onFieldSubmitted: (_) => onSubmitted(),
      ),
      optionsViewBuilder: (ctx, onSelected, options) {
        final query = widget.controller.text.trim();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: KColors.surface2,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: KColors.border2),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 280),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: options.map((opt) {
                  if (opt == _kAddSentinel) {
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: const Icon(Icons.person_add_outlined,
                          size: 14, color: KColors.phosphor),
                      title: Text(
                        'Add "$query" as new person',
                        style: const TextStyle(
                          color: KColors.phosphor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        onSelected(opt);
                        _handleAddNew(query);
                      },
                    );
                  }
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.person_outline,
                        size: 14, color: KColors.textDim),
                    title: Text(opt,
                        style: const TextStyle(
                            color: KColors.text, fontSize: 12)),
                    onTap: () => onSelected(opt),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
      onSelected: (opt) {
        if (opt != _kAddSentinel) {
          widget.controller.text = opt;
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Add new person dialog (with type selector)
// ---------------------------------------------------------------------------

class _NewPersonResult {
  final String name;
  final String? role;
  final String? organisation;
  final String personType;

  const _NewPersonResult({
    required this.name,
    this.role,
    this.organisation,
    required this.personType,
  });
}

class _AddPersonDialog extends StatefulWidget {
  final String name;
  const _AddPersonDialog({required this.name});

  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog> {
  late TextEditingController _nameCtrl;
  final _roleCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  String _personType = 'stakeholder';

  static const _types = [
    ('stakeholder', 'Stakeholder'),
    ('colleague', 'Colleague'),
    ('exec', 'Executive'),
    ('vendor', 'Vendor'),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _orgCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(_NewPersonResult(
      name: name,
      role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
      organisation:
          _orgCtrl.text.trim().isEmpty ? null : _orgCtrl.text.trim(),
      personType: _personType,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Add New Person',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Name *'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _roleCtrl,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration:
                  const InputDecoration(labelText: 'Role (optional)'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _orgCtrl,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(
                  labelText: 'Organisation (optional)'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            const Text(
              'TYPE',
              style: TextStyle(
                color: KColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _types.map((t) {
                final (value, label) = t;
                final selected = _personType == value;
                return ChoiceChip(
                  label: Text(label,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? KColors.bg : KColors.textDim,
                      )),
                  selected: selected,
                  selectedColor: KColors.amber,
                  backgroundColor: KColors.surface2,
                  side: BorderSide(
                    color: selected ? KColors.amber : KColors.border2,
                  ),
                  onSelected: (_) =>
                      setState(() => _personType = value),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Add Person'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

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
