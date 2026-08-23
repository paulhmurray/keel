import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/database.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/min_width_hscroll.dart';
import '../../shared/widgets/source_badge.dart';
import '../../shared/utils/avatar_utils.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../timeline/timeline_chart.dart' show parseHexColor;
import 'action_form.dart';
import 'action_grouping.dart';

// ---------------------------------------------------------------------------
// Column model
// ---------------------------------------------------------------------------

enum _Col { todo, inProgress, overdue, done }

extension _ColExt on _Col {
  String get label => switch (this) {
        _Col.todo => 'To Do',
        _Col.inProgress => 'In Progress',
        _Col.overdue => 'Overdue',
        _Col.done => 'Done',
      };

  String get dbStatus => switch (this) {
        _Col.todo => 'open',
        _Col.inProgress => 'in progress',
        _Col.overdue => 'overdue',
        _Col.done => 'closed',
      };
}

_Col _colFor(ProjectAction a) {
  if (a.status == 'closed') return _Col.done;
  final today = DateTime.now().toIso8601String().substring(0, 10);
  if (a.dueDate != null && a.dueDate!.compareTo(today) < 0) return _Col.overdue;
  if (a.status == 'overdue') return _Col.overdue;
  if (a.status == 'in progress') return _Col.inProgress;
  return _Col.todo;
}

List<ProjectAction> _sorted(List<ProjectAction> items) {
  final dated = items.where((a) => a.dueDate != null).toList()
    ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  final undated = items.where((a) => a.dueDate == null).toList();
  return [...dated, ...undated];
}

Color _dueDateColor(String? dueDate) {
  if (dueDate == null) return KColors.textDim;
  final today = DateTime.now().toIso8601String().substring(0, 10);
  if (dueDate.compareTo(today) < 0) return KColors.red;
  final inThree = DateTime.now()
      .add(const Duration(days: 3))
      .toIso8601String()
      .substring(0, 10);
  if (dueDate.compareTo(inThree) <= 0) return KColors.amber;
  return KColors.textDim;
}

// ---------------------------------------------------------------------------
// Layout constants
// ---------------------------------------------------------------------------

const double _kLaneHeaderWidth = 180;

// ---------------------------------------------------------------------------
// ActionsKanban
// ---------------------------------------------------------------------------

class ActionsKanban extends StatefulWidget {
  final List<ProjectAction> actions;
  final Map<String, ActionCategory> catMap;
  final AppDatabase db;
  final String projectId;
  final Map<String, String> planTagMap;
  final bool Function(ProjectAction) ownerMatches;
  final bool ownerFilterActive;

  const ActionsKanban({
    super.key,
    required this.actions,
    required this.catMap,
    required this.db,
    required this.projectId,
    required this.ownerMatches,
    required this.ownerFilterActive,
    this.planTagMap = const {},
  });

  @override
  State<ActionsKanban> createState() => _ActionsKanbanState();
}

class _ActionsKanbanState extends State<ActionsKanban> {
  String? _pendingOutcomeId;
  final _outcomeCtrl = TextEditingController();
  final _outcomeFocus = FocusNode();

  @override
  void dispose() {
    _outcomeCtrl.dispose();
    _outcomeFocus.dispose();
    super.dispose();
  }

  Future<void> _drop(
      ProjectAction action, _Col targetCol, String? targetParentId) async {
    final statusChange = _colFor(action) != targetCol;
    final parentChange = action.parentActionId != targetParentId;
    if (!statusChange && !parentChange) return;

    // Nesting keeps the whole subtree together, so it's allowed as long
    // as the tree still fits within two levels under the lane's root.
    if (targetParentId != null && parentChange) {
      if (action.id == targetParentId) return;
      final part = partitionByParent(widget.actions);
      if (actionDescendantIds(action.id, part.childrenByParent)
          .contains(targetParentId)) {
        return;
      }
      if (actionSubtreeHeight(action.id, part.childrenByParent) + 1 >
          kMaxActionDepth) {
        return;
      }
    }

    final isClose = statusChange && targetCol == _Col.done;

    // Two focused, explicit writes in a transaction so neither side gets
    // accidentally dropped by partial-companion semantics.
    await widget.db.transaction(() async {
      if (parentChange) {
        await widget.db.actionsDao.setParent(action.id, targetParentId);
      }
      if (statusChange) {
        await widget.db.actionsDao.upsertAction(ProjectActionsCompanion(
          id: Value(action.id),
          projectId: Value(action.projectId),
          description: Value(action.description),
          status: Value(isClose ? 'closed' : targetCol.dbStatus),
          updatedAt: Value(DateTime.now()),
        ));
      }
    });

    if (isClose) {
      setState(() {
        _pendingOutcomeId = action.id;
        _outcomeCtrl.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _outcomeFocus.requestFocus();
      });
    }
  }

  Future<void> _saveOutcome(ProjectAction action) async {
    final outcome = _outcomeCtrl.text.trim();
    final author = context.read<SettingsProvider>().settings.myName;
    final now = DateTime.now();

    await widget.db.transaction(() async {
      await widget.db.actionsDao.upsertAction(ProjectActionsCompanion(
        id: Value(action.id),
        projectId: Value(action.projectId),
        description: Value(action.description),
        status: const Value('closed'),
        outcome: Value(outcome.isEmpty ? null : outcome),
        updatedAt: Value(now),
      ));
      // Mirror non-empty outcomes into a special "completion" comment so
      // the reason shows up in the action's running comment thread.
      if (outcome.isNotEmpty) {
        await widget.db.actionCommentsDao.upsertComment(ActionCommentsCompanion(
          id: Value(const Uuid().v4()),
          actionId: Value(action.id),
          content: Value(outcome),
          isCompletion: const Value(true),
          authorName: Value(author.isEmpty ? null : author),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
      }
    });

    if (mounted) setState(() => _pendingOutcomeId = null);
  }

  void _dismissOutcome() => setState(() => _pendingOutcomeId = null);

  /// Drop card [dragged] onto card [target]: nest it as a child/sub-task,
  /// promoting the target to a group parent if needed.
  Future<void> _nestUnderCard(
      ProjectAction dragged, ProjectAction target) async {
    if (dragged.id == target.id) return;
    final part = partitionByParent(widget.actions);
    final byId = {for (final a in widget.actions) a.id: a};
    if (actionDescendantIds(dragged.id, part.childrenByParent)
        .contains(target.id)) {
      return;
    }
    final height = actionSubtreeHeight(dragged.id, part.childrenByParent);
    if (actionDepth(target, byId) + 1 + height > kMaxActionDepth) return;
    await widget.db.actionsDao.nestUnder(dragged.id, target.id);
  }

  Future<void> _closeGroup(ProjectAction root) async {
    final part = partitionByParent(widget.actions);
    final ids = [
      root.id,
      ...actionDescendantIds(root.id, part.childrenByParent),
    ];
    final openCount = widget.actions
        .where((a) => ids.contains(a.id) && a.status != 'closed')
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close group'),
        content: Text(openCount == 0
            ? 'Close this group? It will leave the board (find it again '
                'via "show old closed").'
            : 'Close this group and its $openCount open '
                'action${openCount == 1 ? '' : 's'}? The group will leave '
                'the board (find it again via "show old closed").'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Close group')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.db.actionsDao.closeActions(ids);
  }

  Future<void> _toggleSubTask(ProjectAction s, bool closed) async {
    await widget.db.actionsDao.upsertAction(ProjectActionsCompanion(
      id: Value(s.id),
      projectId: Value(s.projectId),
      description: Value(s.description),
      status: Value(closed ? 'closed' : 'open'),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _deleteAction(ProjectAction a) async {
    if (_pendingOutcomeId == a.id) {
      setState(() => _pendingOutcomeId = null);
    }
    await widget.db.actionsDao.deleteAction(a.id);
  }

  Future<void> _deleteSeries(ProjectAction a) async {
    if (a.recurrenceGroupId == null) return;
    await widget.db.actionsDao.deleteByRecurrenceGroup(a.recurrenceGroupId!);
  }

  void _openCard(ProjectAction a) => showDialog(
        context: context,
        builder: (_) => ActionFormDialog(
          projectId: widget.projectId,
          db: widget.db,
          action: a,
          startInViewMode: true,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final part = partitionByParent(widget.actions);

    // Build lanes:
    //   - One per designated parent (even before it has children, so
    //     there's a lane to drag into)
    //   - One "Ungrouped" lane for the other top-level actions
    final parentLanes = <_LaneSpec>[];
    final ungroupedActions = <ProjectAction>[];
    for (final root in part.roots) {
      final children = part.childrenByParent[root.id] ?? const [];
      if (children.isNotEmpty || root.isParent) {
        parentLanes.add(_LaneSpec.forParent(root, children));
      } else {
        ungroupedActions.add(root);
      }
    }

    // Apply owner filter.
    final visibleParentLanes = parentLanes.where((l) {
      if (!widget.ownerFilterActive) return true;
      if (widget.ownerMatches(l.parent!)) return true;
      return l.children.any(widget.ownerMatches);
    }).toList();
    final visibleUngrouped = widget.ownerFilterActive
        ? ungroupedActions.where(widget.ownerMatches).toList()
        : ungroupedActions;

    final lanes = <_LaneSpec>[
      ...visibleParentLanes,
      if (visibleUngrouped.isNotEmpty || parentLanes.isEmpty)
        _LaneSpec.ungrouped(visibleUngrouped),
    ];

    // Below ~900px (journal dock / narrow window) the four status
    // columns become unusably thin and their cards overflow — scroll
    // the board horizontally at a workable width instead.
    return MinWidthHScroll(
      minWidth: 900,
      child: Column(
      children: [
        _ColumnHeaderRow(),
        const Divider(color: KColors.border, height: 1),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < lanes.length; i++) ...[
                  _Swimlane(
                    spec: lanes[i],
                    childrenByParent: part.childrenByParent,
                    catMap: widget.catMap,
                    planTagMap: widget.planTagMap,
                    db: widget.db,
                    projectId: widget.projectId,
                    ownerMatches: widget.ownerMatches,
                    ownerFilterActive: widget.ownerFilterActive,
                    pendingOutcomeId: _pendingOutcomeId,
                    outcomeCtrl: _outcomeCtrl,
                    outcomeFocus: _outcomeFocus,
                    onDrop: _drop,
                    onNest: _nestUnderCard,
                    onToggleSubTask: _toggleSubTask,
                    onCloseGroup: _closeGroup,
                    onSaveOutcome: _saveOutcome,
                    onDismissOutcome: _dismissOutcome,
                    onCardTap: _openCard,
                    onDelete: _deleteAction,
                    onDeleteSeries: _deleteSeries,
                  ),
                  if (i < lanes.length - 1)
                    const Divider(color: KColors.border, height: 1),
                ],
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lane spec
// ---------------------------------------------------------------------------

class _LaneSpec {
  final ProjectAction? parent; // null for ungrouped
  final List<ProjectAction> children;

  const _LaneSpec({this.parent, required this.children});

  factory _LaneSpec.forParent(ProjectAction parent, List<ProjectAction> kids) =>
      _LaneSpec(parent: parent, children: kids);

  factory _LaneSpec.ungrouped(List<ProjectAction> actions) =>
      _LaneSpec(parent: null, children: actions);

  bool get isUngrouped => parent == null;
  String? get parentId => parent?.id;
}

// ---------------------------------------------------------------------------
// Column header row (sticky at top of board)
// ---------------------------------------------------------------------------

class _ColumnHeaderRow extends StatelessWidget {
  Color _colorFor(_Col col) => switch (col) {
        _Col.overdue => KColors.red,
        _Col.done => KColors.textMuted,
        _ => KColors.textDim,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: KColors.surface,
      child: Row(
        children: [
          const SizedBox(width: _kLaneHeaderWidth),
          for (final col in _Col.values)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: KColors.border, width: 1),
                  ),
                ),
                child: Text(
                  col.label.toUpperCase(),
                  style: TextStyle(
                    color: _colorFor(col),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.15,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Swimlane (one row: header tile + 4 status cells)
// ---------------------------------------------------------------------------

class _Swimlane extends StatelessWidget {
  final _LaneSpec spec;
  final Map<String, List<ProjectAction>> childrenByParent;
  final Map<String, ActionCategory> catMap;
  final Map<String, String> planTagMap;
  final AppDatabase db;
  final String projectId;
  final bool Function(ProjectAction) ownerMatches;
  final bool ownerFilterActive;
  final String? pendingOutcomeId;
  final TextEditingController outcomeCtrl;
  final FocusNode outcomeFocus;
  final Future<void> Function(ProjectAction, _Col, String?) onDrop;
  final Future<void> Function(ProjectAction, ProjectAction) onNest;
  final Future<void> Function(ProjectAction, bool) onToggleSubTask;
  final Future<void> Function(ProjectAction) onCloseGroup;
  final Future<void> Function(ProjectAction) onSaveOutcome;
  final VoidCallback onDismissOutcome;
  final void Function(ProjectAction) onCardTap;
  final Future<void> Function(ProjectAction) onDelete;
  final Future<void> Function(ProjectAction) onDeleteSeries;

  const _Swimlane({
    required this.spec,
    required this.childrenByParent,
    required this.catMap,
    required this.planTagMap,
    required this.db,
    required this.projectId,
    required this.ownerMatches,
    required this.ownerFilterActive,
    required this.pendingOutcomeId,
    required this.outcomeCtrl,
    required this.outcomeFocus,
    required this.onDrop,
    required this.onNest,
    required this.onToggleSubTask,
    required this.onCloseGroup,
    required this.onSaveOutcome,
    required this.onDismissOutcome,
    required this.onCardTap,
    required this.onDelete,
    required this.onDeleteSeries,
  });

  @override
  Widget build(BuildContext context) {
    final visibleChildren = ownerFilterActive
        ? spec.children.where(ownerMatches).toList()
        : spec.children;
    final byCol = {for (final c in _Col.values) c: <ProjectAction>[]};
    for (final a in visibleChildren) {
      byCol[_colFor(a)]!.add(a);
    }

    // Rollup counts the whole subtree, sub-tasks included.
    final rollupActions = spec.isUngrouped
        ? spec.children
        : [
            ...spec.children,
            for (final c in spec.children)
              ...childrenByParent[c.id] ?? const <ProjectAction>[],
          ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _kLaneHeaderWidth,
            child: spec.isUngrouped
                ? const _UngroupedHeader()
                : _ParentHeader(
                    parent: spec.parent!,
                    rollup: rollupFor(rollupActions),
                    onTap: () => onCardTap(spec.parent!),
                    onCloseGroup: () => onCloseGroup(spec.parent!),
                  ),
          ),
          for (final col in _Col.values)
            Expanded(
              child: _LaneCell(
                col: col,
                actions: _sorted(byCol[col]!),
                childrenByParent: childrenByParent,
                catMap: catMap,
                planTagMap: planTagMap,
                pendingOutcomeId: pendingOutcomeId,
                outcomeCtrl: outcomeCtrl,
                outcomeFocus: outcomeFocus,
                onDrop: (a) => onDrop(a, col, spec.parentId),
                onNest: onNest,
                onToggleSubTask: onToggleSubTask,
                onSaveOutcome: onSaveOutcome,
                onDismissOutcome: onDismissOutcome,
                onCardTap: onCardTap,
                onDelete: onDelete,
                onDeleteSeries: onDeleteSeries,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Parent header tile (left of swimlane)
// ---------------------------------------------------------------------------

class _ParentHeader extends StatelessWidget {
  final ProjectAction parent;
  final GroupRollup rollup;
  final VoidCallback onTap;
  final VoidCallback onCloseGroup;

  const _ParentHeader({
    required this.parent,
    required this.rollup,
    required this.onTap,
    required this.onCloseGroup,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: KColors.phosphor.withValues(alpha: 0.55),
              width: 3,
            ),
            right: BorderSide(color: KColors.border, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_outlined,
                    size: 11, color: KColors.phosphor),
                const SizedBox(width: 5),
                if (parent.ref != null) ...[
                  Text(parent.ref!,
                      style: const TextStyle(
                          color: KColors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    '${rollup.done}/${rollup.total}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: KColors.textMuted, fontSize: 10),
                  ),
                ),
                const SizedBox(width: 2),
                _HeaderMenuButton(onCloseGroup: onCloseGroup),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              parent.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const Spacer(),
            if (parent.owner != null && parent.owner!.isNotEmpty)
              Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colorFromName(parent.owner!)
                          .withValues(alpha: 0.28),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorFromName(parent.owner!)
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initialsFromName(parent.owner!),
                      style: const TextStyle(
                        color: KColors.text,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      parent.owner!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: KColors.textDim, fontSize: 10),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderMenuButton extends StatelessWidget {
  final VoidCallback onCloseGroup;

  const _HeaderMenuButton({required this.onCloseGroup});

  Future<void> _showMenu(BuildContext context) async {
    final button = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final val = await showMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(
          value: 'close_group',
          height: 32,
          child: Text('Close group', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
    if (val == 'close_group') onCloseGroup();
  }

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: () => _showMenu(context),
      radius: 12,
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: Icon(Icons.more_vert, size: 13, color: KColors.textMuted),
      ),
    );
  }
}

class _UngroupedHeader extends StatelessWidget {
  const _UngroupedHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: KColors.border, width: 1),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: const Text(
        '— Ungrouped —',
        style: TextStyle(
          color: KColors.textMuted,
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cell (one status column within one swimlane)
// ---------------------------------------------------------------------------

class _LaneCell extends StatelessWidget {
  final _Col col;
  final List<ProjectAction> actions;
  final Map<String, List<ProjectAction>> childrenByParent;
  final Map<String, ActionCategory> catMap;
  final Map<String, String> planTagMap;
  final String? pendingOutcomeId;
  final TextEditingController outcomeCtrl;
  final FocusNode outcomeFocus;
  final Future<void> Function(ProjectAction) onDrop;
  final Future<void> Function(ProjectAction, ProjectAction) onNest;
  final Future<void> Function(ProjectAction, bool) onToggleSubTask;
  final Future<void> Function(ProjectAction) onSaveOutcome;
  final VoidCallback onDismissOutcome;
  final void Function(ProjectAction) onCardTap;
  final Future<void> Function(ProjectAction) onDelete;
  final Future<void> Function(ProjectAction) onDeleteSeries;

  const _LaneCell({
    required this.col,
    required this.actions,
    required this.childrenByParent,
    required this.catMap,
    required this.planTagMap,
    required this.pendingOutcomeId,
    required this.outcomeCtrl,
    required this.outcomeFocus,
    required this.onDrop,
    required this.onNest,
    required this.onToggleSubTask,
    required this.onSaveOutcome,
    required this.onDismissOutcome,
    required this.onCardTap,
    required this.onDelete,
    required this.onDeleteSeries,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<ProjectAction>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (ctx, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          decoration: BoxDecoration(
            color: hovering
                ? KColors.amber.withValues(alpha: 0.05)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: hovering ? KColors.amber : KColors.border,
                width: hovering ? 2 : 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _KanbanCard(
                  action: actions[i],
                  category: actions[i].categoryId != null
                      ? catMap[actions[i].categoryId!]
                      : null,
                  planTag: actions[i].planActivityId != null
                      ? planTagMap[actions[i].planActivityId!]
                      : null,
                  subTasks: childrenByParent[actions[i].id] ??
                      const <ProjectAction>[],
                  showOutcomeField: pendingOutcomeId == actions[i].id,
                  outcomeCtrl:
                      pendingOutcomeId == actions[i].id ? outcomeCtrl : null,
                  outcomeFocus:
                      pendingOutcomeId == actions[i].id ? outcomeFocus : null,
                  onTap: () => onCardTap(actions[i]),
                  onNest: onNest,
                  onToggleSubTask: onToggleSubTask,
                  onSaveOutcome: () => onSaveOutcome(actions[i]),
                  onDismissOutcome: onDismissOutcome,
                  onDelete: () => onDelete(actions[i]),
                  onDeleteSeries: () => onDeleteSeries(actions[i]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

class _KanbanCard extends StatelessWidget {
  final ProjectAction action;
  final ActionCategory? category;
  final String? planTag;
  final List<ProjectAction> subTasks;
  final bool showOutcomeField;
  final TextEditingController? outcomeCtrl;
  final FocusNode? outcomeFocus;
  final VoidCallback onTap;
  final Future<void> Function(ProjectAction, ProjectAction) onNest;
  final Future<void> Function(ProjectAction, bool) onToggleSubTask;
  final VoidCallback onSaveOutcome;
  final VoidCallback onDismissOutcome;
  final VoidCallback onDelete;
  final VoidCallback onDeleteSeries;

  const _KanbanCard({
    required this.action,
    required this.category,
    this.planTag,
    this.subTasks = const [],
    required this.showOutcomeField,
    required this.outcomeCtrl,
    required this.outcomeFocus,
    required this.onTap,
    required this.onNest,
    required this.onToggleSubTask,
    required this.onSaveOutcome,
    required this.onDismissOutcome,
    required this.onDelete,
    required this.onDeleteSeries,
  });

  Widget _buildCardContent({bool nestHover = false}) {
    final barColor =
        category != null ? parseHexColor(category!.color) : KColors.border2;

    return Container(
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(
          color: nestHover ? KColors.phosphor : KColors.border2,
          width: nestHover ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 3,
                    height: 12,
                    color: barColor,
                    margin: const EdgeInsets.only(right: 6),
                  ),
                  if (action.ref != null) ...[
                    Text(
                      action.ref!,
                      style: const TextStyle(
                        color: KColors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Spacer(),
                  SourceBadge(source: action.source),
                  const SizedBox(width: 2),
                  _CardMenuButton(
                    hasSeries: action.recurrenceGroupId != null,
                    onDelete: onDelete,
                    onDeleteSeries: onDeleteSeries,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                action.description,
                style: const TextStyle(
                  color: KColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (action.owner != null && action.owner!.isNotEmpty) ...[
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: colorFromName(action.owner!)
                            .withValues(alpha: 0.28),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorFromName(action.owner!)
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initialsFromName(action.owner!),
                        style: const TextStyle(
                          color: KColors.text,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        action.owner!,
                        style: const TextStyle(
                            color: KColors.textDim, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (action.dueDate != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 9,
                          color: _dueDateColor(action.dueDate),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          du.formatDate(action.dueDate),
                          style: TextStyle(
                            color: _dueDateColor(action.dueDate),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (subTasks.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Divider(color: KColors.border, height: 1),
                const SizedBox(height: 4),
                for (final s in subTasks)
                  InkWell(
                    onTap: () =>
                        onToggleSubTask(s, s.status != 'closed'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            s.status == 'closed'
                                ? Icons.check_box_outlined
                                : Icons.check_box_outline_blank,
                            size: 12,
                            color: s.status == 'closed'
                                ? KColors.phosphor
                                : KColors.textDim,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              s.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: s.status == 'closed'
                                    ? KColors.textMuted
                                    : KColors.textDim,
                                decoration: s.status == 'closed'
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (planTag != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: KColors.phosphor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                        color: KColors.phosphor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_tree_outlined,
                          size: 9, color: KColors.phosphor),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          planTag!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: KColors.phosphor,
                              fontSize: 9,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (showOutcomeField && outcomeCtrl != null) ...[
                const SizedBox(height: 8),
                const Divider(color: KColors.border, height: 1),
                const SizedBox(height: 6),
                SizedBox(
                  height: 20,
                  child: TextField(
                    controller: outcomeCtrl,
                    focusNode: outcomeFocus,
                    style: const TextStyle(
                        color: KColors.text, fontSize: 11, height: 1.2),
                    decoration: const InputDecoration(
                      hintText: 'Add outcome… (Enter to save)',
                      hintStyle: TextStyle(
                          color: KColors.textMuted, fontSize: 11, height: 1.2),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => onSaveOutcome(),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: onDismissOutcome,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size.zero,
                        ),
                        child: const Text('Skip',
                            style: TextStyle(
                                color: KColors.textMuted, fontSize: 10)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: onSaveOutcome,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size.zero,
                        ),
                        child: const Text('Save',
                            style: TextStyle(
                                color: KColors.phosphor, fontSize: 10)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildCardContent();
    // Dropping another card onto this one nests it as a child/sub-task
    // (Jira-style); dropping on the empty cell area changes status only.
    return DragTarget<ProjectAction>(
      onWillAcceptWithDetails: (d) => d.data.id != action.id,
      onAcceptWithDetails: (d) => onNest(d.data, action),
      builder: (ctx, candidates, _) {
        final hover = candidates.isNotEmpty;
        final display =
            hover ? _buildCardContent(nestHover: true) : content;
        return Draggable<ProjectAction>(
          data: action,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 220,
              child: Opacity(
                opacity: 0.92,
                child: Transform.scale(scale: 1.03, child: content),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: content),
          child: display,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Card menu button (⋮ → Delete / Delete series)
// ---------------------------------------------------------------------------

class _CardMenuButton extends StatelessWidget {
  final bool hasSeries;
  final VoidCallback onDelete;
  final VoidCallback onDeleteSeries;

  const _CardMenuButton({
    required this.hasSeries,
    required this.onDelete,
    required this.onDeleteSeries,
  });

  Future<void> _showMenu(BuildContext context) async {
    final button = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final val = await showMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(
          value: 'delete',
          height: 32,
          child: Text('Delete', style: TextStyle(fontSize: 12)),
        ),
        if (hasSeries)
          const PopupMenuItem(
            value: 'delete_series',
            height: 32,
            child: Text('Delete all in series',
                style: TextStyle(fontSize: 12)),
          ),
      ],
    );
    if (val == 'delete') onDelete();
    if (val == 'delete_series') onDeleteSeries();
  }

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: () => _showMenu(context),
      radius: 12,
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: Icon(Icons.more_vert, size: 14, color: KColors.textMuted),
      ),
    );
  }
}
