import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/database/database.dart';
import '../../../../../shared/theme/keel_colors.dart';
import 'swot_model.dart';

/// View for a single SWOT template instance.
///
/// 2×2 grid:
///   ┌──────────────┬──────────────┐
///   │ Strengths    │ Opportunities│
///   ├──────────────┼──────────────┤
///   │ Weaknesses   │ Threats      │
///   └──────────────┴──────────────┘
/// Plus Internal/External axis labels above the grid and Positive/
/// Negative labels down the left edge.
///
/// Items are inline-edit TextFields. Saves on every keystroke + on
/// every structural change (add / delete / drag-between-quadrants /
/// promote). Same save-on-every-edit pattern as the pre-mortem view.
class SwotView extends StatefulWidget {
  final CanvasTemplate template;

  const SwotView({super.key, required this.template});

  @override
  State<SwotView> createState() => _SwotViewState();
}

class _SwotViewState extends State<SwotView> {
  late SwotContent _content;
  // One controller per item id — preserves cursor across rebuilds.
  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _content = SwotContent.decode(widget.template.content);
    _seedControllers();
  }

  @override
  void didUpdateWidget(covariant SwotView old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id) {
      _content = SwotContent.decode(widget.template.content);
      _disposeControllers();
      _seedControllers();
    }
  }

  void _seedControllers() {
    for (final q in SwotQuadrant.all) {
      for (final item in _content.itemsFor(q)) {
        _ctrls.putIfAbsent(
            item.id, () => TextEditingController(text: item.text));
      }
    }
  }

  void _disposeControllers() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  // ---- Mutations ----------------------------------------------------------

  Future<void> _save(SwotContent next) async {
    setState(() => _content = next);
    final db = context.read<AppDatabase>();
    await db.canvasTemplatesDao.patchTemplate(
      widget.template.id,
      CanvasTemplatesCompanion(content: Value(next.encode())),
    );
  }

  void _addItem(String quadrant) {
    final id = const Uuid().v4();
    final list = [..._content.itemsFor(quadrant)];
    final item = SwotItem(id: id, sortOrder: list.length);
    list.add(item);
    _ctrls[id] = TextEditingController();
    _save(_content.withQuadrant(quadrant, list));
  }

  void _editItemText(String quadrant, String id, String text) {
    final updated = _content.itemsFor(quadrant).map((it) {
      return it.id == id ? it.copyWith(text: text) : it;
    }).toList();
    _save(_content.withQuadrant(quadrant, updated));
  }

  void _deleteItem(String quadrant, String id) {
    final filtered = _content
        .itemsFor(quadrant)
        .where((it) => it.id != id)
        .toList();
    final renumbered = [
      for (var i = 0; i < filtered.length; i++)
        filtered[i].copyWith(sortOrder: i),
    ];
    _ctrls.remove(id)?.dispose();
    _save(_content.withQuadrant(quadrant, renumbered));
  }

  /// Moves [id] from [sourceQuadrant] into [targetQuadrant] (at the end).
  /// No-op when source and target are the same.
  void _moveBetweenQuadrants({
    required String id,
    required String sourceQuadrant,
    required String targetQuadrant,
  }) {
    if (sourceQuadrant == targetQuadrant) return;
    final source = [..._content.itemsFor(sourceQuadrant)];
    final idx = source.indexWhere((it) => it.id == id);
    if (idx < 0) return;
    final moving = source.removeAt(idx);
    final renumberedSource = [
      for (var i = 0; i < source.length; i++)
        source[i].copyWith(sortOrder: i),
    ];
    final target = [..._content.itemsFor(targetQuadrant)];
    target.add(moving.copyWith(sortOrder: target.length));
    var next = _content.withQuadrant(sourceQuadrant, renumberedSource);
    next = next.withQuadrant(targetQuadrant, target);
    _save(next);
  }

  // ---- Promotion ----------------------------------------------------------

  Future<void> _promoteToRisk(String quadrant, SwotItem item) async {
    if (item.promotedToType != null || item.text.trim().isEmpty) return;
    final db = context.read<AppDatabase>();
    final newId = const Uuid().v4();
    await db.raidDao.insertRisk(RisksCompanion.insert(
      id: newId,
      projectId: widget.template.projectId,
      description: item.text,
      source: const Value('swot'),
      sourceNote: Value(
          'SWOT: ${widget.template.name} (${SwotQuadrant.label(quadrant)})'),
    ));
    _stampPromotion(quadrant, item.id, 'risk', newId);
    _snack('Promoted to Risk.');
  }

  Future<void> _promoteToAction(String quadrant, SwotItem item) async {
    if (item.promotedToType != null || item.text.trim().isEmpty) return;
    final db = context.read<AppDatabase>();
    final newId = const Uuid().v4();
    await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
      id: newId,
      projectId: widget.template.projectId,
      description: item.text,
      source: const Value('swot'),
      sourceNote: Value(
          'SWOT: ${widget.template.name} (${SwotQuadrant.label(quadrant)})'),
    ));
    _stampPromotion(quadrant, item.id, 'action', newId);
    _snack('Promoted to Action.');
  }

  void _stampPromotion(
      String quadrant, String itemId, String type, String newId) {
    final updated = _content.itemsFor(quadrant).map((it) {
      return it.id == itemId
          ? it.copyWith(promotedToType: type, promotedToId: newId)
          : it;
    }).toList();
    _save(_content.withQuadrant(quadrant, updated));
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          // Internal / External axis labels.
          Row(
            children: const [
              SizedBox(width: 36),
              Expanded(
                child: Center(
                  child: Text(
                    'INTERNAL',
                    style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'EXTERNAL',
                    style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AxisLabelV(text: 'POSITIVE\n / NEGATIVE'),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    children: [
                      // Top row: Strengths | Opportunities (both POSITIVE)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _Quadrant(
                                quadrant: SwotQuadrant.strengths,
                                items:
                                    _content.itemsFor(SwotQuadrant.strengths),
                                accent: KColors.phosphor,
                                ctrls: _ctrls,
                                onAdd: () =>
                                    _addItem(SwotQuadrant.strengths),
                                onTextChanged: (id, v) => _editItemText(
                                    SwotQuadrant.strengths, id, v),
                                onDelete: (id) =>
                                    _deleteItem(SwotQuadrant.strengths, id),
                                onPromoteToAction: (it) => _promoteToAction(
                                    SwotQuadrant.strengths, it),
                                onPromoteToRisk: null,
                                onDropFrom: (sourceQ, id) =>
                                    _moveBetweenQuadrants(
                                  id: id,
                                  sourceQuadrant: sourceQ,
                                  targetQuadrant: SwotQuadrant.strengths,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _Quadrant(
                                quadrant: SwotQuadrant.opportunities,
                                items: _content
                                    .itemsFor(SwotQuadrant.opportunities),
                                accent: KColors.blue,
                                ctrls: _ctrls,
                                onAdd: () =>
                                    _addItem(SwotQuadrant.opportunities),
                                onTextChanged: (id, v) => _editItemText(
                                    SwotQuadrant.opportunities, id, v),
                                onDelete: (id) => _deleteItem(
                                    SwotQuadrant.opportunities, id),
                                onPromoteToAction: (it) => _promoteToAction(
                                    SwotQuadrant.opportunities, it),
                                onPromoteToRisk: null,
                                onDropFrom: (sourceQ, id) =>
                                    _moveBetweenQuadrants(
                                  id: id,
                                  sourceQuadrant: sourceQ,
                                  targetQuadrant: SwotQuadrant.opportunities,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Bottom row: Weaknesses | Threats (both NEGATIVE)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _Quadrant(
                                quadrant: SwotQuadrant.weaknesses,
                                items: _content
                                    .itemsFor(SwotQuadrant.weaknesses),
                                accent: KColors.amber,
                                ctrls: _ctrls,
                                onAdd: () =>
                                    _addItem(SwotQuadrant.weaknesses),
                                onTextChanged: (id, v) => _editItemText(
                                    SwotQuadrant.weaknesses, id, v),
                                onDelete: (id) => _deleteItem(
                                    SwotQuadrant.weaknesses, id),
                                onPromoteToAction: (it) => _promoteToAction(
                                    SwotQuadrant.weaknesses, it),
                                onPromoteToRisk: (it) => _promoteToRisk(
                                    SwotQuadrant.weaknesses, it),
                                onDropFrom: (sourceQ, id) =>
                                    _moveBetweenQuadrants(
                                  id: id,
                                  sourceQuadrant: sourceQ,
                                  targetQuadrant: SwotQuadrant.weaknesses,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _Quadrant(
                                quadrant: SwotQuadrant.threats,
                                items:
                                    _content.itemsFor(SwotQuadrant.threats),
                                accent: KColors.red,
                                ctrls: _ctrls,
                                onAdd: () =>
                                    _addItem(SwotQuadrant.threats),
                                onTextChanged: (id, v) => _editItemText(
                                    SwotQuadrant.threats, id, v),
                                onDelete: (id) =>
                                    _deleteItem(SwotQuadrant.threats, id),
                                onPromoteToAction: (it) => _promoteToAction(
                                    SwotQuadrant.threats, it),
                                onPromoteToRisk: (it) =>
                                    _promoteToRisk(SwotQuadrant.threats, it),
                                onDropFrom: (sourceQ, id) =>
                                    _moveBetweenQuadrants(
                                  id: id,
                                  sourceQuadrant: sourceQ,
                                  targetQuadrant: SwotQuadrant.threats,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical "POSITIVE / NEGATIVE" rail down the left edge of the grid.
class _AxisLabelV extends StatelessWidget {
  final String text;
  const _AxisLabelV({required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      child: RotatedBox(
        quarterTurns: 3,
        child: Center(
          child: Text(
            'POSITIVE         NEGATIVE',
            style: const TextStyle(
              color: KColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag payload used to move SwotItems between quadrants.
class _SwotDragData {
  final String sourceQuadrant;
  final String itemId;

  const _SwotDragData(this.sourceQuadrant, this.itemId);
}

class _Quadrant extends StatelessWidget {
  final String quadrant;
  final List<SwotItem> items;
  final Color accent;
  final Map<String, TextEditingController> ctrls;
  final VoidCallback onAdd;
  final void Function(String id, String text) onTextChanged;
  final void Function(String id) onDelete;
  final void Function(SwotItem item) onPromoteToAction;
  final void Function(SwotItem item)? onPromoteToRisk;
  final void Function(String sourceQuadrant, String itemId) onDropFrom;

  const _Quadrant({
    required this.quadrant,
    required this.items,
    required this.accent,
    required this.ctrls,
    required this.onAdd,
    required this.onTextChanged,
    required this.onDelete,
    required this.onPromoteToAction,
    required this.onPromoteToRisk,
    required this.onDropFrom,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_SwotDragData>(
      onWillAcceptWithDetails: (d) => d.data.sourceQuadrant != quadrant,
      onAcceptWithDetails: (d) =>
          onDropFrom(d.data.sourceQuadrant, d.data.itemId),
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
              // Header bar with accent colour.
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  border: Border(
                    bottom: BorderSide(
                      color: accent.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      SwotQuadrant.label(quadrant).toUpperCase(),
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${items.length}',
                      style: TextStyle(
                        color: accent.withValues(alpha: 0.75),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                  children: [
                    ...items.map((item) {
                      return _SwotItemRow(
                        key: ValueKey(item.id),
                        quadrant: quadrant,
                        item: item,
                        ctrl: ctrls[item.id]!,
                        accent: accent,
                        onTextChanged: (v) => onTextChanged(item.id, v),
                        onDelete: () => onDelete(item.id),
                        onPromoteToAction: () => onPromoteToAction(item),
                        onPromoteToRisk:
                            onPromoteToRisk == null ? null : () => onPromoteToRisk!(item),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add, size: 13),
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
    );
  }
}

class _SwotItemRow extends StatelessWidget {
  final String quadrant;
  final SwotItem item;
  final TextEditingController ctrl;
  final Color accent;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onDelete;
  final VoidCallback onPromoteToAction;
  final VoidCallback? onPromoteToRisk;

  const _SwotItemRow({
    super.key,
    required this.quadrant,
    required this.item,
    required this.ctrl,
    required this.accent,
    required this.onTextChanged,
    required this.onDelete,
    required this.onPromoteToAction,
    required this.onPromoteToRisk,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Icon(Icons.drag_indicator,
                size: 12, color: KColors.textMuted),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: null,
              style: const TextStyle(
                color: KColors.text,
                fontSize: 12.5,
                height: 1.35,
              ),
              decoration: const InputDecoration(
                hintText: 'Add an item',
                hintStyle:
                    TextStyle(color: KColors.textMuted, fontSize: 12),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onTextChanged,
            ),
          ),
          if (item.promotedToType != null)
            Tooltip(
              message:
                  'Promoted to ${item.promotedToType == 'risk' ? 'Risk' : 'Action'}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  item.promotedToType == 'risk'
                      ? Icons.shield_outlined
                      : Icons.check_circle,
                  size: 12,
                  color: KColors.phosphor,
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Item actions',
            icon: const Icon(Icons.more_horiz,
                size: 14, color: KColors.textMuted),
            onSelected: (v) {
              switch (v) {
                case 'promote_action':
                  onPromoteToAction();
                  break;
                case 'promote_risk':
                  onPromoteToRisk?.call();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (_) => [
              if (item.promotedToType == null) ...[
                if (onPromoteToRisk != null)
                  const PopupMenuItem(
                      value: 'promote_risk',
                      child: Text('Promote to Risk')),
                const PopupMenuItem(
                    value: 'promote_action',
                    child: Text('Promote to Action')),
              ],
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );

    return LongPressDraggable<_SwotDragData>(
      data: _SwotDragData(quadrant, item.id),
      delay: const Duration(milliseconds: 200),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: KColors.surface,
            border: Border.all(color: accent, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            item.text.isEmpty ? '(blank)' : item.text,
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
      childWhenDragging: Opacity(opacity: 0.3, child: row),
      child: row,
    );
  }
}
