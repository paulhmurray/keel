import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../providers/project_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/source_badge.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/utils/date_utils.dart' as du;

class ActionsView extends StatelessWidget {
  const ActionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final projectId = context.watch<ProjectProvider>().currentProjectId;
    if (projectId == null) {
      return const Center(child: Text('Select a project to view actions.',
          style: TextStyle(color: KColors.textDim)));
    }

    final db = context.read<AppDatabase>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: KColors.amber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text('ACTIONS',
                    style: Theme.of(context).textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) =>
                      _ActionFormDialog(projectId: projectId, db: db),
                ),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Action'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<ProjectAction>>(
              stream: db.actionsDao.watchActionsForProject(projectId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline,
                            size: 40, color: KColors.textMuted),
                        const SizedBox(height: 12),
                        const Text('No actions yet.',
                            style: TextStyle(color: KColors.textDim)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) =>
                                _ActionFormDialog(projectId: projectId, db: db),
                          ),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Action'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _ActionCard(
                      action: items[i], db: db, projectId: projectId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Color _actionBarColor(ProjectAction action) {
  if (action.status == 'closed') return KColors.phosphor;
  final isOverdue = action.dueDate != null &&
      action.status != 'closed' &&
      action.dueDate!.compareTo(
              DateTime.now().toIso8601String().substring(0, 10)) <
          0;
  if (isOverdue) return KColors.red;
  return KColors.amber;
}

class _ActionCard extends StatelessWidget {
  final ProjectAction action;
  final AppDatabase db;
  final String projectId;

  const _ActionCard(
      {required this.action, required this.db, required this.projectId});

  bool get _isOverdue {
    if (action.dueDate == null || action.status == 'closed') return false;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return action.dueDate!.compareTo(today) < 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KColors.surface,
        border: Border.all(color: KColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: () => showDialog(
          context: context,
          builder: (_) => _ActionFormDialog(
              projectId: projectId, db: db, action: action,
              startInViewMode: true),
        ),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 2,
                height: 48,
                color: _actionBarColor(action),
                margin: const EdgeInsets.only(right: 12),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (action.ref != null) ...[
                          Text(action.ref!,
                              style: const TextStyle(
                                  color: KColors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(action.description,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                  color: KColors.text)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        StatusChip(status: action.status),
                        const SizedBox(width: 8),
                        if (action.owner != null &&
                            action.owner!.isNotEmpty) ...[
                          const Icon(Icons.person_outline,
                              size: 11, color: KColors.textDim),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(action.owner!,
                                style: const TextStyle(
                                    color: KColors.textDim, fontSize: 11),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (action.dueDate != null) ...[
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 11,
                            color: _isOverdue ? KColors.red : KColors.textDim,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            du.formatDate(action.dueDate),
                            style: TextStyle(
                              color: _isOverdue ? KColors.red : KColors.textDim,
                              fontSize: 11,
                              fontWeight: _isOverdue
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        SourceBadge(source: action.source),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 16, color: KColors.textMuted),
                onSelected: (val) {
                  if (val == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) => _ActionFormDialog(
                          projectId: projectId, db: db, action: action),
                    );
                  } else if (val == 'close') {
                    db.actionsDao.upsertAction(
                      ProjectActionsCompanion(
                        id: Value(action.id),
                        projectId: Value(action.projectId),
                        description: Value(action.description),
                        status: const Value('closed'),
                        updatedAt: Value(DateTime.now()),
                      ),
                    );
                  } else if (val == 'delete') {
                    db.actionsDao.deleteAction(action.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'close', child: Text('Mark Closed')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ProjectAction? action;
  final bool startInViewMode;

  const _ActionFormDialog({
    required this.projectId,
    required this.db,
    this.action,
    this.startInViewMode = false,
  });

  @override
  State<_ActionFormDialog> createState() => _ActionFormDialogState();
}

class _ActionFormDialogState extends State<_ActionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descCtrl;
  late TextEditingController _ownerCtrl;
  String? _dueDate;
  late TextEditingController _sourceNoteCtrl;

  String _status = 'open';
  String _priority = 'medium';
  String _source = 'manual';

  late bool _isViewing;

  List<Person> _persons = [];

  final _statuses = ['open', 'in progress', 'closed', 'blocked'];
  final _priorities = ['low', 'medium', 'high', 'critical'];
  final _sources = ['manual', 'inbox', 'document', 'observation', 'meeting'];

  @override
  void initState() {
    super.initState();
    final a = widget.action;
    _descCtrl = TextEditingController(text: a?.description ?? '');
    _ownerCtrl = TextEditingController(text: a?.owner ?? '');
    _dueDate = a?.dueDate;
    _sourceNoteCtrl = TextEditingController(text: a?.sourceNote ?? '');
    _status = a?.status ?? 'open';
    _priority = a?.priority ?? 'medium';
    _source = a?.source ?? 'manual';
    _isViewing = widget.startInViewMode && a != null;
    _loadPersons();
  }

  Future<void> _loadPersons() async {
    final persons =
        await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    if (mounted) setState(() => _persons = persons);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _ownerCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final existing = await widget.db.actionsDao.getActionsForProject(widget.projectId);
    final nums = existing
        .where((a) => a.ref != null && a.ref!.startsWith('AC'))
        .map((a) => int.tryParse(a.ref!.substring(2)) ?? 0)
        .toList()
      ..sort();
    final String ref = widget.action?.ref ??
        'AC${(nums.isEmpty ? 0 : nums.last) + 1}';

    final id = widget.action?.id ?? const Uuid().v4();
    await widget.db.actionsDao.upsertAction(
      ProjectActionsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(ref),
        description: Value(_descCtrl.text.trim()),
        owner: Value(
            _ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
        dueDate: Value(_dueDate),
        status: Value(_status),
        priority: Value(_priority),
        source: Value(_source),
        sourceNote: Value(_sourceNoteCtrl.text.trim().isEmpty
            ? null
            : _sourceNoteCtrl.text.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (mounted) Navigator.of(context).pop();
  }

  Widget _readView() {
    final a = widget.action!;
    final isOverdue = a.dueDate != null &&
        a.status != 'closed' &&
        a.dueDate!.compareTo(DateTime.now().toIso8601String().substring(0, 10)) < 0;
    return AlertDialog(
      title: Row(
        children: [
          if (a.ref != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: KColors.amberDim,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(a.ref!,
                  style: const TextStyle(
                      color: KColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
          ],
          const Text('Action'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _viewField('Description', a.description, large: true),
            Row(
              children: [
                Expanded(child: _viewField('Status', a.status)),
                Expanded(child: _viewField('Priority', a.priority)),
              ],
            ),
            Row(
              children: [
                if (a.owner != null && a.owner!.isNotEmpty)
                  Expanded(child: _viewField('Owner', a.owner)),
                if (a.dueDate != null)
                  Expanded(
                    child: _viewField(
                      'Due Date',
                      du.formatDate(a.dueDate),
                      valueColor: isOverdue ? KColors.red : null,
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(child: _viewField('Source', a.source)),
                if (a.sourceNote != null && a.sourceNote!.isNotEmpty)
                  Expanded(child: _viewField('Source Note', a.sourceNote)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: () => setState(() => _isViewing = false),
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Edit'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isViewing) return _readView();

    final isEdit = widget.action != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Action' : 'New Action'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _descCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Description *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownField(
                      label: 'Status',
                      value: _status,
                      items: _statuses,
                      onChanged: (v) => setState(() => _status = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownField(
                      label: 'Priority',
                      value: _priority,
                      items: _priorities,
                      onChanged: (v) => setState(() => _priority = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _ownerCtrl.text.isEmpty
                          ? null
                          : _ownerCtrl.text,
                      decoration:
                          const InputDecoration(labelText: 'Owner'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— none —')),
                        ..._persons.map((p) => DropdownMenuItem(
                              value: p.name,
                              child: Text(p.name),
                            )),
                      ],
                      onChanged: (v) =>
                          setState(() => _ownerCtrl.text = v ?? ''),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DatePickerField(
                      label: 'Due Date',
                      isoValue: _dueDate,
                      onChanged: (v) => setState(() => _dueDate = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownField(
                      label: 'Source',
                      value: _source,
                      items: _sources,
                      onChanged: (v) => setState(() => _source = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sourceNoteCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Source Note'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.startInViewMode)
          TextButton(
            onPressed: () => setState(() => _isViewing = true),
            child: const Text('Cancel'),
          )
        else
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

Widget _viewField(String label, String? value,
    {bool large = false, Color? valueColor}) {
  if (value == null || value.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: KColors.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? KColors.text,
            fontSize: large ? 14 : 12,
            height: 1.55,
          ),
        ),
      ],
    ),
  );
}
