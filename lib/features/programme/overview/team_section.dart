import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database.dart';
import '../../../core/programme/scaffold_definitions.dart';
import '../../../shared/theme/keel_colors.dart';
import 'person_assign_picker.dart';
import 'role_row_helpers.dart';

class TeamSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final List<TeamRole> roles;
  final List<Person> persons;

  const TeamSection({
    super.key,
    required this.projectId,
    required this.db,
    required this.roles,
    required this.persons,
  });

  @override
  Widget build(BuildContext context) {
    const groups = [
      ('programme_leadership', 'PROGRAMME LEADERSHIP'),
      ('business_analysis', 'BUSINESS & ANALYSIS'),
      ('technology', 'TECHNOLOGY'),
      ('specialist', 'SPECIALIST'),
      ('governance', 'GOVERNANCE & ASSURANCE'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (group, label) in groups) ...[
          _TeamGroup(
            groupKey: group,
            groupLabel: label,
            roles: roles.where((r) => r.teamGroup == group).toList(),
            projectId: projectId,
            db: db,
            persons: persons,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Group
// ---------------------------------------------------------------------------

class _TeamGroup extends StatelessWidget {
  final String groupKey;
  final String groupLabel;
  final List<TeamRole> roles;
  final String projectId;
  final AppDatabase db;
  final List<Person> persons;

  const _TeamGroup({
    required this.groupKey,
    required this.groupLabel,
    required this.roles,
    required this.projectId,
    required this.db,
    required this.persons,
  });

  int get _filledCount =>
      roles.where((r) => r.isApplicable && r.personId != null).length;
  int get _applicableCount => roles.where((r) => r.isApplicable).length;

  @override
  Widget build(BuildContext context) {
    final visible = roles.where((r) => r.isApplicable).toList();
    final naRoles = roles.where((r) => !r.isApplicable).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          child: Row(
            children: [
              Text(
                groupLabel,
                style: const TextStyle(
                  color: KColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.15,
                ),
              ),
              const Spacer(),
              Text(
                '$_filledCount of $_applicableCount filled',
                style: const TextStyle(
                  color: KColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        const Divider(color: KColors.border, height: 8),

        for (final role in visible)
          _TeamRoleRow(
            role: role,
            db: db,
            projectId: projectId,
            persons: persons,
            hint: _hintFor(role.roleName),
          ),

        for (final role in naRoles)
          RoleNaRow(
            roleName: role.roleName,
            onRestore: () => restoreTeamRole(db, role.id),
          ),

        RoleAddButton(
          label: 'Add team member to this group',
          onAdd: () => _addCustomRole(context),
        ),
      ],
    );
  }

  String _hintFor(String roleName) {
    final match = teamScaffold.where((r) => r.roleName == roleName);
    return match.isNotEmpty ? match.first.hint : '';
  }

  Future<void> _addCustomRole(BuildContext context) async {
    final name = await _promptRoleName(context);
    if (name == null || name.isEmpty) return;
    final uuid = const Uuid();
    final now = DateTime.now();
    await db.teamRoleDao.upsert(TeamRolesCompanion.insert(
      id: uuid.v4(),
      projectId: projectId,
      roleName: name,
      teamGroup: groupKey,
      isScaffold: const Value(false),
      isApplicable: const Value(true),
      sortOrder: Value(
          roles.fold(0, (m, r) => r.sortOrder > m ? r.sortOrder : m) + 1),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  Future<String?> _promptRoleName(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KColors.surface,
        title: const Text('Add Team Role',
            style: TextStyle(color: KColors.text, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: KColors.text, fontSize: 13),
          decoration: const InputDecoration(labelText: 'Role name'),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: KColors.textDim, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team role row
// ---------------------------------------------------------------------------

class _TeamRoleRow extends StatelessWidget {
  final TeamRole role;
  final AppDatabase db;
  final String projectId;
  final List<Person> persons;
  final String hint;

  const _TeamRoleRow({
    required this.role,
    required this.db,
    required this.projectId,
    required this.persons,
    required this.hint,
  });

  Person? get _person =>
      persons.where((p) => p.id == role.personId).firstOrNull;
  bool get _filled => role.personId != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(
          color: _filled ? KColors.border2 : KColors.border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: Icon(
              _filled ? Icons.circle : Icons.circle_outlined,
              size: 10,
              color: _filled ? KColors.phosphor : KColors.textMuted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.roleName,
                  style: TextStyle(
                    color: _filled ? KColors.text : KColors.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_filled && _person != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [_person!.name, _person!.role, _person!.organisation]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(
                        color: KColors.textDim, fontSize: 11),
                  ),
                ] else if (hint.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: const TextStyle(
                        color: KColors.textMuted, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!_filled)
            RoleSmallButton(
                label: 'Assign', onTap: () => _assign(context))
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoleSmallButton(
                    label: 'Change', onTap: () => _assign(context)),
                const SizedBox(width: 6),
                RoleMoreMenu(
                  onMarkNA: () => _markNA(),
                  onRemove: () => _removePerson(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _assign(BuildContext context) async {
    final person = await showPersonAssignPicker(
      context,
      db: db,
      projectId: projectId,
      existingPersons: persons,
    );
    if (person != null) {
      await db.teamRoleDao.updateRole(TeamRolesCompanion(
        id: Value(role.id),
        personId: Value(person.id),
        updatedAt: Value(DateTime.now()),
      ));
    }
  }

  Future<void> _markNA() async {
    await db.teamRoleDao.updateRole(TeamRolesCompanion(
      id: Value(role.id),
      isApplicable: const Value(false),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _removePerson() async {
    await db.teamRoleDao.updateRole(TeamRolesCompanion(
      id: Value(role.id),
      personId: const Value(null),
      updatedAt: Value(DateTime.now()),
    ));
  }
}
