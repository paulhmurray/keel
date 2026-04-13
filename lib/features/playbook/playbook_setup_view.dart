import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';

class PlaybookSetupView extends StatefulWidget {
  final AppDatabase db;
  final String? initialOrgId;

  const PlaybookSetupView({
    super.key,
    required this.db,
    this.initialOrgId,
  });

  @override
  State<PlaybookSetupView> createState() => _PlaybookSetupViewState();
}

class _PlaybookSetupViewState extends State<PlaybookSetupView> {
  String? _selectedOrgId;
  String? _selectedPlaybookId;

  @override
  void initState() {
    super.initState();
    _selectedOrgId = widget.initialOrgId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KColors.bg,
      appBar: AppBar(
        backgroundColor: KColors.surface,
        foregroundColor: KColors.text,
        title: const Row(
          children: [
            Icon(Icons.account_tree_outlined, color: KColors.amber, size: 18),
            SizedBox(width: 8),
            Text(
              'PLAYBOOK SETUP',
              style: TextStyle(
                color: KColors.amber,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: KColors.border),
        ),
      ),
      body: Row(
        children: [
          // Left: org list
          Container(
            width: 220,
            decoration: const BoxDecoration(
              color: KColors.surface,
              border: Border(right: BorderSide(color: KColors.border)),
            ),
            child: _OrgList(
              db: widget.db,
              selectedId: _selectedOrgId,
              onSelect: (id) => setState(() {
                _selectedOrgId = id;
                _selectedPlaybookId = null;
              }),
            ),
          ),
          // Middle: playbook list for org
          if (_selectedOrgId != null)
            Container(
              width: 240,
              decoration: const BoxDecoration(
                color: KColors.surface,
                border: Border(right: BorderSide(color: KColors.border)),
              ),
              child: _PlaybookList(
                db: widget.db,
                orgId: _selectedOrgId!,
                selectedId: _selectedPlaybookId,
                onSelect: (id) => setState(() => _selectedPlaybookId = id),
              ),
            ),
          // Right: stage editor
          if (_selectedPlaybookId != null)
            Expanded(
              child: _StageEditor(
                db: widget.db,
                playbookId: _selectedPlaybookId!,
              ),
            )
          else
            Expanded(
              child: Center(
                child: Text(
                  _selectedOrgId == null
                      ? 'Select or create an organisation'
                      : 'Select or create a playbook',
                  style: const TextStyle(color: KColors.textDim, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Organisation list
// ---------------------------------------------------------------------------

class _OrgList extends StatelessWidget {
  final AppDatabase db;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _OrgList({
    required this.db,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Organisation>>(
      stream: db.playbookDao.watchAllOrganisations(),
      builder: (context, snap) {
        final orgs = snap.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ListHeader(
              label: 'ORGANISATIONS',
              onAdd: () => _showOrgDialog(context, null),
            ),
            Expanded(
              child: orgs.isEmpty
                  ? const Center(
                      child: Text(
                        'No organisations yet',
                        style: TextStyle(color: KColors.textMuted, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      itemCount: orgs.length,
                      itemBuilder: (_, i) {
                        final org = orgs[i];
                        final selected = org.id == selectedId;
                        return _SidebarItem(
                          label: org.name,
                          sublabel: org.shortName,
                          selected: selected,
                          onTap: () => onSelect(org.id),
                          onEdit: () => _showOrgDialog(context, org),
                          onDelete: () => _confirmDeleteOrg(context, org),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showOrgDialog(BuildContext context, Organisation? existing) {
    showDialog(
      context: context,
      builder: (_) => _OrgDialog(db: db, existing: existing),
    );
  }

  void _confirmDeleteOrg(BuildContext context, Organisation org) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete organisation?'),
        content: Text('Delete "${org.name}"? This will also delete all its playbooks and stages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await db.playbookDao.deleteOrganisation(org.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playbook list
// ---------------------------------------------------------------------------

class _PlaybookList extends StatelessWidget {
  final AppDatabase db;
  final String orgId;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _PlaybookList({
    required this.db,
    required this.orgId,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Playbook>>(
      stream: db.playbookDao.watchPlaybooksForOrg(orgId),
      builder: (context, snap) {
        final books = snap.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ListHeader(
              label: 'PLAYBOOKS',
              onAdd: () => _showPlaybookDialog(context, null),
            ),
            Expanded(
              child: books.isEmpty
                  ? const Center(
                      child: Text(
                        'No playbooks yet',
                        style: TextStyle(color: KColors.textMuted, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      itemCount: books.length,
                      itemBuilder: (_, i) {
                        final pb = books[i];
                        final selected = pb.id == selectedId;
                        return _SidebarItem(
                          label: pb.name,
                          sublabel: pb.version,
                          selected: selected,
                          onTap: () => onSelect(pb.id),
                          onEdit: () => _showPlaybookDialog(context, pb),
                          onDelete: () => _confirmDelete(context, pb),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showPlaybookDialog(BuildContext context, Playbook? existing) {
    showDialog(
      context: context,
      builder: (_) => _PlaybookDialog(db: db, orgId: orgId, existing: existing),
    );
  }

  void _confirmDelete(BuildContext context, Playbook pb) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete playbook?'),
        content: Text('Delete "${pb.name}"? Stages will also be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await db.playbookDao.deletePlaybook(pb.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stage editor
// ---------------------------------------------------------------------------

class _StageEditor extends StatelessWidget {
  final AppDatabase db;
  final String playbookId;

  const _StageEditor({required this.db, required this.playbookId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PlaybookStage>>(
      stream: db.playbookDao.watchStagesForPlaybook(playbookId),
      builder: (context, snap) {
        final stages = snap.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: KColors.border)),
              ),
              child: Row(
                children: [
                  const Text(
                    'STAGES',
                    style: TextStyle(
                      color: KColors.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.15,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${stages.length} stages',
                    style: const TextStyle(color: KColors.textMuted, fontSize: 10),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showStageDialog(context, null, stages.length),
                    icon: const Icon(Icons.add, size: 13),
                    label: const Text('Add Stage'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: stages.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_tree_outlined,
                              size: 32, color: KColors.textMuted),
                          SizedBox(height: 10),
                          Text(
                            'No stages yet. Add the first stage.',
                            style: TextStyle(color: KColors.textDim, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: stages.length,
                      onReorder: (oldIndex, newIndex) async {
                        if (newIndex > oldIndex) newIndex--;
                        final reordered = List.of(stages);
                        final moved = reordered.removeAt(oldIndex);
                        reordered.insert(newIndex, moved);
                        await db.playbookDao
                            .reorderStages(reordered.map((s) => s.id).toList());
                      },
                      itemBuilder: (_, i) {
                        final stage = stages[i];
                        return _StageCard(
                          key: ValueKey(stage.id),
                          stage: stage,
                          index: i,
                          db: db,
                          onEdit: () => _showStageDialog(context, stage, stages.length),
                          onDelete: () => _confirmDeleteStage(context, stage),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showStageDialog(BuildContext context, PlaybookStage? existing, int count) {
    showDialog(
      context: context,
      builder: (_) => _StageDialog(
        db: db,
        playbookId: playbookId,
        existing: existing,
        nextSortOrder: count,
      ),
    );
  }

  void _confirmDeleteStage(BuildContext context, PlaybookStage stage) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete stage?'),
        content: Text('Delete "${stage.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KColors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await db.playbookDao.deleteStage(stage.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  final PlaybookStage stage;
  final int index;
  final AppDatabase db;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StageCard({
    super.key,
    required this.stage,
    required this.index,
    required this.db,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: KColors.amberDim,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: KColors.amber,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        title: Text(
          stage.name,
          style: const TextStyle(color: KColors.text, fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: stage.approverRole != null || stage.gateCondition != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stage.approverRole != null)
                    Text('Approver: ${stage.approverRole}',
                        style: const TextStyle(color: KColors.textDim, fontSize: 11)),
                  if (stage.gateCondition != null)
                    Text('Gate: ${stage.gateCondition}',
                        style: const TextStyle(color: KColors.textDim, fontSize: 11)),
                ],
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.drag_indicator, size: 16, color: KColors.textMuted),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 15, color: KColors.textDim),
              onPressed: onEdit,
              tooltip: 'Edit stage',
              splashRadius: 16,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 15, color: KColors.textMuted),
              onPressed: onDelete,
              tooltip: 'Delete stage',
              splashRadius: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

class _OrgDialog extends StatefulWidget {
  final AppDatabase db;
  final Organisation? existing;

  const _OrgDialog({required this.db, this.existing});

  @override
  State<_OrgDialog> createState() => _OrgDialogState();
}

class _OrgDialogState extends State<_OrgDialog> {
  late final TextEditingController _name;
  late final TextEditingController _short;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _short = TextEditingController(text: widget.existing?.shortName ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Organisation' : 'New Organisation'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _short,
              decoration: const InputDecoration(labelText: 'Short name / acronym'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    await widget.db.playbookDao.upsertOrganisation(OrganisationsCompanion(
      id: Value(widget.existing?.id ?? const Uuid().v4()),
      name: Value(name),
      shortName: Value(_short.text.trim().isEmpty ? null : _short.text.trim()),
      notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
      createdAt: Value(widget.existing?.createdAt ?? now),
      updatedAt: Value(now),
    ));
    if (mounted) Navigator.pop(context);
  }
}

class _PlaybookDialog extends StatefulWidget {
  final AppDatabase db;
  final String orgId;
  final Playbook? existing;

  const _PlaybookDialog({required this.db, required this.orgId, this.existing});

  @override
  State<_PlaybookDialog> createState() => _PlaybookDialogState();
}

class _PlaybookDialogState extends State<_PlaybookDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _version;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _desc = TextEditingController(text: widget.existing?.description ?? '');
    _version = TextEditingController(text: widget.existing?.version ?? 'v1.0');
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _version.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Playbook' : 'New Playbook'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Playbook name *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _version,
              decoration: const InputDecoration(labelText: 'Version'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    await widget.db.playbookDao.upsertPlaybook(PlaybooksCompanion(
      id: Value(widget.existing?.id ?? const Uuid().v4()),
      organisationId: Value(widget.orgId),
      name: Value(name),
      description: Value(_desc.text.trim().isEmpty ? null : _desc.text.trim()),
      version: Value(_version.text.trim().isEmpty ? null : _version.text.trim()),
      createdAt: Value(widget.existing?.createdAt ?? now),
      updatedAt: Value(now),
    ));
    if (mounted) Navigator.pop(context);
  }
}

class _StageDialog extends StatefulWidget {
  final AppDatabase db;
  final String playbookId;
  final PlaybookStage? existing;
  final int nextSortOrder;

  const _StageDialog({
    required this.db,
    required this.playbookId,
    this.existing,
    required this.nextSortOrder,
  });

  @override
  State<_StageDialog> createState() => _StageDialogState();
}

class _StageDialogState extends State<_StageDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _approver;
  late final TextEditingController _gate;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _desc = TextEditingController(text: widget.existing?.description ?? '');
    _approver = TextEditingController(text: widget.existing?.approverRole ?? '');
    _gate = TextEditingController(text: widget.existing?.gateCondition ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _approver.dispose();
    _gate.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Stage' : 'New Stage'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Stage name *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _desc,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'What this stage is and why it exists',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _approver,
                decoration: const InputDecoration(
                  labelText: 'Approver role',
                  hintText: 'e.g. Head of Strategy',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _gate,
                decoration: const InputDecoration(
                  labelText: 'Gate condition',
                  hintText: 'e.g. Lean Canvas approved by sponsor',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Institutional knowledge, tips, gotchas',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Add Stage'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    await widget.db.playbookDao.upsertStage(PlaybookStagesCompanion(
      id: Value(widget.existing?.id ?? const Uuid().v4()),
      playbookId: Value(widget.playbookId),
      name: Value(name),
      description: Value(_desc.text.trim().isEmpty ? null : _desc.text.trim()),
      sortOrder: Value(widget.existing?.sortOrder ?? widget.nextSortOrder),
      approverRole: Value(_approver.text.trim().isEmpty ? null : _approver.text.trim()),
      gateCondition: Value(_gate.text.trim().isEmpty ? null : _gate.text.trim()),
      notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
      createdAt: Value(widget.existing?.createdAt ?? now),
      updatedAt: Value(now),
    ));
    if (mounted) Navigator.pop(context);
  }
}

// ---------------------------------------------------------------------------
// Shared sidebar widgets
// ---------------------------------------------------------------------------

class _ListHeader extends StatelessWidget {
  final String label;
  final VoidCallback onAdd;

  const _ListHeader({required this.label, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: KColors.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            child: const Icon(Icons.add, size: 16, color: KColors.amber),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SidebarItem({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? KColors.amberDim : Colors.transparent,
        border: const Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? KColors.amber : KColors.text,
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (sublabel != null && sublabel!.isNotEmpty)
                      Text(
                        sublabel!,
                        style: const TextStyle(color: KColors.textDim, fontSize: 10),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 14, color: KColors.textMuted),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
