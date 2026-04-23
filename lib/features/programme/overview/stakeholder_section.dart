import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/database.dart';
import '../../../core/programme/scaffold_definitions.dart';
import '../../../shared/theme/keel_colors.dart';
import 'person_assign_picker.dart';
import 'role_row_helpers.dart';

// ─── Engagement status metadata ───────────────────────────────────────────────
const _kEngagementOptions = [
  ('not_started',        'Not started'),
  ('engaged',            'Engaged'),
  ('gap_action_required','Gap — action required'),
  ('not_engaged',        'Not engaged'),
  ('complete',           'Complete'),
];

const _kPriorityOptions = [
  ('critical', 'Critical'),
  ('high',     'High'),
  ('medium',   'Medium'),
  ('low',      'Low'),
];

Widget _engagementChip(String? status) {
  final (label, color, bg) = switch (status) {
    'engaged'            => ('● Engaged',         KColors.phosphor, KColors.phosDim),
    'gap_action_required'=> ('⚠ Gap — action req', KColors.red,      KColors.redDim),
    'not_engaged'        => ('○ Not engaged',      KColors.amber,    KColors.amberDim),
    'complete'           => ('✓ Complete',         KColors.phosphor, KColors.phosDim),
    _                    => ('— Not started',      KColors.textMuted, Colors.transparent),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(3),
      border: bg == Colors.transparent
          ? Border.all(color: KColors.border2)
          : null,
    ),
    child: Text(label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

class StakeholderSection extends StatelessWidget {
  final String projectId;
  final AppDatabase db;
  final List<StakeholderRole> roles;
  final List<Person> persons;

  const StakeholderSection({
    super.key,
    required this.projectId,
    required this.db,
    required this.roles,
    required this.persons,
  });

  @override
  Widget build(BuildContext context) {
    const tiers = [
      ('accountable', 'ACCOUNTABLE'),
      ('active', 'ACTIVE'),
      ('affected', 'AFFECTED'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (type, label) in tiers) ...[
          _TierGroup(
            tierType: type,
            tierLabel: label,
            roles: roles.where((r) => r.roleType == type).toList(),
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
// Tier group
// ---------------------------------------------------------------------------

class _TierGroup extends StatelessWidget {
  final String tierType;
  final String tierLabel;
  final List<StakeholderRole> roles;
  final String projectId;
  final AppDatabase db;
  final List<Person> persons;

  const _TierGroup({
    required this.tierType,
    required this.tierLabel,
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
        // Tier header
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          child: Row(
            children: [
              Text(
                tierLabel,
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

        // Applicable roles
        for (final role in visible)
          _StakeholderRoleRow(
            role: role,
            db: db,
            projectId: projectId,
            persons: persons,
            hint: _hintFor(role.roleName),
            isCritical: _isCritical(role.roleName),
          ),

        // N/A roles (collapsed)
        for (final role in naRoles)
          RoleNaRow(
            roleName: role.roleName,
            onRestore: () => restoreStakeholderRole(db, role.id),
          ),

        // Add custom
        RoleAddButton(
          label: 'Add stakeholder to this tier',
          onAdd: () => _addCustomRole(context),
        ),
      ],
    );
  }

  String _hintFor(String roleName) {
    final match = stakeholderScaffold.where((r) => r.roleName == roleName);
    return match.isNotEmpty ? match.first.hint : '';
  }

  bool _isCritical(String roleName) {
    final match = stakeholderScaffold.where((r) => r.roleName == roleName);
    return match.isNotEmpty ? match.first.isCritical : false;
  }

  Future<void> _addCustomRole(BuildContext context) async {
    final name = await _promptRoleName(context);
    if (name == null || name.isEmpty) return;
    final uuid = const Uuid();
    final now = DateTime.now();
    await db.stakeholderRoleDao.upsert(StakeholderRolesCompanion.insert(
      id: uuid.v4(),
      projectId: projectId,
      roleName: name,
      roleType: tierType,
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
        title: const Text('Add Stakeholder Role',
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
// Individual role row
// ---------------------------------------------------------------------------

class _StakeholderRoleRow extends StatelessWidget {
  final StakeholderRole role;
  final AppDatabase db;
  final String projectId;
  final List<Person> persons;
  final String hint;
  final bool isCritical;

  const _StakeholderRoleRow({
    required this.role,
    required this.db,
    required this.projectId,
    required this.persons,
    required this.hint,
    required this.isCritical,
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
          // Indicator dot
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
                if (isCritical && !_filled) ...[
                  const SizedBox(height: 4),
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 11, color: KColors.amber),
                      SizedBox(width: 4),
                      Text(
                        'Required — every programme needs one',
                        style:
                            TextStyle(color: KColors.amber, fontSize: 10),
                      ),
                    ],
                  ),
                ],
                // Engagement + gap indicators
                if (role.engagementStatus != null ||
                    role.priority != null ||
                    role.gapFlag) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (role.priority != null)
                        _PriorityBadge(role.priority!),
                      _engagementChip(role.engagementStatus),
                      if (role.gapFlag)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: KColors.redDim,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('⚠ GAP',
                              style: TextStyle(
                                  color: KColors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ],
                if (role.gapFlag && role.gapDescription != null) ...[
                  const SizedBox(height: 4),
                  Text(role.gapDescription!,
                      style: const TextStyle(
                          color: KColors.red, fontSize: 10)),
                ],
                if (role.functionalArea != null) ...[
                  const SizedBox(height: 3),
                  Text(role.functionalArea!,
                      style: const TextStyle(
                          color: KColors.textMuted,
                          fontSize: 10,
                          fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Actions
          if (!_filled)
            RoleSmallButton(
              label: 'Assign',
              onTap: () => _assign(context),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoleSmallButton(
                  label: 'Change',
                  onTap: () => _assign(context),
                ),
                const SizedBox(width: 6),
                RoleMoreMenu(
                  onMarkNA: () => _markNA(),
                  onRemove: () => _removePerson(),
                  onEditDetails: () => _editDetails(context),
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
      await db.stakeholderRoleDao.updateRole(StakeholderRolesCompanion(
        id: Value(role.id),
        personId: Value(person.id),
        updatedAt: Value(DateTime.now()),
      ));
    }
  }

  Future<void> _markNA() async {
    await db.stakeholderRoleDao.updateRole(StakeholderRolesCompanion(
      id: Value(role.id),
      isApplicable: const Value(false),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _removePerson() async {
    await db.stakeholderRoleDao.updateRole(StakeholderRolesCompanion(
      id: Value(role.id),
      personId: const Value(null),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _editDetails(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _StakeholderDetailsDialog(role: role, db: db),
    );
  }
}

// ---------------------------------------------------------------------------
// Priority badge
// ---------------------------------------------------------------------------

class _PriorityBadge extends StatelessWidget {
  final String priority;
  const _PriorityBadge(this.priority);

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (priority) {
      'critical' => ('● Critical', KColors.red,      KColors.redDim),
      'high'     => ('▲ High',     KColors.amber,    KColors.amberDim),
      'medium'   => ('◆ Medium',   KColors.phosphor, KColors.phosDim),
      _          => ('○ Low',      KColors.textMuted, Colors.transparent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
        border: bg == Colors.transparent
            ? Border.all(color: KColors.border2)
            : null,
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

// ---------------------------------------------------------------------------
// Stakeholder details dialog
// ---------------------------------------------------------------------------

class _StakeholderDetailsDialog extends StatefulWidget {
  final StakeholderRole role;
  final AppDatabase db;

  const _StakeholderDetailsDialog({required this.role, required this.db});

  @override
  State<_StakeholderDetailsDialog> createState() =>
      _StakeholderDetailsDialogState();
}

class _StakeholderDetailsDialogState
    extends State<_StakeholderDetailsDialog> {
  late final TextEditingController _areaCtrl;
  late final TextEditingController _relevanceCtrl;
  late final TextEditingController _gapDescCtrl;
  String? _priority;
  String? _engagementStatus;
  late bool _gapFlag;

  @override
  void initState() {
    super.initState();
    final r = widget.role;
    _areaCtrl       = TextEditingController(text: r.functionalArea ?? '');
    _relevanceCtrl  = TextEditingController(text: r.integrationRelevance ?? '');
    _gapDescCtrl    = TextEditingController(text: r.gapDescription ?? '');
    _priority        = r.priority;
    _engagementStatus = r.engagementStatus;
    _gapFlag         = r.gapFlag;
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _relevanceCtrl.dispose();
    _gapDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.db.stakeholderRoleDao.updateRole(StakeholderRolesCompanion(
      id: Value(widget.role.id),
      functionalArea:       Value(_areaCtrl.text.trim().isEmpty
          ? null : _areaCtrl.text.trim()),
      integrationRelevance: Value(_relevanceCtrl.text.trim().isEmpty
          ? null : _relevanceCtrl.text.trim()),
      priority:             Value(_priority),
      engagementStatus:     Value(_engagementStatus),
      gapFlag:              Value(_gapFlag),
      gapDescription:       Value(_gapDescCtrl.text.trim().isEmpty
          ? null : _gapDescCtrl.text.trim()),
      updatedAt:            Value(DateTime.now()),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stakeholder Details — ${widget.role.roleName}',
                  style: const TextStyle(
                      color: KColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),

              // Functional area
              TextField(
                controller: _areaCtrl,
                style: const TextStyle(color: KColors.text, fontSize: 13),
                decoration: const InputDecoration(
                    labelText: 'Functional area',
                    hintText: 'e.g. Technology and Integration'),
              ),
              const SizedBox(height: 12),

              // Priority dropdown
              DropdownButtonFormField<String>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                dropdownColor: KColors.surface2,
                items: [
                  const DropdownMenuItem(value: null, child: Text('— None')),
                  for (final (v, l) in _kPriorityOptions)
                    DropdownMenuItem(value: v, child: Text(l)),
                ],
                onChanged: (v) => setState(() => _priority = v),
              ),
              const SizedBox(height: 12),

              // Engagement status
              DropdownButtonFormField<String>(
                value: _engagementStatus,
                decoration:
                    const InputDecoration(labelText: 'Engagement status'),
                dropdownColor: KColors.surface2,
                items: [
                  const DropdownMenuItem(value: null, child: Text('— None')),
                  for (final (v, l) in _kEngagementOptions)
                    DropdownMenuItem(value: v, child: Text(l)),
                ],
                onChanged: (v) => setState(() => _engagementStatus = v),
              ),
              const SizedBox(height: 12),

              // Integration relevance
              TextField(
                controller: _relevanceCtrl,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(color: KColors.text, fontSize: 13),
                decoration: const InputDecoration(
                    labelText: 'Integration relevance',
                    hintText: 'Describe why this stakeholder matters'),
              ),
              const SizedBox(height: 12),

              // Gap flag + description
              Row(children: [
                Checkbox(
                  value: _gapFlag,
                  onChanged: (v) => setState(() => _gapFlag = v ?? false),
                ),
                const Text('Gap — action required',
                    style: TextStyle(color: KColors.text, fontSize: 13)),
              ]),
              if (_gapFlag) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _gapDescCtrl,
                  minLines: 2,
                  maxLines: 3,
                  style: const TextStyle(color: KColors.text, fontSize: 13),
                  decoration: const InputDecoration(
                      labelText: 'Gap description'),
                ),
              ],
              const SizedBox(height: 20),

              // Buttons
              Row(children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel',
                      style:
                          TextStyle(color: KColors.textDim, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
