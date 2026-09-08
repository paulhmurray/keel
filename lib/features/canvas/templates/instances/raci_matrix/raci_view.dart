import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/database/database.dart';
import '../../../../../shared/theme/keel_colors.dart';
import '../../../../../shared/widgets/person_picker_field.dart';
import 'raci_model.dart';

/// View for a single RACI Matrix template.
///
/// Rows = activities, columns = people, cells cycle blank → R → A → C
/// → I → blank on click. First column (activity name) and the header
/// row (person name) are inline-editable. Add Activity / Add Person
/// in the toolbar. Horizontal scroll for matrices with many people.
class RaciView extends StatefulWidget {
  final CanvasTemplate template;

  const RaciView({super.key, required this.template});

  @override
  State<RaciView> createState() => _RaciViewState();
}

class _RaciViewState extends State<RaciView> {
  static const double _activityColWidth = 220;
  static const double _personColWidth = 110;
  static const double _rowHeight = 40;
  static const double _headerHeight = 40;

  late RaciContent _content;
  final Map<String, TextEditingController> _activityCtrls = {};
  final Map<String, TextEditingController> _personCtrls = {};
  // Explicit controller — the Scrollbar/SingleChildScrollView pair on
  // horizontal axes can't fall back to PrimaryScrollController.
  final ScrollController _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _content = RaciContent.decode(widget.template.content);
    _seedControllers();
  }

  @override
  void didUpdateWidget(covariant RaciView old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id) {
      _content = RaciContent.decode(widget.template.content);
      _disposeControllers();
      _seedControllers();
    }
  }

  void _seedControllers() {
    for (final a in _content.activities) {
      _activityCtrls.putIfAbsent(
          a.id, () => TextEditingController(text: a.name));
    }
    for (final p in _content.people) {
      _personCtrls.putIfAbsent(
          p.id, () => TextEditingController(text: p.name));
    }
  }

  void _disposeControllers() {
    for (final c in _activityCtrls.values) {
      c.dispose();
    }
    for (final c in _personCtrls.values) {
      c.dispose();
    }
    _activityCtrls.clear();
    _personCtrls.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    _hScroll.dispose();
    super.dispose();
  }

  // ---- Mutations ----------------------------------------------------------

  Future<void> _save(RaciContent next) async {
    setState(() => _content = next);
    final db = context.read<AppDatabase>();
    await db.canvasTemplatesDao.patchTemplate(
      widget.template.id,
      CanvasTemplatesCompanion(content: Value(next.encode())),
    );
  }

  void _addActivity() {
    final id = const Uuid().v4();
    _activityCtrls[id] = TextEditingController();
    final activities = [
      ..._content.activities,
      RaciActivity(id: id, sortOrder: _content.activities.length),
    ];
    _save(_content.copyWith(activities: activities));
  }

  void _editActivityName(String id, String name) {
    final updated = _content.activities
        .map((a) => a.id == id ? a.copyWith(name: name) : a)
        .toList();
    _save(_content.copyWith(activities: updated));
  }

  void _deleteActivity(String id) {
    final filtered =
        _content.activities.where((a) => a.id != id).toList();
    final renumbered = [
      for (var i = 0; i < filtered.length; i++)
        filtered[i].copyWith(sortOrder: i),
    ];
    _activityCtrls.remove(id)?.dispose();
    // Drop any assignments referencing this activity.
    final assignments = _content.assignments
        .where((x) => x.activityId != id)
        .toList();
    _save(_content.copyWith(
      activities: renumbered,
      assignments: assignments,
    ));
  }

  void _addPersonFromProject(Person p) {
    final id = const Uuid().v4();
    _personCtrls[id] = TextEditingController(text: p.name);
    final people = [
      ..._content.people,
      RaciPerson(
        id: id,
        name: p.name,
        personId: p.id,
        sortOrder: _content.people.length,
      ),
    ];
    _save(_content.copyWith(people: people));
  }

  /// Opens the canonical [AddPersonDialog], persists the new Person to
  /// the project's Persons table, and then adds them to the RACI matrix
  /// via the same path used by the dropdown's existing-person picker.
  /// No more free-text rows that live only inside the RACI JSON — every
  /// person on the matrix exists as a real Person.
  Future<void> _addNewPerson() async {
    final db = context.read<AppDatabase>();
    final result = await showDialog<NewPersonResult>(
      context: context,
      builder: (_) => AddPersonDialog(
        name: '',
        db: db,
        projectId: widget.template.projectId,
      ),
    );
    if (result == null) return;
    final now = DateTime.now();
    final personId = const Uuid().v4();
    await db.peopleDao.upsertPerson(PersonsCompanion(
      id: Value(personId),
      projectId: Value(widget.template.projectId),
      name: Value(result.name),
      role: Value(result.role),
      organisation: Value(result.organisation),
      personType: Value(result.personType),
      isStakeholder: Value(result.isStakeholder),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    _addPersonFromProject(Person(
      id: personId,
      projectId: widget.template.projectId,
      name: result.name,
      role: result.role,
      organisation: result.organisation,
      personType: result.personType,
      isStakeholder: result.isStakeholder,
      createdAt: now,
      updatedAt: now,
    ));
  }

  void _editPersonName(String id, String name) {
    final updated = _content.people
        .map((p) => p.id == id ? p.copyWith(name: name) : p)
        .toList();
    _save(_content.copyWith(people: updated));
  }

  void _deletePerson(String id) {
    final filtered = _content.people.where((p) => p.id != id).toList();
    final renumbered = [
      for (var i = 0; i < filtered.length; i++)
        filtered[i].copyWith(sortOrder: i),
    ];
    _personCtrls.remove(id)?.dispose();
    final assignments =
        _content.assignments.where((x) => x.personId != id).toList();
    _save(_content.copyWith(
      people: renumbered,
      assignments: assignments,
    ));
  }

  void _cycleCell(String activityId, String personId) {
    final current = _content.roleFor(activityId, personId);
    final next = RaciRole.next(current);
    final without = _content.assignments
        .where((a) =>
            !(a.activityId == activityId && a.personId == personId))
        .toList();
    final updated = next == null
        ? without // blank — drop the row to keep JSON compact
        : [
            ...without,
            RaciAssignment(
              activityId: activityId,
              personId: personId,
              role: next,
            ),
          ];
    _save(_content.copyWith(assignments: updated));
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<Person>>(
      stream:
          db.peopleDao.watchPersonsForProject(widget.template.projectId),
      builder: (context, snap) {
        final people = snap.data ?? const <Person>[];
        // Persons NOT yet in the matrix (only filter project-linked
        // people; free-text rows can't dedupe).
        final usedIds = _content.people
            .map((p) => p.personId)
            .whereType<String>()
            .toSet();
        final addable = people
            .where((p) => !usedIds.contains(p.id))
            .toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Toolbar(
                addable: addable,
                onAddActivity: _addActivity,
                onAddPersonFromProject: _addPersonFromProject,
                onAddNewPerson: _addNewPerson,
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildMatrix()),
              const SizedBox(height: 10),
              const _Legend(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMatrix() {
    if (_content.activities.isEmpty && _content.people.isEmpty) {
      return _EmptyState(onAddActivity: _addActivity);
    }
    return Scrollbar(
      controller: _hScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _hScroll,
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row.
            Row(
              children: [
                Container(
                  width: _activityColWidth,
                  height: _headerHeight,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom:
                          BorderSide(color: KColors.border, width: 1),
                      right:
                          BorderSide(color: KColors.border, width: 1),
                    ),
                  ),
                  child: const Text(
                    'ACTIVITY',
                    style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                for (final p in _content.people)
                  _PersonHeader(
                    person: p,
                    ctrl: _personCtrls[p.id]!,
                    width: _personColWidth,
                    height: _headerHeight,
                    onNameChanged: (v) => _editPersonName(p.id, v),
                    onDelete: () => _deletePerson(p.id),
                  ),
              ],
            ),
            // Activity rows.
            for (final a in _content.activities)
              Row(
                children: [
                  _ActivityCell(
                    activity: a,
                    ctrl: _activityCtrls[a.id]!,
                    width: _activityColWidth,
                    height: _rowHeight,
                    onNameChanged: (v) => _editActivityName(a.id, v),
                    onDelete: () => _deleteActivity(a.id),
                  ),
                  for (final p in _content.people)
                    _RoleCell(
                      role: _content.roleFor(a.id, p.id),
                      width: _personColWidth,
                      height: _rowHeight,
                      onTap: () => _cycleCell(a.id, p.id),
                    ),
                ],
              ),
          ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final List<Person> addable;
  final VoidCallback onAddActivity;
  final ValueChanged<Person> onAddPersonFromProject;
  final VoidCallback onAddNewPerson;

  const _Toolbar({
    required this.addable,
    required this.onAddActivity,
    required this.onAddPersonFromProject,
    required this.onAddNewPerson,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'RACI MATRIX',
          style: TextStyle(
            color: KColors.amber,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: onAddActivity,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Add activity'),
          style: OutlinedButton.styleFrom(
            foregroundColor: KColors.amber,
            side: const BorderSide(color: KColors.amber),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: const TextStyle(fontSize: 12),
            minimumSize: const Size(0, 32),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Add person',
          onSelected: (id) {
            if (id == '__add_new__') {
              onAddNewPerson();
            } else {
              final p = addable.firstWhere((x) => x.id == id);
              onAddPersonFromProject(p);
            }
          },
          itemBuilder: (_) => [
            for (final p in addable)
              PopupMenuItem<String>(
                value: p.id,
                child: Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 14, color: KColors.textDim),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        p.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            if (addable.isNotEmpty) const PopupMenuDivider(),
            const PopupMenuItem(
              value: '__add_new__',
              child: Row(
                children: [
                  Icon(Icons.person_add_alt_1,
                      size: 14, color: KColors.textDim),
                  SizedBox(width: 8),
                  Text('Add new person…',
                      style: TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
          ],
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: KColors.amberDim.withValues(alpha: 0.6),
              border: Border.all(
                color: KColors.amber.withValues(alpha: 0.7),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: KColors.amber),
                SizedBox(width: 4),
                Text(
                  'Add person',
                  style: TextStyle(
                    color: KColors.amber,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityCell extends StatelessWidget {
  final RaciActivity activity;
  final TextEditingController ctrl;
  final double width;
  final double height;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onDelete;

  const _ActivityCell({
    required this.activity,
    required this.ctrl,
    required this.width,
    required this.height,
    required this.onNameChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: KColors.surface,
        border: Border(
          bottom: BorderSide(color: KColors.border, width: 0.5),
          right: BorderSide(color: KColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'Activity',
                hintStyle: TextStyle(
                    color: KColors.textMuted, fontSize: 12),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onNameChanged,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            tooltip: 'Delete activity',
            icon: const Icon(Icons.close,
                size: 13, color: KColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _PersonHeader extends StatelessWidget {
  final RaciPerson person;
  final TextEditingController ctrl;
  final double width;
  final double height;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onDelete;

  const _PersonHeader({
    required this.person,
    required this.ctrl,
    required this.width,
    required this.height,
    required this.onNameChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        color: KColors.surface,
        border: Border(
          bottom: BorderSide(color: KColors.border, width: 1),
          right: BorderSide(color: KColors.border, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                hintText: 'Name',
                hintStyle: TextStyle(
                    color: KColors.textMuted, fontSize: 11.5),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onNameChanged,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            tooltip: 'Remove column',
            icon: const Icon(Icons.close,
                size: 12, color: KColors.textMuted),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 22, minHeight: 22),
          ),
        ],
      ),
    );
  }
}

class _RoleCell extends StatelessWidget {
  final String? role;
  final double width;
  final double height;
  final VoidCallback onTap;

  const _RoleCell({
    required this.role,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Capture into a local so Dart flow analysis can promote it past
    // the null check below (public final fields don't auto-promote).
    final r = role;
    final colour = _colourFor(r);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colour == null
              ? KColors.bg
              : colour.withValues(alpha: 0.18),
          border: const Border(
            bottom: BorderSide(color: KColors.border, width: 0.5),
            right: BorderSide(color: KColors.border, width: 0.5),
          ),
        ),
        child: r == null
            ? const SizedBox.shrink()
            : Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  r,
                  style: const TextStyle(
                    color: KColors.bg,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
      ),
    );
  }

  Color? _colourFor(String? r) {
    switch (r) {
      case RaciRole.responsible:
        return KColors.blue;
      case RaciRole.accountable:
        return KColors.amber;
      case RaciRole.consulted:
        return KColors.phosphor;
      case RaciRole.informed:
        return KColors.textDim;
      default:
        return null;
    }
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget chip(String letter, String label, Color color) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              letter,
              style: const TextStyle(
                color: KColors.bg,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        chip('R', 'Responsible', KColors.blue),
        const SizedBox(width: 16),
        chip('A', 'Accountable', KColors.amber),
        const SizedBox(width: 16),
        chip('C', 'Consulted', KColors.phosphor),
        const SizedBox(width: 16),
        chip('I', 'Informed', KColors.textDim),
        const Spacer(),
        const Text(
          'Click a cell to cycle: blank → R → A → C → I → blank',
          style: TextStyle(
            color: KColors.textMuted,
            fontSize: 10.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddActivity;

  const _EmptyState({required this.onAddActivity});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.table_chart_outlined,
                  size: 26, color: KColors.amber),
              const SizedBox(height: 12),
              const Text(
                'Add activities and people to start',
                style: TextStyle(
                  color: KColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'List the activities along the rows, the people across '
                'the top, then click a cell to mark them Responsible, '
                'Accountable, Consulted, or Informed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: KColors.textDim,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: onAddActivity,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add first activity'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: KColors.amberDim,
                  foregroundColor: KColors.amber,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                    side: const BorderSide(color: KColors.amber, width: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
