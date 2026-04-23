import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';

// ---------------------------------------------------------------------------
// N/A row — used in both stakeholder and team sections
// ---------------------------------------------------------------------------

class RoleNaRow extends StatelessWidget {
  final String roleName;
  final VoidCallback onRestore;

  const RoleNaRow({
    super.key,
    required this.roleName,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
      child: Row(
        children: [
          const Text('—',
              style: TextStyle(color: KColors.textMuted, fontSize: 12)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              roleName,
              style: const TextStyle(color: KColors.textMuted, fontSize: 12),
            ),
          ),
          const Text('N/A',
              style: TextStyle(color: KColors.textMuted, fontSize: 10)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRestore,
            child: const Text(
              'Restore',
              style: TextStyle(
                color: KColors.textDim,
                fontSize: 10,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add custom role button
// ---------------------------------------------------------------------------

class RoleAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onAdd;

  const RoleAddButton({
    super.key,
    required this.label,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
      child: GestureDetector(
        onTap: onAdd,
        child: Row(
          children: [
            const Icon(Icons.add, size: 14, color: KColors.textDim),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: KColors.textDim, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small action button
// ---------------------------------------------------------------------------

class RoleSmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const RoleSmallButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.border2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: const TextStyle(color: KColors.textDim, fontSize: 11),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// More (···) menu
// ---------------------------------------------------------------------------

class RoleMoreMenu extends StatelessWidget {
  final VoidCallback onMarkNA;
  final VoidCallback onRemove;
  final VoidCallback? onEditDetails;

  const RoleMoreMenu({
    super.key,
    required this.onMarkNA,
    required this.onRemove,
    this.onEditDetails,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: KColors.surface2,
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz, size: 16, color: KColors.textDim),
      iconSize: 16,
      constraints: const BoxConstraints(minWidth: 160),
      onSelected: (v) {
        if (v == 'na') onMarkNA();
        if (v == 'remove') onRemove();
        if (v == 'details') onEditDetails?.call();
      },
      itemBuilder: (_) => [
        if (onEditDetails != null)
          const PopupMenuItem(
            value: 'details',
            height: 32,
            child: Text('Edit details…',
                style: TextStyle(color: KColors.text, fontSize: 12)),
          ),
        const PopupMenuItem(
          value: 'na',
          height: 32,
          child: Text('Mark N/A',
              style: TextStyle(color: KColors.text, fontSize: 12)),
        ),
        const PopupMenuItem(
          value: 'remove',
          height: 32,
          child: Text('Remove person',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers for restoring N/A stakeholder/team roles
// ---------------------------------------------------------------------------

Future<void> restoreStakeholderRole(AppDatabase db, String roleId) async {
  await db.stakeholderRoleDao.updateRole(StakeholderRolesCompanion(
    id: Value(roleId),
    isApplicable: const Value(true),
    updatedAt: Value(DateTime.now()),
  ));
}

Future<void> restoreTeamRole(AppDatabase db, String roleId) async {
  await db.teamRoleDao.updateRole(TeamRolesCompanion(
    id: Value(roleId),
    isApplicable: const Value(true),
    updatedAt: Value(DateTime.now()),
  ));
}
