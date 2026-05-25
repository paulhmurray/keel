import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../providers/settings_provider.dart';
import '../theme/keel_colors.dart';
import 'entity_picker.dart';
import 'role_picker_field.dart';

/// Inline person picker for forms — autocomplete from the project's Persons
/// table, with a pinned "Me — [name]" shortcut and an "Add new" affordance
/// that opens the canonical [AddPersonDialog].
///
/// Backed by [EntityPickerField], shared with role/system/term pickers.
class PersonPickerField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final List<Person> persons;
  final AppDatabase db;
  final String projectId;
  final VoidCallback onPersonCreated;

  const PersonPickerField({
    super.key,
    required this.controller,
    required this.label,
    required this.persons,
    required this.db,
    required this.projectId,
    required this.onPersonCreated,
  });

  @override
  Widget build(BuildContext context) {
    final myName = context.watch<SettingsProvider>().settings.myName;
    return EntityPickerField<Person>(
      controller: controller,
      label: label,
      items: persons,
      displayName: (p) => p.name,
      secondaryLine: (p) => [p.role, p.organisation]
          .where((s) => s != null && s.isNotEmpty)
          .join(' · '),
      itemIcon: Icons.person_outline,
      addNewSuffix: 'as new person',
      shortcut: myName.isEmpty
          ? null
          : EntityPickerShortcut<Person>(
              label: 'Me — $myName',
              icon: Icons.person_pin_outlined,
              iconColor: KColors.phosphor,
              textColor: KColors.phosphor,
              displayString: myName,
              onSelected: () async => null,
              showFor: (q) {
                final qq = q.toLowerCase().trim();
                return qq.isEmpty ||
                    myName.toLowerCase().contains(qq) ||
                    'me'.contains(qq);
              },
            ),
      onAddNew: (ctx, query) async {
        final result = await showDialog<NewPersonResult>(
          context: ctx,
          builder: (_) =>
              AddPersonDialog(name: query, db: db, projectId: projectId),
        );
        if (result == null) return null;
        final now = DateTime.now();
        final id = const Uuid().v4();
        await db.peopleDao.upsertPerson(PersonsCompanion(
          id: Value(id),
          projectId: Value(projectId),
          name: Value(result.name),
          role: Value(result.role),
          organisation: Value(result.organisation),
          personType: Value(result.personType),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
        onPersonCreated();
        // Refetch so the returned object has the freshly-persisted id.
        final fetched = await db.peopleDao.getPersonsForProject(projectId);
        return fetched.firstWhere(
          (p) => p.id == id,
          orElse: () => Person(
            id: id,
            projectId: projectId,
            name: result.name,
            role: result.role,
            organisation: result.organisation,
            personType: result.personType,
            createdAt: now,
            updatedAt: now,
          ),
        );
      },
    );
  }
}

/// Modal "find or create a person" dialog. Used for slot-assignment flows
/// (e.g. assigning someone to a stakeholder role). Returns the picked
/// Person, or null on cancel.
Future<Person?> showPersonPicker({
  required BuildContext context,
  required AppDatabase db,
  required String projectId,
  required List<Person> persons,
  String title = 'Assign Person',
}) {
  return showEntityPicker<Person>(
    context: context,
    title: title,
    items: persons,
    displayName: (p) => p.name,
    secondaryLine: (p) => [p.role, p.organisation]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · '),
    itemIcon: Icons.person_outline,
    itemIconColor: KColors.textDim,
    addNewLabel: 'Add new person',
    searchHint: 'Search people…',
    onAddNew: (ctx, query) async {
      final result = await showDialog<NewPersonResult>(
        context: ctx,
        builder: (_) =>
            AddPersonDialog(name: query, db: db, projectId: projectId),
      );
      if (result == null) return null;
      final now = DateTime.now();
      final id = const Uuid().v4();
      await db.peopleDao.upsertPerson(PersonsCompanion(
        id: Value(id),
        projectId: Value(projectId),
        name: Value(result.name),
        role: Value(result.role),
        organisation: Value(result.organisation),
        personType: Value(result.personType),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      return Person(
        id: id,
        projectId: projectId,
        name: result.name,
        role: result.role,
        organisation: result.organisation,
        personType: result.personType,
        createdAt: now,
        updatedAt: now,
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Add new person dialog (shared)
// ---------------------------------------------------------------------------

class NewPersonResult {
  final String name;
  final String? role;
  final String? organisation;
  final String personType;

  const NewPersonResult({
    required this.name,
    this.role,
    this.organisation,
    required this.personType,
  });
}

/// Rich "Add Person" dialog — capture name, role (via [RolePickerField] so
/// known roles are suggested), organisation, and person type.
class AddPersonDialog extends StatefulWidget {
  final String name;
  final AppDatabase db;
  final String projectId;

  const AddPersonDialog({
    super.key,
    required this.name,
    required this.db,
    required this.projectId,
  });

  @override
  State<AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<AddPersonDialog> {
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
    Navigator.of(context).pop(NewPersonResult(
      name: name,
      role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
      organisation: _orgCtrl.text.trim().isEmpty ? null : _orgCtrl.text.trim(),
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
        width: 360,
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
            RolePickerField(
              controller: _roleCtrl,
              label: 'Role (optional)',
              db: widget.db,
              projectId: widget.projectId,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _orgCtrl,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration:
                  const InputDecoration(labelText: 'Organisation (optional)'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            const Text('TYPE',
                style: TextStyle(
                    color: KColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1)),
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
                          color: selected ? KColors.bg : KColors.textDim)),
                  selected: selected,
                  selectedColor: KColors.amber,
                  backgroundColor: KColors.surface2,
                  side: BorderSide(
                      color: selected ? KColors.amber : KColors.border2),
                  onSelected: (_) => setState(() => _personType = value),
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
        ElevatedButton(onPressed: _submit, child: const Text('Add Person')),
      ],
    );
  }
}
