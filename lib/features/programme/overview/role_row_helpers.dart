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
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const RoleMoreMenu({
    super.key,
    required this.onMarkNA,
    required this.onRemove,
    this.onEditDetails,
    this.onRename,
    this.onDelete,
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
        if (v == 'rename') onRename?.call();
        if (v == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => [
        if (onEditDetails != null)
          const PopupMenuItem(
            value: 'details',
            height: 32,
            child: Text('Edit details…',
                style: TextStyle(color: KColors.text, fontSize: 12)),
          ),
        if (onRename != null)
          const PopupMenuItem(
            value: 'rename',
            height: 32,
            child: Text('Rename role…',
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
        if (onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            height: 32,
            child: Text('Delete role',
                style: TextStyle(color: KColors.red, fontSize: 12)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rename / delete dialogs
// ---------------------------------------------------------------------------

Future<String?> promptRenameRole(
    BuildContext context, String currentName) async {
  final ctrl = TextEditingController(text: currentName);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Rename Role',
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
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Role picker dialog — name field with best-practice suggestion chips
// ---------------------------------------------------------------------------

Future<String?> showRolePickerDialog({
  required BuildContext context,
  required String title,
  required List<String> suggestions,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RolePickerDialog(title: title, suggestions: suggestions),
  );
}

class _RolePickerDialog extends StatefulWidget {
  final String title;
  final List<String> suggestions;

  const _RolePickerDialog({
    required this.title,
    required this.suggestions,
  });

  @override
  State<_RolePickerDialog> createState() => _RolePickerDialogState();
}

class _RolePickerDialogState extends State<_RolePickerDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: Text(widget.title,
          style: const TextStyle(color: KColors.text, fontSize: 14)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.suggestions.isNotEmpty) ...[
              const Text(
                'Common picks',
                style: TextStyle(
                  color: KColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.15,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in widget.suggestions)
                    _SuggestionChip(
                      label: s,
                      onTap: () => Navigator.of(context).pop(s),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Or enter your own',
                style: TextStyle(
                  color: KColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.15,
                ),
              ),
              const SizedBox(height: 6),
            ],
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: KColors.text, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Role name'),
              onSubmitted: (_) => _submit(),
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
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.border2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 11, color: KColors.textDim),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: KColors.text, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmDeleteRole(BuildContext context, String roleName) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Delete Role?',
          style: TextStyle(color: KColors.text, fontSize: 14)),
      content: Text(
        'Permanently delete "$roleName"? This cannot be undone.',
        style: const TextStyle(color: KColors.textDim, fontSize: 12),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
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
