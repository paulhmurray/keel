import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import 'package:provider/provider.dart';

import '../../core/database/database.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/person_picker_field.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../timeline/timeline_chart.dart' show parseHexColor;
import 'action_grouping.dart';

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
  /// Pre-link to a specific plan activity (e.g. when opened from the Plan view).
  final String? preLinkedActivityId;

  const ActionFormDialog({
    super.key,
    required this.projectId,
    required this.db,
    this.action,
    this.startInViewMode = false,
    this.preLinkedActivityId,
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
  String? _planActivityId;
  String? _parentActionId;

  late bool _isViewing;

  List<Person> _persons = [];
  List<ActionCategory> _categories = [];
  List<ProjectAction> _allActions = [];
  List<TimelineWorkPackage> _workPackages = [];
  List<TimelineActivity> _planActivities = [];

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
    _planActivityId = a?.planActivityId ?? widget.preLinkedActivityId;
    _parentActionId = a?.parentActionId;
    _isViewing = widget.startInViewMode && a != null;
    _loadData();
  }

  Future<void> _loadData() async {
    await widget.db.actionCategoriesDao.seedPresetsIfEmpty(widget.projectId);
    final cats = await widget.db.actionCategoriesDao.getForProject(widget.projectId);
    final persons = await widget.db.peopleDao.getPersonsForProject(widget.projectId);
    final actions = await widget.db.actionsDao.getActionsForProject(widget.projectId);
    final wps = await widget.db.programmeGanttDao.getWorkPackages(widget.projectId);
    final activities = await widget.db.programmeGanttDao.getActivitiesForProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _persons = persons;
      _allActions = actions.where((a) => a.id != widget.action?.id).toList();
      _workPackages = wps;
      _planActivities = activities;
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
          planActivityId: Value(_planActivityId),
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
        planActivityId: Value(_planActivityId),
        parentActionId: Value(_parentActionId),
        updatedAt: Value(DateTime.now()),
      ));
    }

    if (mounted) Navigator.of(context).pop();
  }

  String _planActivityLabel(String activityId) {
    final act = _planActivities.cast<TimelineActivity?>()
        .firstWhere((a) => a?.id == activityId, orElse: () => null);
    if (act == null) return activityId;
    final wp = _workPackages.cast<TimelineWorkPackage?>()
        .firstWhere((w) => w?.id == act.workPackageId, orElse: () => null);
    final prefix = wp != null ? '[${wp.shortCode ?? wp.name}] ' : '';
    return '$prefix${act.name}';
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
              if (a.planActivityId != null) _viewField(
                'Plan Activity',
                _planActivityLabel(a.planActivityId!),
              ),
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
              const SizedBox(height: 4),
              const Divider(color: KColors.border, height: 1),
              const SizedBox(height: 12),
              _CommentsThread(action: a, db: widget.db),
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
                          fontSize: 10,
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
                    child: PersonPickerField(
                      controller: _ownerCtrl,
                      label: 'Owner',
                      persons: _persons,
                      db: widget.db,
                      projectId: widget.projectId,
                      onPersonCreated: _loadData,
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
                ]),
                const SizedBox(height: 12),

                // ── Recurrence (create only) ───────────────────────────
                if (!isEdit) ...[
                  const Divider(color: KColors.border, height: 1),
                  const SizedBox(height: 12),
                  const Text('RECURRENCE',
                      style: TextStyle(
                          color: KColors.textMuted,
                          fontSize: 10,
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

                // ── Parent action (group) ──────────────────────────────
                _ParentActionPicker(
                  editing: widget.action,
                  allActions: _allActions,
                  value: _parentActionId,
                  onChanged: (v) => setState(() => _parentActionId = v),
                ),
                const SizedBox(height: 12),

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

                // ── Link to plan activity ──────────────────────────────
                if (_workPackages.isNotEmpty) ...[
                  _PlanActivityPicker(
                    value: _planActivityId,
                    workPackages: _workPackages,
                    activities: _planActivities,
                    onChanged: (v) => setState(() => _planActivityId = v),
                  ),
                  const SizedBox(height: 12),
                ],

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
                    fontSize: 10,
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
// Plan activity picker
// ---------------------------------------------------------------------------

class _PlanActivityPicker extends StatelessWidget {
  final String? value;
  final List<TimelineWorkPackage> workPackages;
  final List<TimelineActivity> activities;
  final ValueChanged<String?> onChanged;

  const _PlanActivityPicker({
    required this.value,
    required this.workPackages,
    required this.activities,
    required this.onChanged,
  });

  static const _kTypeIcons = {
    'milestone': '◆ ',
    'hard_deadline': '⚠ ',
    'gate': '◈ ',
  };

  @override
  Widget build(BuildContext context) {
    // Build grouped items: null option + one item per activity under its WP header
    final items = <DropdownMenuItem<String?>>[];
    items.add(const DropdownMenuItem<String?>(
        value: null,
        child: Text('— none —',
            style: TextStyle(color: KColors.textDim))));

    for (final wp in workPackages) {
      final wpActs = activities.where((a) => a.workPackageId == wp.id).toList();
      if (wpActs.isEmpty) continue;
      // Header (disabled item used as visual group label)
      items.add(DropdownMenuItem<String?>(
        enabled: false,
        value: '__header__${wp.id}',
        child: Text(
          '${wp.shortCode ?? wp.name}',
          style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5),
        ),
      ));
      for (final act in wpActs) {
        final prefix = _kTypeIcons[act.activityType] ?? '';
        items.add(DropdownMenuItem<String?>(
          value: act.id,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              '$prefix${act.name}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ));
      }
    }

    return DropdownButtonFormField<String?>(
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Plan Activity (optional)'),
      items: items,
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// Parent action picker (Epic-style grouping)
// ---------------------------------------------------------------------------

class _ParentActionPicker extends StatelessWidget {
  final ProjectAction? editing;
  final List<ProjectAction> allActions;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _ParentActionPicker({
    required this.editing,
    required this.allActions,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final candidates =
        eligibleParentCandidates(editing: editing, all: allActions);
    final hasChildren = editing != null &&
        allActions.any((a) => a.parentActionId == editing!.id);

    if (hasChildren) {
      final childCount =
          allActions.where((a) => a.parentActionId == editing!.id).length;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: KColors.border2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_tree_outlined,
                size: 13, color: KColors.phosphor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Group parent · $childCount child action${childCount == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: KColors.phosphor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const Text(
              "Can't be nested under another action",
              style: TextStyle(color: KColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String?>(
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Parent action (group under…)',
      ),
      items: [
        const DropdownMenuItem<String?>(
            value: null, child: Text('— none (top level) —')),
        ...candidates.map((a) => DropdownMenuItem<String?>(
              value: a.id,
              child: Text(
                '${a.ref != null ? '${a.ref} ' : ''}${a.description}',
                overflow: TextOverflow.ellipsis,
              ),
            )),
      ],
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// Comments thread (view mode)
// ---------------------------------------------------------------------------

class _CommentsThread extends StatefulWidget {
  final ProjectAction action;
  final AppDatabase db;

  const _CommentsThread({required this.action, required this.db});

  @override
  State<_CommentsThread> createState() => _CommentsThreadState();
}

class _CommentsThreadState extends State<_CommentsThread> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    final author = context.read<SettingsProvider>().settings.myName;
    final now = DateTime.now();
    await widget.db.actionCommentsDao.upsertComment(ActionCommentsCompanion(
      id: Value(const Uuid().v4()),
      actionId: Value(widget.action.id),
      content: Value(text),
      isCompletion: const Value(false),
      authorName: Value(author.isEmpty ? null : author),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    if (mounted) {
      _ctrl.clear();
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('COMMENTS',
            style: TextStyle(
                color: KColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1)),
        const SizedBox(height: 8),
        StreamBuilder<List<ActionComment>>(
          stream:
              widget.db.actionCommentsDao.watchForAction(widget.action.id),
          builder: (context, snap) {
            final comments = snap.data ?? const <ActionComment>[];
            final hasRealCompletion =
                comments.any((c) => c.isCompletion);
            // Legacy fallback: synthesise a completion-comment view when the
            // action has an outcome but no completion comment row yet.
            final synth = (!hasRealCompletion &&
                    widget.action.outcome != null &&
                    widget.action.outcome!.isNotEmpty)
                ? _SyntheticCompletion(
                    content: widget.action.outcome!,
                    when: widget.action.updatedAt,
                  )
                : null;
            if (comments.isEmpty && synth == null) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('No comments yet.',
                    style: TextStyle(
                        color: KColors.textMuted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (synth != null)
                  _CompletionTile(
                    content: synth.content,
                    author: null,
                    when: synth.when,
                    isSynthetic: true,
                  ),
                for (final c in comments)
                  c.isCompletion
                      ? _CompletionTile(
                          content: c.content,
                          author: c.authorName,
                          when: c.createdAt,
                          isSynthetic: false,
                        )
                      : _CommentTile(comment: c),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(color: KColors.text, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'Add a comment…',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onSubmitted: (_) => _addComment(),
              ),
            ),
            const SizedBox(width: 6),
            ElevatedButton(
              onPressed: _saving ? null : _addComment,
              child: const Text('Post'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SyntheticCompletion {
  final String content;
  final DateTime when;
  _SyntheticCompletion({required this.content, required this.when});
}

class _CompletionTile extends StatelessWidget {
  final String content;
  final String? author;
  final DateTime when;
  final bool isSynthetic;

  const _CompletionTile({
    required this.content,
    required this.author,
    required this.when,
    required this.isSynthetic,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: KColors.phosDim.withValues(alpha: 0.5),
        border: Border(
          left: BorderSide(
              color: KColors.phosphor.withValues(alpha: 0.7), width: 3),
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 12, color: KColors.phosphor),
              const SizedBox(width: 6),
              Text(
                'REASON COMPLETED${isSynthetic ? ' · legacy' : ''}',
                style: const TextStyle(
                    color: KColors.phosphor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5),
              ),
              const Spacer(),
              if (author != null && author!.isNotEmpty) ...[
                Text(author!,
                    style: const TextStyle(
                        color: KColors.textDim, fontSize: 10)),
                const SizedBox(width: 6),
              ],
              Text(du.formatDate(when.toIso8601String().substring(0, 10)),
                  style: const TextStyle(
                      color: KColors.textMuted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          Text(content,
              style: const TextStyle(
                  color: KColors.text, fontSize: 12, height: 1.45)),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final ActionComment comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: KColors.border2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (comment.authorName != null &&
                  comment.authorName!.isNotEmpty) ...[
                Text(comment.authorName!,
                    style: const TextStyle(
                        color: KColors.textDim,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              Text(
                du.formatDate(
                    comment.createdAt.toIso8601String().substring(0, 10)),
                style:
                    const TextStyle(color: KColors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(comment.content,
              style: const TextStyle(
                  color: KColors.text, fontSize: 12, height: 1.45)),
        ],
      ),
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
            fontSize: 10,
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
