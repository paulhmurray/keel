import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../core/programme/scaffold_definitions.dart';
import '../theme/keel_colors.dart';
import 'entity_picker.dart';

/// Inline role picker — suggests roles already used in the project plus the
/// best-practice scaffold role names. "Add new" is free-text (the value is
/// committed straight to the controller, then stored wherever the caller
/// persists it).
class RolePickerField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final AppDatabase db;
  final String projectId;

  const RolePickerField({
    super.key,
    required this.controller,
    required this.label,
    required this.db,
    required this.projectId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: collectRoleSuggestions(db: db, projectId: projectId),
      builder: (ctx, snap) {
        final roles = snap.data ?? const <String>[];
        return EntityPickerField<String>(
          controller: controller,
          label: label,
          items: roles,
          displayName: (r) => r,
          itemIcon: Icons.badge_outlined,
          itemIconColor: KColors.textDim,
          addNewSuffix: 'as new role',
          onAddNew: (ctx, query) async => query.trim().isEmpty ? null : query.trim(),
        );
      },
    );
  }
}

/// Modal role picker.
Future<String?> showRolePicker({
  required BuildContext context,
  required AppDatabase db,
  required String projectId,
  String title = 'Pick a role',
}) async {
  final roles = await collectRoleSuggestions(db: db, projectId: projectId);
  if (!context.mounted) return null;
  return showEntityPicker<String>(
    context: context,
    title: title,
    items: roles,
    displayName: (r) => r,
    itemIcon: Icons.badge_outlined,
    addNewLabel: 'role',
    searchHint: 'Search roles…',
    onAddNew: (ctx, query) async {
      return query.trim().isEmpty ? null : query.trim();
    },
  );
}

/// Aggregates known roles for a project. Order:
///   1. Roles already in use on Persons in this project (most useful).
///   2. Best-practice scaffold role names (stakeholder + team) for breadth.
/// Deduplicated case-insensitively, preserving first-seen casing.
Future<List<String>> collectRoleSuggestions({
  required AppDatabase db,
  required String projectId,
}) async {
  final persons = await db.peopleDao.getPersonsForProject(projectId);
  final fromPeople = persons
      .map((p) => p.role)
      .whereType<String>()
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty);

  final fromScaffold = <String>[
    for (final s in stakeholderScaffold) s.roleName,
    for (final t in teamScaffold) t.roleName,
  ];

  final seen = <String>{};
  final out = <String>[];
  for (final r in [...fromPeople, ...fromScaffold]) {
    final key = r.toLowerCase();
    if (seen.add(key)) out.add(r);
  }
  return out;
}
