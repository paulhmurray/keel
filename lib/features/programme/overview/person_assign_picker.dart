import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';

/// Shows a dialog to search for or create a person and returns the Person.
Future<Person?> showPersonAssignPicker(
  BuildContext context, {
  required AppDatabase db,
  required String projectId,
  required List<Person> existingPersons,
}) {
  return showDialog<Person>(
    context: context,
    builder: (_) => _PersonAssignDialog(
      db: db,
      projectId: projectId,
      existingPersons: existingPersons,
    ),
  );
}

class _PersonAssignDialog extends StatefulWidget {
  final AppDatabase db;
  final String projectId;
  final List<Person> existingPersons;

  const _PersonAssignDialog({
    required this.db,
    required this.projectId,
    required this.existingPersons,
  });

  @override
  State<_PersonAssignDialog> createState() => _PersonAssignDialogState();
}

class _PersonAssignDialogState extends State<_PersonAssignDialog> {
  final _searchCtrl = TextEditingController();
  bool _showCreate = false;

  final _nameCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  List<Person> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.existingPersons;
    return widget.existingPersons
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _orgCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAndAssign() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    final id = const Uuid().v4();
    await widget.db.peopleDao.upsertPerson(PersonsCompanion(
      id: Value(id),
      projectId: Value(widget.projectId),
      name: Value(name),
      role: Value(_roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim()),
      organisation: Value(
          _orgCtrl.text.trim().isEmpty ? null : _orgCtrl.text.trim()),
      email: Value(
          _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim()),
      personType: const Value('stakeholder'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    final person = await widget.db.peopleDao.getPersonById(id);
    if (mounted && person != null) {
      Navigator.of(context).pop(person);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Text(
        _showCreate ? 'Create New Person' : 'Assign Person',
        style: const TextStyle(color: KColors.text, fontSize: 14),
      ),
      content: SizedBox(
        width: 360,
        child: _showCreate ? _buildCreateForm() : _buildSearchPanel(),
      ),
      actions: _showCreate
          ? [
              TextButton(
                onPressed: () => setState(() => _showCreate = false),
                child: const Text('Back',
                    style: TextStyle(color: KColors.textDim, fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: _createAndAssign,
                child: const Text('Create & Assign'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: KColors.textDim, fontSize: 12)),
              ),
            ],
    );
  }

  Widget _buildSearchPanel() {
    final filtered = _filtered;
    final query = _searchCtrl.text.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Search or type name...',
            hintStyle: TextStyle(color: KColors.textDim, fontSize: 12),
            prefixIcon: Icon(Icons.search, size: 16, color: KColors.textDim),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(
            shrinkWrap: true,
            children: [
              ...filtered.map((p) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.person_outline,
                        size: 16, color: KColors.textDim),
                    title: Text(p.name,
                        style: const TextStyle(
                            color: KColors.text, fontSize: 13)),
                    subtitle: p.role != null
                        ? Text(
                            [p.role, p.organisation]
                                .where((s) => s != null)
                                .join(' · '),
                            style: const TextStyle(
                                color: KColors.textDim, fontSize: 11),
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(p),
                  )),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.person_add_outlined,
                    size: 16, color: KColors.phosphor),
                title: Text(
                  query.isNotEmpty
                      ? 'Create "$query" as new person'
                      : 'Create new person',
                  style: const TextStyle(
                      color: KColors.phosphor, fontSize: 13),
                ),
                onTap: () {
                  _nameCtrl.text = query;
                  setState(() => _showCreate = true);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCreateForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(labelText: 'Name *'),
          onSubmitted: (_) => _createAndAssign(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _roleCtrl,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(labelText: 'Role / Title'),
          onSubmitted: (_) => _createAndAssign(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _orgCtrl,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(labelText: 'Organisation'),
          onSubmitted: (_) => _createAndAssign(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailCtrl,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration:
              const InputDecoration(labelText: 'Email (optional)'),
          onSubmitted: (_) => _createAndAssign(),
        ),
      ],
    );
  }
}
