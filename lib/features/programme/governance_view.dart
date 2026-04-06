import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';

class GovernanceView extends StatelessWidget {
  const GovernanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project.'));
    }

    final db = context.read<AppDatabase>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Governance Cadences',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showForm(context, projectId, db, null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Meeting'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<GovernanceCadence>>(
              stream: db.programmeDao.watchGovernanceForProject(projectId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return const Center(
                    child: Text('No governance cadences yet.',
                        style: TextStyle(color: KColors.textDim)),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final g = items[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 18, color: KColors.amber),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(g.meetingName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (g.frequency != null)
                                        _InfoChip(
                                            icon: Icons.repeat,
                                            label: g.frequency!),
                                      if (g.chair != null) ...[
                                        const SizedBox(width: 8),
                                        _InfoChip(
                                            icon: Icons.person_outline,
                                            label: 'Chair: ${g.chair}'),
                                      ],
                                      if (g.myRole != null) ...[
                                        const SizedBox(width: 8),
                                        _InfoChip(
                                            icon: Icons.badge_outlined,
                                            label: 'My role: ${g.myRole}'),
                                      ],
                                    ],
                                  ),
                                  if (g.notes != null && g.notes!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(g.notes!,
                                        style: const TextStyle(
                                            color: KColors.textDim,
                                            fontSize: 12)),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () =>
                                  _showForm(context, projectId, db, g),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: KColors.red),
                              onPressed: () =>
                                  db.programmeDao.deleteGovernance(g.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showForm(BuildContext context, String projectId, AppDatabase db,
      GovernanceCadence? cadence) {
    showDialog(
      context: context,
      builder: (_) => _GovernanceFormDialog(
          projectId: projectId, db: db, cadence: cadence),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: KColors.textDim),
        const SizedBox(width: 3),
        Text(label,
            style:
                const TextStyle(color: KColors.textDim, fontSize: 12)),
      ],
    );
  }
}

class _GovernanceFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final GovernanceCadence? cadence;

  const _GovernanceFormDialog(
      {required this.projectId, required this.db, this.cadence});

  @override
  State<_GovernanceFormDialog> createState() => _GovernanceFormDialogState();
}

class _GovernanceFormDialogState extends State<_GovernanceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _frequencyCtrl;
  late TextEditingController _chairCtrl;
  late TextEditingController _roleCtrl;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final g = widget.cadence;
    _nameCtrl = TextEditingController(text: g?.meetingName ?? '');
    _frequencyCtrl = TextEditingController(text: g?.frequency ?? '');
    _chairCtrl = TextEditingController(text: g?.chair ?? '');
    _roleCtrl = TextEditingController(text: g?.myRole ?? '');
    _notesCtrl = TextEditingController(text: g?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _frequencyCtrl.dispose();
    _chairCtrl.dispose();
    _roleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final id = widget.cadence?.id ?? const Uuid().v4();
    await widget.db.programmeDao.upsertGovernance(
      GovernanceCadencesCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        meetingName: Value(_nameCtrl.text.trim()),
        frequency: Value(
            _frequencyCtrl.text.trim().isEmpty ? null : _frequencyCtrl.text.trim()),
        chair: Value(
            _chairCtrl.text.trim().isEmpty ? null : _chairCtrl.text.trim()),
        myRole: Value(
            _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim()),
        notes: Value(
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.cadence != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Meeting' : 'New Meeting Cadence'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Meeting Name *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _frequencyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Frequency (e.g. Weekly, Fortnightly)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _chairCtrl,
                      decoration: const InputDecoration(labelText: 'Chair'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _roleCtrl,
                      decoration: const InputDecoration(labelText: 'My Role'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
      ),
      actions: [
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
