import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../providers/settings_provider.dart';
import '../theme/keel_colors.dart';

const _kAddSentinel = '\x00__add__';
const _kMeSentinel = '\x00__me__';

/// A text field with autocomplete from the project's People list.
/// Shows "Me — [name]" at the top when the user has set their name in Settings.
/// Offers an "Add new person" option when typing an unknown name.
class PersonPickerField extends StatefulWidget {
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
  State<PersonPickerField> createState() => _PersonPickerFieldState();
}

class _PersonPickerFieldState extends State<PersonPickerField> {
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

  List<String> _optionsFor(String query, String myName) {
    final q = query.toLowerCase().trim();
    final opts = <String>[];

    // "Me" shortcut at top if name is set and matches query (or query empty)
    if (myName.isNotEmpty &&
        (q.isEmpty || myName.toLowerCase().contains(q) || 'me'.contains(q))) {
      opts.add(_kMeSentinel);
    }

    final matches = widget.persons
        .where((p) => p.name.toLowerCase().contains(q))
        .map((p) => p.name)
        .take(6)
        .toList();
    opts.addAll(matches);

    if (q.isNotEmpty) opts.add(_kAddSentinel);
    return opts;
  }

  Future<void> _handleAddNew(String query) async {
    final result = await showDialog<_NewPersonResult>(
      context: context,
      builder: (_) => _AddPersonDialog(name: query),
    );
    if (result != null && mounted) {
      final now = DateTime.now();
      await widget.db.peopleDao.upsertPerson(PersonsCompanion(
        id: Value(const Uuid().v4()),
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
    final myName = context.read<SettingsProvider>().settings.myName;

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (v) => _optionsFor(v.text, myName),
      displayStringForOption: (opt) {
        if (opt == _kMeSentinel) return myName;
        if (opt == _kAddSentinel) return widget.controller.text;
        return opt;
      },
      fieldViewBuilder: (ctx, ctrl, focusNode, onSubmitted) => TextFormField(
        controller: ctrl,
        focusNode: focusNode,
        style: const TextStyle(color: KColors.text, fontSize: 12),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: KColors.textDim, fontSize: 11),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
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
                  if (opt == _kMeSentinel) {
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: const Icon(Icons.person_pin_outlined,
                          size: 14, color: KColors.phosphor),
                      title: Text(
                        'Me — $myName',
                        style: const TextStyle(
                          color: KColors.phosphor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        widget.controller.text = myName;
                        onSelected(opt);
                      },
                    );
                  }
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
                        style: const TextStyle(color: KColors.text, fontSize: 12)),
                    onTap: () => onSelected(opt),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
      onSelected: (opt) {
        if (opt == _kMeSentinel) {
          widget.controller.text = myName;
        } else if (opt != _kAddSentinel) {
          widget.controller.text = opt;
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Add new person dialog (shared)
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
              decoration: const InputDecoration(labelText: 'Role (optional)'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _orgCtrl,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Organisation (optional)'),
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
