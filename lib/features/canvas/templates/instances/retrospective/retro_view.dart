import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/database/database.dart';
import '../../../../../shared/theme/keel_colors.dart';
import 'retro_model.dart';

/// View for a single Retrospective template instance.
///
/// Four columns side-by-side — Start / Stop / Continue / Learn. Each
/// item card has a title + optional notes + a vote button and a `⋯`
/// menu. Cards within a column sort by votes desc (ties by sort_order)
/// so the team can quickly see what to action.
class RetroView extends StatefulWidget {
  final CanvasTemplate template;

  const RetroView({super.key, required this.template});

  @override
  State<RetroView> createState() => _RetroViewState();
}

class _RetroViewState extends State<RetroView> {
  late RetroContent _content;
  // Per-item controllers, keyed by id, for both title and notes.
  final Map<String, TextEditingController> _titleCtrls = {};
  final Map<String, TextEditingController> _notesCtrls = {};

  @override
  void initState() {
    super.initState();
    _content = RetroContent.decode(widget.template.content);
    _seedControllers();
  }

  @override
  void didUpdateWidget(covariant RetroView old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id) {
      _content = RetroContent.decode(widget.template.content);
      _disposeControllers();
      _seedControllers();
    }
  }

  void _seedControllers() {
    for (final col in RetroColumn.all) {
      for (final item in _content.itemsFor(col)) {
        _titleCtrls.putIfAbsent(
            item.id, () => TextEditingController(text: item.title));
        _notesCtrls.putIfAbsent(item.id,
            () => TextEditingController(text: item.notes ?? ''));
      }
    }
  }

  void _disposeControllers() {
    for (final c in _titleCtrls.values) {
      c.dispose();
    }
    for (final c in _notesCtrls.values) {
      c.dispose();
    }
    _titleCtrls.clear();
    _notesCtrls.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  // ---- Mutations ----------------------------------------------------------

  Future<void> _save(RetroContent next) async {
    setState(() => _content = next);
    final db = context.read<AppDatabase>();
    await db.canvasTemplatesDao.patchTemplate(
      widget.template.id,
      CanvasTemplatesCompanion(content: Value(next.encode())),
    );
  }

  void _addItem(String column) {
    final id = const Uuid().v4();
    final list = [..._content.itemsFor(column)];
    final item = RetroItem(id: id, sortOrder: list.length);
    list.add(item);
    _titleCtrls[id] = TextEditingController();
    _notesCtrls[id] = TextEditingController();
    _save(_content.withColumn(column, list));
  }

  void _updateItem(String column, String id,
      RetroItem Function(RetroItem) edit) {
    final updated = _content
        .itemsFor(column)
        .map((it) => it.id == id ? edit(it) : it)
        .toList();
    _save(_content.withColumn(column, updated));
  }

  void _deleteItem(String column, String id) {
    final filtered =
        _content.itemsFor(column).where((it) => it.id != id).toList();
    final renumbered = [
      for (var i = 0; i < filtered.length; i++)
        filtered[i].copyWith(sortOrder: i),
    ];
    _titleCtrls.remove(id)?.dispose();
    _notesCtrls.remove(id)?.dispose();
    _save(_content.withColumn(column, renumbered));
  }

  void _voteUp(String column, String id) {
    _updateItem(column, id, (it) => it.copyWith(votes: it.votes + 1));
  }

  void _moveBetweenColumns({
    required String id,
    required String sourceColumn,
    required String targetColumn,
  }) {
    if (sourceColumn == targetColumn) return;
    final source = [..._content.itemsFor(sourceColumn)];
    final idx = source.indexWhere((it) => it.id == id);
    if (idx < 0) return;
    final moving = source.removeAt(idx);
    final renumberedSource = [
      for (var i = 0; i < source.length; i++)
        source[i].copyWith(sortOrder: i),
    ];
    final target = [..._content.itemsFor(targetColumn)];
    target.add(moving.copyWith(sortOrder: target.length));
    var next = _content.withColumn(sourceColumn, renumberedSource);
    next = next.withColumn(targetColumn, target);
    _save(next);
  }

  // ---- Promotion ----------------------------------------------------------

  Future<void> _promoteToAction(String column, RetroItem item) async {
    if (item.promotedToActionId != null) return;
    if (item.title.trim().isEmpty) {
      _snack('Add a title before promoting.');
      return;
    }
    final db = context.read<AppDatabase>();
    final newId = const Uuid().v4();
    final desc = item.notes != null && item.notes!.isNotEmpty
        ? '${item.title}\n\n${item.notes}'
        : item.title;
    await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
      id: newId,
      projectId: widget.template.projectId,
      description: desc,
      source: const Value('retrospective'),
      sourceNote: Value(
          'Retro: ${widget.template.name} (${RetroColumn.label(column)})'),
    ));
    _updateItem(column, item.id,
        (it) => it.copyWith(promotedToActionId: newId));
    _snack('Promoted to Action.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
    ));
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Column(
            column: RetroColumn.start,
            items: _content.itemsFor(RetroColumn.start),
            accent: KColors.phosphor,
            titleCtrls: _titleCtrls,
            notesCtrls: _notesCtrls,
            onAdd: () => _addItem(RetroColumn.start),
            onTitleChanged: (id, v) =>
                _updateItem(RetroColumn.start, id, (it) => it.copyWith(title: v)),
            onNotesChanged: (id, v) => _updateItem(
                RetroColumn.start,
                id,
                (it) => it.copyWith(notes: v.isEmpty ? null : v)),
            onVoteUp: (id) => _voteUp(RetroColumn.start, id),
            onDelete: (id) => _deleteItem(RetroColumn.start, id),
            onPromoteToAction: (it) =>
                _promoteToAction(RetroColumn.start, it),
            onDropFrom: (src, id) => _moveBetweenColumns(
              id: id,
              sourceColumn: src,
              targetColumn: RetroColumn.start,
            ),
          ),
          const SizedBox(width: 8),
          _Column(
            column: RetroColumn.stop,
            items: _content.itemsFor(RetroColumn.stop),
            accent: KColors.red,
            titleCtrls: _titleCtrls,
            notesCtrls: _notesCtrls,
            onAdd: () => _addItem(RetroColumn.stop),
            onTitleChanged: (id, v) =>
                _updateItem(RetroColumn.stop, id, (it) => it.copyWith(title: v)),
            onNotesChanged: (id, v) => _updateItem(
                RetroColumn.stop,
                id,
                (it) => it.copyWith(notes: v.isEmpty ? null : v)),
            onVoteUp: (id) => _voteUp(RetroColumn.stop, id),
            onDelete: (id) => _deleteItem(RetroColumn.stop, id),
            onPromoteToAction: null,
            onDropFrom: (src, id) => _moveBetweenColumns(
              id: id,
              sourceColumn: src,
              targetColumn: RetroColumn.stop,
            ),
          ),
          const SizedBox(width: 8),
          _Column(
            column: RetroColumn.cont,
            items: _content.itemsFor(RetroColumn.cont),
            accent: KColors.amber,
            titleCtrls: _titleCtrls,
            notesCtrls: _notesCtrls,
            onAdd: () => _addItem(RetroColumn.cont),
            onTitleChanged: (id, v) =>
                _updateItem(RetroColumn.cont, id, (it) => it.copyWith(title: v)),
            onNotesChanged: (id, v) => _updateItem(
                RetroColumn.cont,
                id,
                (it) => it.copyWith(notes: v.isEmpty ? null : v)),
            onVoteUp: (id) => _voteUp(RetroColumn.cont, id),
            onDelete: (id) => _deleteItem(RetroColumn.cont, id),
            onPromoteToAction: null,
            onDropFrom: (src, id) => _moveBetweenColumns(
              id: id,
              sourceColumn: src,
              targetColumn: RetroColumn.cont,
            ),
          ),
          const SizedBox(width: 8),
          _Column(
            column: RetroColumn.learn,
            items: _content.itemsFor(RetroColumn.learn),
            accent: KColors.blue,
            titleCtrls: _titleCtrls,
            notesCtrls: _notesCtrls,
            onAdd: () => _addItem(RetroColumn.learn),
            onTitleChanged: (id, v) =>
                _updateItem(RetroColumn.learn, id, (it) => it.copyWith(title: v)),
            onNotesChanged: (id, v) => _updateItem(
                RetroColumn.learn,
                id,
                (it) => it.copyWith(notes: v.isEmpty ? null : v)),
            onVoteUp: (id) => _voteUp(RetroColumn.learn, id),
            onDelete: (id) => _deleteItem(RetroColumn.learn, id),
            onPromoteToAction: null,
            onDropFrom: (src, id) => _moveBetweenColumns(
              id: id,
              sourceColumn: src,
              targetColumn: RetroColumn.learn,
            ),
          ),
        ],
      ),
    );
  }
}

/// Drag payload for moving retro items between columns.
class _RetroDragData {
  final String sourceColumn;
  final String itemId;

  const _RetroDragData(this.sourceColumn, this.itemId);
}

class _Column extends StatelessWidget {
  final String column;
  final List<RetroItem> items;
  final Color accent;
  final Map<String, TextEditingController> titleCtrls;
  final Map<String, TextEditingController> notesCtrls;
  final VoidCallback onAdd;
  final void Function(String id, String value) onTitleChanged;
  final void Function(String id, String value) onNotesChanged;
  final void Function(String id) onVoteUp;
  final void Function(String id) onDelete;
  final void Function(RetroItem item)? onPromoteToAction;
  final void Function(String sourceColumn, String id) onDropFrom;

  const _Column({
    required this.column,
    required this.items,
    required this.accent,
    required this.titleCtrls,
    required this.notesCtrls,
    required this.onAdd,
    required this.onTitleChanged,
    required this.onNotesChanged,
    required this.onVoteUp,
    required this.onDelete,
    required this.onPromoteToAction,
    required this.onDropFrom,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DragTarget<_RetroDragData>(
        onWillAcceptWithDetails: (d) => d.data.sourceColumn != column,
        onAcceptWithDetails: (d) =>
            onDropFrom(d.data.sourceColumn, d.data.itemId),
        builder: (context, candidate, _) {
          final hovering = candidate.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              color: KColors.surface,
              border: Border.all(
                color: hovering
                    ? KColors.amber.withValues(alpha: 0.55)
                    : KColors.border,
                width: hovering ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ColumnHeader(
                    column: column, accent: accent, count: items.length),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    children: [
                      for (final item in items)
                        _ItemCard(
                          key: ValueKey(item.id),
                          column: column,
                          item: item,
                          accent: accent,
                          titleCtrl: titleCtrls[item.id]!,
                          notesCtrl: notesCtrls[item.id]!,
                          onTitleChanged: (v) => onTitleChanged(item.id, v),
                          onNotesChanged: (v) => onNotesChanged(item.id, v),
                          onVoteUp: () => onVoteUp(item.id),
                          onDelete: () => onDelete(item.id),
                          onPromoteToAction: onPromoteToAction == null
                              ? null
                              : () => onPromoteToAction!(item),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: onAdd,
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add'),
                          style: TextButton.styleFrom(
                            foregroundColor: accent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6),
                            minimumSize: const Size(0, 28),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  final String column;
  final Color accent;
  final int count;

  const _ColumnHeader({
    required this.column,
    required this.accent,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  RetroColumn.label(column).toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                Text(
                  RetroColumn.subtitle(column),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KColors.textMuted,
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              color: accent.withValues(alpha: 0.75),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final String column;
  final RetroItem item;
  final Color accent;
  final TextEditingController titleCtrl;
  final TextEditingController notesCtrl;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onNotesChanged;
  final VoidCallback onVoteUp;
  final VoidCallback onDelete;
  final VoidCallback? onPromoteToAction;

  const _ItemCard({
    super.key,
    required this.column,
    required this.item,
    required this.accent,
    required this.titleCtrl,
    required this.notesCtrl,
    required this.onTitleChanged,
    required this.onNotesChanged,
    required this.onVoteUp,
    required this.onDelete,
    required this.onPromoteToAction,
  });

  @override
  Widget build(BuildContext context) {
    final isPromoted = item.promotedToActionId != null;
    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: KColors.surface2,
        border: Border.all(
          color: isPromoted
              ? KColors.phosphor.withValues(alpha: 0.5)
              : KColors.border,
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: titleCtrl,
                  maxLines: null,
                  style: const TextStyle(
                    color: KColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    hintStyle:
                        TextStyle(color: KColors.textMuted, fontSize: 12),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: onTitleChanged,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Item actions',
                icon: const Icon(Icons.more_horiz,
                    size: 14, color: KColors.textMuted),
                onSelected: (v) {
                  switch (v) {
                    case 'promote':
                      onPromoteToAction?.call();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (onPromoteToAction != null && !isPromoted)
                    const PopupMenuItem(
                        value: 'promote',
                        child: Text('Promote to Action')),
                  const PopupMenuItem(
                      value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          TextField(
            controller: notesCtrl,
            maxLines: null,
            style: const TextStyle(
              color: KColors.textDim,
              fontSize: 11.5,
              height: 1.35,
            ),
            decoration: const InputDecoration(
              hintText: 'Notes (optional)',
              hintStyle:
                  TextStyle(color: KColors.textMuted, fontSize: 11),
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: onNotesChanged,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              InkWell(
                onTap: onVoteUp,
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.votes > 0
                        ? accent.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: item.votes > 0
                          ? accent
                          : KColors.border,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.thumb_up_outlined,
                          size: 11,
                          color: item.votes > 0
                              ? accent
                              : KColors.textDim),
                      const SizedBox(width: 4),
                      Text(
                        '${item.votes}',
                        style: TextStyle(
                          color: item.votes > 0
                              ? accent
                              : KColors.textDim,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (isPromoted)
                Tooltip(
                  message: 'Promoted to Action',
                  child: Icon(Icons.check_circle,
                      size: 12, color: KColors.phosphor),
                ),
            ],
          ),
        ],
      ),
    );

    return LongPressDraggable<_RetroDragData>(
      data: _RetroDragData(column, item.id),
      delay: const Duration(milliseconds: 200),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: KColors.surface,
            border: Border.all(color: accent),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            item.title.isEmpty ? '(blank)' : item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }
}
