import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import 'package:provider/provider.dart';

import '../../core/analytics/keel_events.dart';
import '../../core/cascade/cascade_factory.dart';
import '../../core/database/database.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/detail_dialog.dart';
import '../../shared/widgets/dropdown_field.dart';
import '../../shared/widgets/date_picker_field.dart';
import '../../shared/widgets/person_picker_field.dart';
import '../../shared/widgets/plan_activity_picker.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../timeline/timeline_chart.dart' show parseHexColor;
import 'action_grouping.dart';
import '../journal/journal_source_link.dart';

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

/// Action view/edit dialog, in the same wide two-column frame as the
/// plan's activity dialog. Left column: the action itself. Right column:
/// how it sits in the hierarchy, its sub-tasks (with quick-add) and the
/// comment thread — visible in edit mode too, so the PM can read the
/// conversation while changing the action.
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
  bool _isParent = false;

  late bool _isViewing;

  // Sub-task quick-add. Edit mode writes straight to the DB (the row
  // exists); create mode queues names and creates them after the action
  // itself saves — the same shape as tasks in the plan activity dialog.
  final _subTaskCtrl = TextEditingController();
  final _subTaskFocus = FocusNode();
  final List<String> _pendingSubTaskNames = [];

  List<Person> _persons = [];
  List<ActionCategory> _categories = [];
  List<ProjectAction> _allActions = [];
  List<TimelineWorkPackage> _workPackages = [];
  List<TimelineActivity> _planActivities = [];

  final _statuses = ['open', 'in progress', 'closed', 'blocked'];
  final _priorities = ['low', 'medium', 'high', 'critical'];
  final _sources = [
    'manual', 'inbox', 'document', 'observation', 'meeting', 'journal'
  ];
  final _recurrences = ['none', 'weekly', 'fortnightly', 'monthly', 'quarterly'];

  bool get _isEdit => widget.action != null;

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
    _isParent = a?.isParent ?? false;
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
    _subTaskCtrl.dispose();
    _subTaskFocus.dispose();
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

    // An action with children is a parent whatever the checkbox says —
    // keeps the flag honest for rows that predate it. Queued sub-tasks
    // make it one too.
    if ((widget.action != null &&
            _allActions.any((a) => a.parentActionId == widget.action!.id)) ||
        _pendingSubTaskNames.isNotEmpty) {
      _isParent = true;
    }

    final existing = await widget.db.actionsDao.getActionsForProject(widget.projectId);
    final String baseRef =
        widget.action?.ref ?? ActionsDao.nextRef(existing);

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
          isParent: Value(_isParent),
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
        isParent: Value(_isParent),
        updatedAt: Value(DateTime.now()),
      ));
      // Sub-tasks queued while creating — the parent row exists now.
      for (final name in _pendingSubTaskNames) {
        await widget.db.actionsDao.addSubTask(
          id: const Uuid().v4(),
          parentId: id,
          description: name,
        );
      }
    }

    if (!isEdit && mounted) {
      context.analytics.track(
        KeelEvents.actionCreated,
        props: {KeelEventProps.source: 'action_form'},
      );
    }
    // Cascade an edited action to linked programmes; the service decides
    // per link. New rows reach the programme on the next reconcile.
    if (widget.action != null && mounted) {
      final fresh = await widget.db.actionsDao.getActionById(widget.action!.id);
      if (fresh != null && mounted) {
        await buildCascadeService(context).pushAction(fresh);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  String _planActivityLabel(String activityId) => PlanActivityPicker.labelFor(
        activityId,
        workPackages: _workPackages,
        activities: _planActivities,
      );

  Color get _accent {
    final cat = _categoryId != null
        ? _categories.where((c) => c.id == _categoryId).firstOrNull
        : null;
    return cat != null ? parseHexColor(cat.color) : KColors.amber;
  }

  // ── Sub-tasks ──────────────────────────────────────────────────────────────

  /// Whether this action may hold sub-tasks: the hierarchy is capped at
  /// parent → task → sub-task, so anything already at depth 2 can't.
  bool get _canHaveSubTasks {
    final byId = {for (final a in _allActions) a.id: a};
    // Judge by the chosen parent (the form may be re-nesting it), not
    // only the persisted row: nesting under a task makes this a
    // sub-task, and sub-tasks can't hold children.
    final chosen = _parentActionId != null ? byId[_parentActionId!] : null;
    if (chosen != null && chosen.parentActionId != null) return false;
    // A recurring series is many rows; sub-tasks would attach to just
    // one of them, so they aren't offered at creation time.
    if (!_isEdit && _recurrence != 'none') return false;
    return true;
  }

  List<ProjectAction> get _children {
    final parent = widget.action;
    if (parent == null) return const [];
    return _allActions
        .where((c) => c.parentActionId == parent.id)
        .toList()
      ..sort((x, y) {
        final xClosed = x.status == 'closed' ? 1 : 0;
        final yClosed = y.status == 'closed' ? 1 : 0;
        if (xClosed != yClosed) return xClosed - yClosed;
        if (x.dueDate != null && y.dueDate != null) {
          return x.dueDate!.compareTo(y.dueDate!);
        }
        if (x.dueDate != null) return -1;
        if (y.dueDate != null) return 1;
        return x.createdAt.compareTo(y.createdAt);
      });
  }

  Future<void> _quickAddSubTask() async {
    final name = _subTaskCtrl.text.trim();
    if (name.isEmpty) return;
    _subTaskCtrl.clear();
    if (_isEdit) {
      await widget.db.actionsDao.addSubTask(
        id: const Uuid().v4(),
        parentId: widget.action!.id,
        description: name,
      );
      if (!mounted) return;
      setState(() => _isParent = true);
      await _loadData();
    } else {
      setState(() {
        _pendingSubTaskNames.add(name);
        _isParent = true;
      });
    }
    _subTaskFocus.requestFocus();
  }

  Future<void> _openSubTask(ProjectAction c) async {
    await showDialog(
      context: context,
      builder: (_) => ActionFormDialog(
        projectId: widget.projectId,
        db: widget.db,
        action: c,
        startInViewMode: true,
      ),
    );
    // The child may have been edited or deleted — refresh so this list
    // (and the done counter) reflects it.
    await _loadData();
  }

  /// Sub-task list + (edit/create) quick-add. In read mode with no
  /// children this collapses to nothing.
  List<Widget> _subTasksSection({required bool editable}) {
    final children = _children;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final doneCount = children.where((c) => c.status == 'closed').length;

    if (!editable && children.isEmpty) return const [];
    if (editable && !_canHaveSubTasks) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Sub-tasks can’t contain actions of their own.',
            style: TextStyle(color: KColors.textMuted, fontSize: 10),
          ),
        ),
        SizedBox(height: 8),
      ];
    }

    return [
      DetailSectionLabel(children.isEmpty
          ? 'Sub-tasks'
          : 'Sub-tasks · $doneCount of ${children.length} done'),
      const SizedBox(height: 6),
      for (final c in children) _subTaskRow(c, today, editable: editable),
      if (!_isEdit)
        for (var i = 0; i < _pendingSubTaskNames.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              const Icon(Icons.radio_button_unchecked,
                  size: 16, color: KColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_pendingSubTaskNames[i],
                    style: const TextStyle(color: KColors.text, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              InkWell(
                onTap: () =>
                    setState(() => _pendingSubTaskNames.removeAt(i)),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 12, color: KColors.textMuted),
                ),
              ),
            ]),
          ),
      if (editable) ...[
        const SizedBox(height: 4),
        TextField(
          controller: _subTaskCtrl,
          focusNode: _subTaskFocus,
          style: const TextStyle(color: KColors.text, fontSize: 12),
          decoration: InputDecoration(
            hintText: _isEdit
                ? 'Add sub-task — Enter to save, keep typing for more'
                : 'Add sub-task — created with the action',
            hintStyle: const TextStyle(color: KColors.textMuted, fontSize: 12),
            isDense: true,
            prefixIcon: const Icon(Icons.add, size: 14, color: KColors.textDim),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          onSubmitted: (_) => _quickAddSubTask(),
        ),
      ],
      const SizedBox(height: 12),
    ];
  }

  Widget _subTaskRow(ProjectAction c, String today, {required bool editable}) {
    final closed = c.status == 'closed';
    final overdue =
        !closed && c.dueDate != null && c.dueDate!.compareTo(today) < 0;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _openSubTask(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(children: [
          Tooltip(
            message: closed ? 'Reopen' : 'Mark done',
            child: InkWell(
              onTap: () async {
                await widget.db.actionsDao
                    .setStatus(c.id, closed ? 'open' : 'closed');
                await _loadData();
              },
              child: Icon(
                closed ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: closed ? KColors.phosphor : KColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (c.ref != null) ...[
            Text(c.ref!,
                style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              c.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: closed ? KColors.textMuted : KColors.text,
                fontSize: 12,
                decoration: closed ? TextDecoration.lineThrough : null,
                decorationColor: KColors.textMuted,
              ),
            ),
          ),
          if (c.owner != null && c.owner!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(c.owner!,
                style:
                    const TextStyle(color: KColors.textMuted, fontSize: 10)),
          ],
          if (c.dueDate != null) ...[
            const SizedBox(width: 8),
            Text(
              du.formatDate(c.dueDate),
              style: TextStyle(
                color: overdue ? KColors.red : KColors.textMuted,
                fontSize: 10,
              ),
            ),
          ],
          const SizedBox(width: 4),
          if (editable)
            Tooltip(
              message: 'Move to top level (keeps the action)',
              child: InkWell(
                onTap: () async {
                  await widget.db.actionsDao.setParent(c.id, null);
                  await _loadData();
                },
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 12, color: KColors.textMuted),
                ),
              ),
            )
          else
            const Icon(Icons.chevron_right, size: 14, color: KColors.textMuted),
        ]),
      ),
    );
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
    final parent = a.parentActionId != null
        ? _allActions.where((p) => p.id == a.parentActionId).firstOrNull
        : null;

    return DetailDialog(
      accent: _accent,
      title: [
        if (a.ref != null) ...[DetailRefChip(a.ref!), const SizedBox(width: 10)],
        const Expanded(child: DetailTitle('Action')),
        if (a.recurrenceGroupId != null)
          const Tooltip(
            message: 'Recurring action',
            child: Icon(Icons.repeat, size: 14, color: KColors.textDim),
          ),
        if (cat != null) ...[
          const SizedBox(width: 10),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: parseHexColor(cat.color), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(cat.name,
              style: TextStyle(
                  color: parseHexColor(cat.color),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ],
      left: [
        DetailField('Description', a.description, large: true),
        Row(children: [
          Expanded(child: DetailField('Status', a.status)),
          Expanded(child: DetailField('Priority', a.priority)),
        ]),
        Row(children: [
          if (a.owner != null && a.owner!.isNotEmpty)
            Expanded(child: DetailField('Owner', a.owner)),
          if (a.dueDate != null)
            Expanded(
              child: DetailField('Due Date', du.formatDate(a.dueDate),
                  valueColor: isOverdue ? KColors.red : null),
            ),
        ]),
        Row(children: [
          Expanded(child: DetailField('Source', a.source)),
          if (a.sourceNote != null && a.sourceNote!.isNotEmpty)
            Expanded(child: DetailField('Source Note', a.sourceNote)),
        ]),
        if (a.planActivityId != null)
          DetailField('Plan Activity', _planActivityLabel(a.planActivityId!)),
        if (parent != null)
          DetailField('Part of',
              '${parent.ref != null ? '${parent.ref} · ' : ''}${parent.description}'),
        JournalSourceLink(
          db: widget.db,
          projectId: widget.projectId,
          itemId: a.id,
          itemText: a.description,
        ),
      ],
      right: [
        ..._subTasksSection(editable: false),
        if (_children.isNotEmpty) const DetailDivider(),
        _CommentsThread(action: a, db: widget.db),
      ],
      footer: [
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close',
              style: TextStyle(color: KColors.textDim, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => setState(() => _isViewing = false),
          icon: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Edit', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── Edit/create mode ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isViewing) return _readView();

    final isEdit = _isEdit;
    return DetailDialog(
      accent: _accent,
      formKey: _formKey,
      title: [
        if (widget.action?.ref != null) ...[
          DetailRefChip(widget.action!.ref!),
          const SizedBox(width: 10),
        ],
        Expanded(child: DetailTitle(isEdit ? 'Edit Action' : 'New Action')),
      ],
      left: [
        // ── Category chips ─────────────────────────────────────
        if (_categories.isNotEmpty) ...[
          const DetailSectionLabel('Category'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ..._categories.map((cat) => _CategoryChip(
                    category: cat,
                    selected: _categoryId == cat.id,
                    onTap: () => setState(() =>
                        _categoryId = _categoryId == cat.id ? null : cat.id),
                  )),
              _AddCategoryChip(onTap: () => _showAddCategoryDialog()),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // ── Description ────────────────────────────────────────
        TextFormField(
          controller: _descCtrl,
          autofocus: !isEdit,
          minLines: 2,
          maxLines: 5,
          style: const TextStyle(color: KColors.text, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Description *',
            alignLabelWithHint: true,
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
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
          const DetailSectionLabel('Recurrence'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownField(
                label: 'Repeats',
                value: _recurrence,
                items: _recurrences,
                onChanged: (v) => setState(() => _recurrence = v!),
              ),
            ),
            if (_recurrence != 'none') ...[
              const SizedBox(width: 12),
              Expanded(
                child: DatePickerField(
                  label: 'Repeat until',
                  isoValue: _recurrenceEndDate,
                  onChanged: (v) => setState(() => _recurrenceEndDate = v),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          const Divider(color: KColors.border, height: 1),
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
              decoration: const InputDecoration(labelText: 'Source Note'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
      ],
      right: [
        // ── Structure: parent flag, nesting, plan link ─────────
        const DetailSectionLabel('Structure'),
        const SizedBox(height: 8),
        _IsParentCheckbox(
          editing: widget.action,
          allActions: _allActions,
          value: _isParent,
          parentActionId: _parentActionId,
          onChanged: (v) => setState(() => _isParent = v),
        ),
        const SizedBox(height: 12),
        _ParentActionPicker(
          editing: widget.action,
          allActions: _allActions,
          value: _parentActionId,
          onChanged: (v) => setState(() => _parentActionId = v),
        ),
        const SizedBox(height: 12),
        if (_workPackages.isNotEmpty) ...[
          PlanActivityPicker(
            value: _planActivityId,
            workPackages: _workPackages,
            activities: _planActivities,
            onChanged: (v) => setState(() => _planActivityId = v),
          ),
          const SizedBox(height: 12),
        ],
        const DetailDivider(),

        // ── Sub-tasks ──────────────────────────────────────────
        if (isEdit || _recurrence == 'none')
          ..._subTasksSection(editable: true),

        // ── Comments (existing rows only — they persist live) ──
        if (isEdit) ...[
          const DetailDivider(),
          JournalSourceLink(
            db: widget.db,
            projectId: widget.projectId,
            itemId: widget.action!.id,
            itemText: widget.action!.description,
          ),

          _CommentsThread(action: widget.action!, db: widget.db),
        ],
      ],
      footer: [
        const Spacer(),
        if (widget.startInViewMode)
          TextButton(
            onPressed: () => setState(() => _isViewing = true),
            child: const Text('Cancel',
                style: TextStyle(color: KColors.textDim, fontSize: 12)),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: KColors.textDim, fontSize: 12)),
          ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Create',
              style: const TextStyle(fontSize: 12)),
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
// Parent action picker (Epic-style grouping)
// ---------------------------------------------------------------------------

class _IsParentCheckbox extends StatelessWidget {
  final ProjectAction? editing;
  final List<ProjectAction> allActions;
  final bool value;
  final String? parentActionId;
  final ValueChanged<bool> onChanged;

  const _IsParentCheckbox({
    required this.editing,
    required this.allActions,
    required this.value,
    required this.parentActionId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final byId = {for (final a in allActions) a.id: a};
    final childCount = editing == null
        ? 0
        : allActions.where((a) => a.parentActionId == editing!.id).length;
    // Locked on while children exist; unavailable to sub-tasks (a child
    // whose chosen parent is itself nested is already at max depth).
    final chosenParent =
        parentActionId != null ? byId[parentActionId!] : null;
    final atMaxDepth =
        chosenParent != null && chosenParent.parentActionId != null;
    final locked = childCount > 0 || atMaxDepth;

    final String? hint;
    if (childCount > 0) {
      hint = '$childCount child action${childCount == 1 ? '' : 's'}';
    } else if (atMaxDepth) {
      hint = 'Sub-tasks can’t contain actions';
    } else {
      hint = null;
    }

    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: value || childCount > 0,
            onChanged:
                locked ? null : (v) => onChanged(v ?? false),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.account_tree_outlined,
            size: 13, color: KColors.phosphor),
        const SizedBox(width: 5),
        const Flexible(
          child: Text(
            'Parent — can group other actions',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: KColors.text, fontSize: 12),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(hint,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style:
                    const TextStyle(color: KColors.textMuted, fontSize: 10)),
          ),
        ],
      ],
    );
  }
}

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
    final byId = {for (final a in allActions) a.id: a};
    final candidates =
        eligibleParentCandidates(editing: editing, all: allActions);
    // A selection made before rules changed (or synced in) stays visible
    // even if it's no longer offered fresh.
    if (value != null &&
        byId[value!] != null &&
        !candidates.any((c) => c.id == value)) {
      candidates.insert(0, byId[value!]!);
    }

    if (editing != null && candidates.isEmpty && value == null) {
      final part = partitionByParent(allActions);
      if (actionSubtreeHeight(editing!.id, part.childrenByParent) >= 2) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Has sub-tasks two levels deep — can’t be nested under '
            'another action.',
            style: TextStyle(color: KColors.textMuted, fontSize: 10),
          ),
        );
      }
    }

    String labelFor(ProjectAction a) {
      final base = '${a.ref != null ? '${a.ref} ' : ''}${a.description}';
      final parent =
          a.parentActionId != null ? byId[a.parentActionId!] : null;
      return parent == null ? base : '$base  ·  under ${parent.ref ?? parent.description}';
    }

    // Before the action list loads (or if the parent was deleted) the
    // value has no matching item — show "none" rather than trip the
    // dropdown's single-match assertion.
    final safeValue = candidates.any((c) => c.id == value) ? value : null;

    return DropdownButtonFormField<String?>(
      value: safeValue,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Nest under parent (optional)',
      ),
      items: [
        const DropdownMenuItem<String?>(
            value: null, child: Text('— none (top level) —')),
        ...candidates.map((a) => DropdownMenuItem<String?>(
              value: a.id,
              child: Text(
                labelFor(a),
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
