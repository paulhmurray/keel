import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../timeline/timeline_chart.dart' show parseHexColor;

// ---------------------------------------------------------------------------
// Color helper
// ---------------------------------------------------------------------------

const _kCustomColors = [
  '#EF4444', '#F97316', '#EAB308', '#22C55E',
  '#14B8A6', '#3B82F6', '#6366F1', '#8B5CF6',
  '#EC4899', '#6B7280', '#F59E0B', '#10B981',
];

// ---------------------------------------------------------------------------
// Action form dialog
// ---------------------------------------------------------------------------

class ActionFormDialog extends StatefulWidget {
  final String projectId;
  final AppDatabase db;
  final ProjectAction? action;
  final bool startInViewMode;

  const ActionFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.action,
    this.startInViewMode = false,
  });

  @override
  State<ActionFormDialog> createState() => _ActionFormDialogState();
}

class _ActionFormDialogState extends State<ActionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descCtrl;
  late TextEditingController _ownerCtrl;
  String? _dueDate;
  late TextEditingController _sourceNoteCtrl;

  String _status = 'open';
  String _priority = 'medium';
  String _source = 'manual';

  // Category & recurrence & link
  String? _categoryId;
  String _recurrence = 'none';
  String? _recurrenceEndDate;
  String? _linkedActionId;

  late bool _isViewing;

  List<Person> _persons = [];
  List<ActionCategory> _categories = [];
  List<ProjectAction> _allActions = [];

  final _statuses = ['open', 'in progress', 'closed', 'blocked'];
  final _priorities = ['low', 'medium', 'high', 'critical'];
  final _sources = ['manual', 'inbox', 'document', 'observation', 'meeting'];
  final _recurrences = ['none', 'weekly', 'fortnightly', 'monthly', 'quarterly'];

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
    _categoryId = a?.categoryId;
    _linkedActionId = a?.linkedActionId;
    _isViewing = widget.startInViewMode && a != null;
    _loadData();
  }

  Future<void> _loadData() async {
    await widget.db.actionCategoriesDao.seedPresetsIfEmpty(widget.projectId);
    final cats = await widget.db.actionCategoriesDao.getForProject(widget.projectId);
    final persons = await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    final actions = await widget.db.actionsDao.getActionsForProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _persons = persons;
      _allActions = actions.where((a) => a.id != widget.action?.id).toList();
    });
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _ownerCtrl.dispose();
    _sourceNoteCtrl.dispose();
    super.dispose();
  }

  List<String> _generateDates(String startIso, String type, String endIso) {
    final start = DateTime.parse(startIso);
    final end = DateTime.parse(endIso);
    final dates = <String>[];
    DateTime cursor = start;
    while (!cursor.isAfter(end)) {
      dates.add(cursor.toIso8601String().substring(0, 10));
      cursor = switch (type) {
        'weekly'      => cursor.add(const Duration(days: 7)),
        'fortnightly' => cursor.add(const Duration(days: 14)),
        'monthly'     => DateTime(cursor.year, cursor.month + 1, cursor.day),
        'quarterly'   => DateTime(cursor.year, cursor.month + 3, cursor.day),
        _             => end.add(const Duration(days: 1)),
      };
    }
    return dates;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final existing = await widget.db.actionsDao.getActionsForProject(widget.projectId);
    final nums = existing
        .where((a) => a.ref != null && a.ref!.startsWith('AC'))
        .map((a) => int.tryParse(a.ref!.substring(2)) ?? 0)
        .toList()
      ..sort();
    final String baseRef = widget.action?.ref ??
        'AC${(nums.isEmpty ? 0 : nums.last) + 1}';

    final isEdit = widget.action != null;

    if (!isEdit &&
        _recurrence != 'none' &&
        _dueDate != null &&
        _recurrenceEndDate != null) {
      // Generate recurring occurrences
      final groupId = const Uuid().v4();
      final dates = _generateDates(_dueDate!, _recurrence, _recurrenceEndDate!);
      for (final date in dates) {
        await widget.db.actionsDao.upsertAction(ProjectActionsCompanion(
          id: Value(const Uuid().v4()),
          projectId: Value(widget.projectId),
          ref: Value(baseRef),
          description: Value(_descCtrl.text.trim()),
          owner: Value(_ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
          dueDate: Value(date),
          status: Value(_status),
          priority: Value(_priority),
          source: Value(_source),
          sourceNote: Value(_sourceNoteCtrl.text.trim().isEmpty
              ? null
              : _sourceNoteCtrl.text.trim()),
          categoryId: Value(_categoryId),
          recurrenceGroupId: Value(groupId),
          linkedActionId: Value(_linkedActionId),
          updatedAt: Value(DateTime.now()),
        ));
      }
    } else {
      final id = widget.action?.id ?? const Uuid().v4();
      await widget.db.actionsDao.upsertAction(ProjectActionsCompanion(
        id: Value(id),
        projectId: Value(widget.projectId),
        ref: Value(baseRef),
        description: Value(_descCtrl.text.trim()),
        owner: Value(_ownerCtrl.text.trim().isEmpty ? null : _ownerCtrl.text.trim()),
        dueDate: Value(_dueDate),
        status: Value(_status),
        priority: Value(_priority),
        source: Value(_source),
        sourceNote: Value(_sourceNoteCtrl.text.trim().isEmpty
            ? null
            : _sourceNoteCtrl.text.trim()),
        categoryId: Value(_categoryId),
        linkedActionId: Value(_linkedActionId),
        updatedAt: Value(DateTime.now()),
      ));
    }

    if (mounted) Navigator.of(context).pop();
  }

  // ── Read/view mode ─────────────────────────────────────────────────────────

  Widget _readView() {
    final a = widget.action!;
    final isOverdue = a.dueDate != null &&
        a.status != 'closed' &&
        a.dueDate!.compareTo(DateTime.now().toIso8601String().substring(0, 10)) < 0;
    final cat = a.categoryId != null
        ? _categories.where((c) => c.id == a.categoryId).firstOrNull
        : null;

    return AlertDialog(
      title: Row(
        children: [
          if (cat != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: parseHexColor(cat.color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
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
          if (a.recurrenceGroupId != null) ...[
            const SizedBox(width: 8),
            const Tooltip(
              message: 'Recurring action',
              child: Icon(Icons.repeat, size: 14, color: KColors.textDim),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cat != null) _viewField('Category', cat.name),
              _viewField('Description', a.description, large: true),
              Row(children: [
                Expanded(child: _viewField('Status', a.status)),
                Expanded(child: _viewField('Priority', a.priority)),
              ]),
              Row(children: [
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
              ]),
              Row(children: [
                Expanded(child: _viewField('Source', a.source)),
                if (a.sourceNote != null && a.sourceNote!.isNotEmpty)
                  Expanded(child: _viewField('Source Note', a.sourceNote)),
              ]),
            ],
          ),
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

  // ── Edit/create mode ───────────────────────────────────────────────────────

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Category chips ─────────────────────────────────────
                if (_categories.isNotEmpty) ...[
                  const Text('CATEGORY',
                      style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ..._categories.map((cat) => _CategoryChip(
                            category: cat,
                            selected: _categoryId == cat.id,
                            onTap: () => setState(() =>
                                _categoryId =
                                    _categoryId == cat.id ? null : cat.id),
                          )),
                      _AddCategoryChip(
                          onTap: () => _showAddCategoryDialog()),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Description ────────────────────────────────────────
                TextFormField(
                  controller: _descCtrl,
                  autofocus: true,
                  decoration:
                      const InputDecoration(labelText: 'Description *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // ── Status + Priority ──────────────────────────────────
                Row(children: [
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
                ]),
                const SizedBox(height: 12),

                // ── Owner + Due Date ───────────────────────────────────
                Row(children: [
                  Expanded(
                    child: Builder(builder: (context) {
                      final myName = context.read<SettingsProvider>().settings.myName;
                      final currentOwner = _ownerCtrl.text.isEmpty ? null : _ownerCtrl.text;
                      // All known names (persons + current owner if free-text)
                      final personNames = _persons.map((p) => p.name).toSet();
                      return DropdownButtonFormField<String>(
                        value: currentOwner,
                        decoration: const InputDecoration(labelText: 'Owner'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('— none —')),
                          // "Me" shortcut at the top
                          if (myName.isNotEmpty)
                            DropdownMenuItem(
                              value: myName,
                              child: Row(
                                children: [
                                  const Icon(Icons.person,
                                      size: 13, color: KColors.phosphor),
                                  const SizedBox(width: 6),
                                  Text('Me — $myName',
                                      style: const TextStyle(
                                          color: KColors.phosphor,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          // Free-text owner not in persons list
                          if (currentOwner != null &&
                              !personNames.contains(currentOwner) &&
                              currentOwner != myName)
                            DropdownMenuItem(
                              value: currentOwner,
                              child: Text(currentOwner),
                            ),
                          ..._persons
                              .where((p) => p.name != myName)
                              .map((p) => DropdownMenuItem(
                                    value: p.name,
                                    child: Text(p.name),
                                  )),
                          // If myName isn't a person record, still show them
                          // once above; but if they ARE in _persons, deduplicate
                          if (myName.isNotEmpty && personNames.contains(myName))
                            ...[],
                        ],
                        onChanged: (v) =>
                            setState(() => _ownerCtrl.text = v ?? ''),
                      );
                    }),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DatePickerField(
                      label: 'Due Date',
                      isoValue: _dueDate,
                      onChanged: (v) => setState(() => _dueDate = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),

                // ── Recurrence (create only) ───────────────────────────
                if (!isEdit) ...[
                  const Divider(color: KColors.border, height: 1),
                  const SizedBox(height: 12),
                  const Text('RECURRENCE',
                      style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: DropdownField(
                        label: 'Repeats',
                        value: _recurrence,
                        items: _recurrences,
                        onChanged: (v) =>
                            setState(() => _recurrence = v!),
                      ),
                    ),
                    if (_recurrence != 'none') ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: DatePickerField(
                          label: 'Repeat until',
                          isoValue: _recurrenceEndDate,
                          onChanged: (v) =>
                              setState(() => _recurrenceEndDate = v),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 12),
                  const Divider(color: KColors.border, height: 1),
                  const SizedBox(height: 12),
                ],

                // ── Link to action ─────────────────────────────────────
                DropdownButtonFormField<String?>(
                  value: _linkedActionId,
                  decoration: const InputDecoration(
                      labelText: 'Linked to action (Gantt line)'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— none —')),
                    ..._allActions.map((a) => DropdownMenuItem<String?>(
                          value: a.id,
                          child: Text(
                            '${a.ref != null ? '${a.ref} ' : ''}${a.description}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (v) =>
                      setState(() => _linkedActionId = v),
                ),
                const SizedBox(height: 12),

                // ── Source ─────────────────────────────────────────────
                Row(children: [
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
                ]),
              ],
            ),
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

  void _showAddCategoryDialog() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _AddCategoryDialog(),
    );
    if (result == null || !mounted) return;
    await widget.db.actionCategoriesDao.upsert(ActionCategoriesCompanion(
      id: Value(const Uuid().v4()),
      projectId: Value(widget.projectId),
      name: Value(result.$1),
      color: Value(result.$2),
      isPreset: const Value(false),
      sortOrder: Value(_categories.length),
    ));
    await _loadData();
  }
}

// ---------------------------------------------------------------------------
// Category chip
// ---------------------------------------------------------------------------

class _CategoryChip extends StatelessWidget {
  final ActionCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(category.color);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(40) : KColors.surface2,
          border: Border.all(
              color: selected ? color : KColors.border2, width: 1.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: TextStyle(
                color: selected ? color : KColors.textDim,
                fontSize: 11,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add custom category chip
// ---------------------------------------------------------------------------

class _AddCategoryChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCategoryChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.border2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 12, color: KColors.textDim),
            SizedBox(width: 4),
            Text('Custom',
                style: TextStyle(color: KColors.textDim, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add custom category dialog
// ---------------------------------------------------------------------------

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog();

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _ctrl = TextEditingController();
  String _selectedColor = _kCustomColors.first;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Category'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 16),
            const Text('COLOUR',
                style: TextStyle(
                    color: KColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kCustomColors.map((hex) {
                final color = parseHexColor(hex);
                final sel = hex == _selectedColor;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedColor = hex),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: sel
                          ? [BoxShadow(color: color.withAlpha(120), blurRadius: 6)]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_ctrl.text.trim().isEmpty) return;
            Navigator.of(context).pop((_ctrl.text.trim(), _selectedColor));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// View field helper
// ---------------------------------------------------------------------------

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
