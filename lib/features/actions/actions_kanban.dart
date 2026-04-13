import 'package:flutter/material.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import '../../shared/widgets/source_badge.dart';
import '../../shared/utils/date_utils.dart' as du;
import '../timeline/timeline_chart.dart' show parseHexColor;
import 'action_form.dart';

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

// ---------------------------------------------------------------------------
// Column assignment logic
// ---------------------------------------------------------------------------

_Col _colFor(ProjectAction a) {
  if (a.status == 'closed') return _Col.done;
  final today = DateTime.now().toIso8601String().substring(0, 10);
  // Auto-promote to overdue if past due and not done
  if (a.dueDate != null && a.dueDate!.compareTo(today) < 0) return _Col.overdue;
  // Explicit overdue flag set by user
  if (a.status == 'overdue') return _Col.overdue;
  if (a.status == 'in progress') return _Col.inProgress;
  return _Col.todo;
}

// Due soonest first; undated at bottom
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
// ActionsKanban
// ---------------------------------------------------------------------------

class ActionsKanban extends StatefulWidget {
  final List<ProjectAction> actions;
  final Map<String, ActionCategory> catMap;
  final AppDatabase db;
  final String projectId;

  const ActionsKanban({
    super.key,
    required this.actions,
    required this.catMap,
    required this.db,
    required this.projectId,
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

  Future<void> _drop(ProjectAction action, _Col targetCol) async {
    if (_colFor(action) == targetCol) return;

    if (targetCol == _Col.done) {
      await widget.db.actionsDao.upsertAction(ProjectActionsCompanion(
        id: Value(action.id),
        projectId: Value(action.projectId),
        description: Value(action.description),
        status: const Value('closed'),
        updatedAt: Value(DateTime.now()),
      ));
      setState(() {
        _pendingOutcomeId = action.id;
        _outcomeCtrl.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _outcomeFocus.requestFocus();
      });
    } else {
      await widget.db.actionsDao.upsertAction(ProjectActionsCompanion(
        id: Value(action.id),
        projectId: Value(action.projectId),
        description: Value(action.description),
        status: Value(targetCol.dbStatus),
        updatedAt: Value(DateTime.now()),
      ));
    }
  }

  Future<void> _saveOutcome(ProjectAction action) async {
    final outcome = _outcomeCtrl.text.trim();
    await widget.db.actionsDao.upsertAction(ProjectActionsCompanion(
      id: Value(action.id),
      projectId: Value(action.projectId),
      description: Value(action.description),
      status: const Value('closed'),
      outcome: Value(outcome.isEmpty ? null : outcome),
      updatedAt: Value(DateTime.now()),
    ));
    if (mounted) setState(() => _pendingOutcomeId = null);
  }

  void _dismissOutcome() => setState(() => _pendingOutcomeId = null);

  @override
  Widget build(BuildContext context) {
    final grouped = {for (final c in _Col.values) c: <ProjectAction>[]};
    for (final a in widget.actions) {
      grouped[_colFor(a)]!.add(a);
    }
    final sorted = {
      for (final c in _Col.values) c: _sorted(grouped[c]!)
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _Col.values.map((col) {
        final isLast = col == _Col.done;
        return _KanbanColumn(
          col: col,
          actions: sorted[col]!,
          catMap: widget.catMap,
          db: widget.db,
          projectId: widget.projectId,
          pendingOutcomeId: _pendingOutcomeId,
          outcomeCtrl: _outcomeCtrl,
          outcomeFocus: _outcomeFocus,
          onDrop: (a) => _drop(a, col),
          onSaveOutcome: _saveOutcome,
          onDismissOutcome: _dismissOutcome,
          showDivider: !isLast,
          onCardTap: (a) => showDialog(
            context: context,
            builder: (_) => ActionFormDialog(
              projectId: widget.projectId,
              db: widget.db,
              action: a,
              startInViewMode: true,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Column
// ---------------------------------------------------------------------------

class _KanbanColumn extends StatelessWidget {
  final _Col col;
  final List<ProjectAction> actions;
  final Map<String, ActionCategory> catMap;
  final AppDatabase db;
  final String projectId;
  final String? pendingOutcomeId;
  final TextEditingController outcomeCtrl;
  final FocusNode outcomeFocus;
  final Future<void> Function(ProjectAction) onDrop;
  final Future<void> Function(ProjectAction) onSaveOutcome;
  final VoidCallback onDismissOutcome;
  final void Function(ProjectAction) onCardTap;
  final bool showDivider;

  const _KanbanColumn({
    required this.col,
    required this.actions,
    required this.catMap,
    required this.db,
    required this.projectId,
    required this.pendingOutcomeId,
    required this.outcomeCtrl,
    required this.outcomeFocus,
    required this.onDrop,
    required this.onSaveOutcome,
    required this.onDismissOutcome,
    required this.onCardTap,
    required this.showDivider,
  });

  Color get _labelColor => switch (col) {
        _Col.overdue => KColors.red,
        _Col.done => KColors.textMuted,
        _ => KColors.textDim,
      };

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: col == _Col.done ? 0.6 : 1.0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Fixed header
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: KColors.border, width: 1)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          col.label.toUpperCase(),
                          style: TextStyle(
                            color: _labelColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.15,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _labelColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${actions.length}',
                            style: TextStyle(
                              color: _labelColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Scrollable DragTarget
                  Expanded(
                    child: DragTarget<ProjectAction>(
                      onWillAcceptWithDetails: (_) => true,
                      onAcceptWithDetails: (d) => onDrop(d.data),
                      builder: (ctx, candidates, _) {
                        final hovering = candidates.isNotEmpty;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          decoration: BoxDecoration(
                            color: hovering
                                ? KColors.amber.withValues(alpha: 0.04)
                                : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: hovering
                                    ? KColors.amber
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: actions.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.only(top: 24),
                                  child: Center(
                                    child: Text(
                                      'No actions',
                                      style: TextStyle(
                                        color: KColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                      6, 8, 6, 24),
                                  itemCount: actions.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (ctx, i) {
                                    final a = actions[i];
                                    final isPending =
                                        pendingOutcomeId == a.id;
                                    return _KanbanCard(
                                      action: a,
                                      category: a.categoryId != null
                                          ? catMap[a.categoryId!]
                                          : null,
                                      showOutcomeField: isPending,
                                      outcomeCtrl:
                                          isPending ? outcomeCtrl : null,
                                      outcomeFocus:
                                          isPending ? outcomeFocus : null,
                                      onTap: () => onCardTap(a),
                                      onSaveOutcome: () => onSaveOutcome(a),
                                      onDismissOutcome: onDismissOutcome,
                                    );
                                  },
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (showDivider)
              Container(width: 1, color: KColors.border),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

class _KanbanCard extends StatelessWidget {
  final ProjectAction action;
  final ActionCategory? category;
  final bool showOutcomeField;
  final TextEditingController? outcomeCtrl;
  final FocusNode? outcomeFocus;
  final VoidCallback onTap;
  final VoidCallback onSaveOutcome;
  final VoidCallback onDismissOutcome;

  const _KanbanCard({
    required this.action,
    required this.category,
    required this.showOutcomeField,
    required this.outcomeCtrl,
    required this.outcomeFocus,
    required this.onTap,
    required this.onSaveOutcome,
    required this.onDismissOutcome,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _buildCardContent() {
    final barColor =
        category != null ? parseHexColor(category!.color) : KColors.border2;

    return Container(
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(color: KColors.border2),
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
              // Top row: colour bar + ref + source badge
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
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Spacer(),
                  SourceBadge(source: action.source),
                ],
              ),
              const SizedBox(height: 6),
              // Description
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
              // Owner + due date
              Row(
                children: [
                  if (action.owner != null && action.owner!.isNotEmpty) ...[
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: KColors.amberDim,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          _initials(action.owner!),
                          style: const TextStyle(
                            color: KColors.amber,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
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
              // Inline outcome field (appears after dropping into Done)
              if (showOutcomeField && outcomeCtrl != null) ...[
                const SizedBox(height: 8),
                const Divider(color: KColors.border, height: 1),
                const SizedBox(height: 6),
                TextField(
                  controller: outcomeCtrl,
                  focusNode: outcomeFocus,
                  style: const TextStyle(color: KColors.text, fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: 'Add outcome… (Enter to save)',
                    hintStyle:
                        TextStyle(color: KColors.textMuted, fontSize: 11),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => onSaveOutcome(),
                ),
                const SizedBox(height: 4),
                Row(
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
      child: content,
    );
  }
}
