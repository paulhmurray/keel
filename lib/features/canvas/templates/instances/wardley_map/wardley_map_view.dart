import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/database/database.dart';
import '../../../../../shared/theme/keel_colors.dart';
import 'wardley_map_model.dart';
import 'wardley_map_painter.dart';

/// Interactive Wardley map: components positioned on a value-chain
/// (Y, top = visible to user) × evolution (X, Genesis → Commodity) grid,
/// draggable, with directed dependency links. Every mutation persists
/// immediately to the template's `content` JSON.
class WardleyMapView extends StatefulWidget {
  final CanvasTemplate template;
  const WardleyMapView({super.key, required this.template});

  @override
  State<WardleyMapView> createState() => _WardleyMapViewState();
}

class _WardleyMapViewState extends State<WardleyMapView> {
  late WardleyMapContent _content;
  String? _selectedId;
  // Link mode: tap a source component, then a target, to create an edge.
  bool _linkMode = false;
  String? _linkSourceId;

  @override
  void initState() {
    super.initState();
    _content = WardleyMapContent.decode(widget.template.content);
  }

  @override
  void didUpdateWidget(covariant WardleyMapView old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id) {
      _content = WardleyMapContent.decode(widget.template.content);
      setState(() {
        _selectedId = null;
        _linkMode = false;
        _linkSourceId = null;
      });
    }
  }

  WardleyComponent? get _selected => _selectedId == null
      ? null
      : _content.components
          .cast<WardleyComponent?>()
          .firstWhere((c) => c!.id == _selectedId, orElse: () => null);

  Future<void> _save(WardleyMapContent next) async {
    setState(() => _content = next);
    final db = context.read<AppDatabase>();
    await db.canvasTemplatesDao.patchTemplate(
      widget.template.id,
      CanvasTemplatesCompanion(content: Value(next.encode())),
    );
  }

  // ── Mutations ───────────────────────────────────────────────────────────
  void _addComponent(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final comp = WardleyComponent(
      id: const Uuid().v4(),
      name: trimmed,
      positionX: 0.28,
      positionY: 0.3,
    );
    _save(_content.copyWith(components: [..._content.components, comp]));
    _select(comp.id);
  }

  void _moveComponent(String id, double x, double y) {
    _save(_content.copyWith(
      components: _content.components
          .map((c) => c.id == id ? c.copyWith(positionX: x, positionY: y) : c)
          .toList(),
    ));
  }

  void _renameComponent(String id, String name) {
    if (name.trim().isEmpty) return;
    _save(_content.copyWith(
      components: _content.components
          .map((c) => c.id == id ? c.copyWith(name: name.trim()) : c)
          .toList(),
    ));
  }

  void _updateNotes(String id, String? notes) {
    _save(_content.copyWith(
      components: _content.components
          .map((c) => c.id == id ? c.copyWith(notes: notes) : c)
          .toList(),
    ));
  }

  void _removeComponent(String id) {
    _save(_content.copyWith(
      components: _content.components.where((c) => c.id != id).toList(),
      dependencies: _content.dependencies
          .where((d) => d.fromComponentId != id && d.toComponentId != id)
          .toList(),
    ));
    if (_selectedId == id) _clearSelection();
  }

  void _removeDependency(String depId) {
    _save(_content.copyWith(
      dependencies:
          _content.dependencies.where((d) => d.id != depId).toList(),
    ));
  }

  void _onComponentTapped(String id) {
    if (_linkMode) {
      if (_linkSourceId == null) {
        setState(() => _linkSourceId = id);
        return;
      }
      if (_linkSourceId == id) {
        setState(() => _linkSourceId = null); // tapped source again → cancel
        return;
      }
      final from = _linkSourceId!;
      final already = _content.dependencies.any((d) =>
          (d.fromComponentId == from && d.toComponentId == id) ||
          (d.fromComponentId == id && d.toComponentId == from));
      if (!already) {
        _save(_content.copyWith(dependencies: [
          ..._content.dependencies,
          WardleyDependency(
              id: const Uuid().v4(), fromComponentId: from, toComponentId: id),
        ]));
      }
      setState(() => _linkSourceId = null); // ready to chain another link
      return;
    }
    _select(id);
  }

  void _select(String id) => setState(() => _selectedId = id);

  void _clearSelection() {
    if (mounted) setState(() => _selectedId = null);
  }

  Future<void> _promptAdd() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddComponentDialog(),
    );
    if (name != null && name.trim().isNotEmpty) _addComponent(name);
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _toolbar(),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _grid()),
              if (_selected != null)
                _ComponentDetailsPanel(
                  // Keyed by id so switching selection remounts the panel
                  // (fresh controllers) instead of us disposing them by hand.
                  key: ValueKey(_selected!.id),
                  component: _selected!,
                  components: _content.components,
                  dependencies: _content.dependencies,
                  onRename: (v) => _renameComponent(_selected!.id, v),
                  onNotesChanged: (v) => _updateNotes(
                      _selected!.id, v.trim().isEmpty ? null : v),
                  onRemoveDependency: _removeDependency,
                  onRemove: () => _removeComponent(_selected!.id),
                  onClose: _clearSelection,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: KColors.border)),
      ),
      child: Row(children: [
        const Text('WARDLEY MAP',
            style: TextStyle(
                color: KColors.amber,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4)),
        const Spacer(),
        if (_linkMode)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
                _linkSourceId == null
                    ? 'Tap a component, then the thing it needs'
                    : 'Now tap its dependency (tap it again to cancel)',
                style: const TextStyle(
                    color: KColors.textDim, fontSize: 11)),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _linkMode = !_linkMode;
            _linkSourceId = null;
          }),
          icon: Icon(_linkMode ? Icons.done : Icons.timeline, size: 14),
          label: Text(_linkMode ? 'Done linking' : 'Link'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _linkMode ? KColors.bg : KColors.amber,
            backgroundColor: _linkMode ? KColors.amber : null,
            side: const BorderSide(color: KColors.amber),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: const TextStyle(fontSize: 12),
            minimumSize: const Size(0, 30),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _promptAdd,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Component'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: const TextStyle(fontSize: 12),
            minimumSize: const Size(0, 30),
          ),
        ),
      ]),
    );
  }

  Widget _grid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 16, 16, 34),
      child: LayoutBuilder(builder: (context, cons) {
        final w = cons.maxWidth;
        final h = cons.maxHeight;
        return Stack(clipBehavior: Clip.none, children: [
          // Backdrop + dividers.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: KColors.surface,
                border: Border.all(color: KColors.border),
              ),
              child: const CustomPaint(painter: WardleyGridPainter()),
            ),
          ),
          // Tapping empty space clears the selection / pending link.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (_linkSourceId != null) {
                  setState(() => _linkSourceId = null);
                } else if (_selectedId != null) {
                  _clearSelection();
                }
              },
            ),
          ),
          // Dependency edges (behind nodes).
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: WardleyDependencyPainter(
                  components: _content.components,
                  dependencies: _content.dependencies,
                  highlightId: _selectedId ?? _linkSourceId,
                ),
              ),
            ),
          ),
          // Nodes.
          for (final c in _content.components)
            _ComponentNode(
              key: ValueKey(c.id),
              component: c,
              gridW: w,
              gridH: h,
              selected: _selectedId == c.id,
              isLinkSource: _linkSourceId == c.id,
              linkMode: _linkMode,
              onTap: () => _onComponentTapped(c.id),
              onMove: (x, y) => _moveComponent(c.id, x, y),
            ),
          // Empty-state hint.
          if (_content.components.isEmpty)
            const Center(
              child: Text(
                'Add components, drag them to position, then use Link to\n'
                'connect what needs what.',
                textAlign: TextAlign.center,
                style: TextStyle(color: KColors.textMuted, fontSize: 12),
              ),
            ),
          // Axis labels.
          ..._axisLabels(),
        ]);
      }),
    );
  }

  List<Widget> _axisLabels() {
    const stageStyle = TextStyle(
        color: KColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5);
    const stages = ['GENESIS', 'CUSTOM-BUILT', 'PRODUCT', 'COMMODITY'];
    return [
      // Evolution stage labels along the bottom.
      Positioned(
        left: 0,
        right: 0,
        bottom: -22,
        child: Row(
          children: [
            for (final s in stages)
              Expanded(
                  child: Text(s, textAlign: TextAlign.center, style: stageStyle)),
          ],
        ),
      ),
      // Value-chain (visibility) axis on the left.
      const Positioned(
        left: -40,
        top: 0,
        child: RotatedBox(
          quarterTurns: 3,
          child: Text('◀ visible          value chain          invisible ▶',
              style: stageStyle),
        ),
      ),
    ];
  }

}

/// Right-hand detail panel for the selected component. A StatefulWidget
/// that OWNS its name/notes controllers (created in initState, disposed in
/// dispose), keyed by component id in the parent so switching selection
/// remounts it cleanly — no manual controller disposal, no
/// used-after-dispose races.
class _ComponentDetailsPanel extends StatefulWidget {
  final WardleyComponent component;
  final List<WardleyComponent> components;
  final List<WardleyDependency> dependencies;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onNotesChanged;
  final ValueChanged<String> onRemoveDependency;
  final VoidCallback onRemove;
  final VoidCallback onClose;

  const _ComponentDetailsPanel({
    super.key,
    required this.component,
    required this.components,
    required this.dependencies,
    required this.onRename,
    required this.onNotesChanged,
    required this.onRemoveDependency,
    required this.onRemove,
    required this.onClose,
  });

  @override
  State<_ComponentDetailsPanel> createState() =>
      _ComponentDetailsPanelState();
}

class _ComponentDetailsPanelState extends State<_ComponentDetailsPanel> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.component.name);
  late final TextEditingController _notesCtrl =
      TextEditingController(text: widget.component.notes ?? '');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _stage(double x) => x < 0.25
      ? 'Genesis'
      : x < 0.5
          ? 'Custom-built'
          : x < 0.75
              ? 'Product'
              : 'Commodity';

  @override
  Widget build(BuildContext context) {
    final comp = widget.component;
    final deps = widget.dependencies
        .where((d) =>
            d.fromComponentId == comp.id || d.toComponentId == comp.id)
        .toList();
    final byId = {for (final c in widget.components) c.id: c};

    return Container(
      width: 288,
      decoration: const BoxDecoration(
        color: KColors.surface,
        border: Border(left: BorderSide(color: KColors.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: KColors.border)),
          ),
          child: Row(children: [
            const Text('COMPONENT',
                style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4)),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 16, color: KColors.textDim),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
            children: [
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(
                    color: KColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
                decoration: const InputDecoration(
                    isDense: true, labelText: 'Name'),
                onChanged: widget.onRename,
              ),
              const SizedBox(height: 10),
              Text('Evolution: ${_stage(comp.positionX)}  ·  '
                  'visibility ${((1 - comp.positionY) * 100).round()}%',
                  style:
                      const TextStyle(color: KColors.textMuted, fontSize: 11)),
              const SizedBox(height: 14),
              const Text('NOTES',
                  style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4)),
              const SizedBox(height: 6),
              TextField(
                controller: _notesCtrl,
                minLines: 3,
                maxLines: 6,
                style: const TextStyle(
                    color: KColors.text, fontSize: 12.5, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'Why it sits here, evolution pressure…',
                  isDense: true,
                  contentPadding: const EdgeInsets.all(8),
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onChanged: widget.onNotesChanged,
              ),
              const SizedBox(height: 16),
              if (deps.isNotEmpty) ...[
                const Text('DEPENDENCIES',
                    style: TextStyle(
                        color: KColors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4)),
                const SizedBox(height: 6),
                for (final d in deps)
                  _DepRow(
                    label: d.fromComponentId == comp.id
                        ? 'needs ${byId[d.toComponentId]?.name ?? '?'}'
                        : 'needed by ${byId[d.fromComponentId]?.name ?? '?'}',
                    onRemove: () => widget.onRemoveDependency(d.id),
                  ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('Remove component'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KColors.red,
                  side: const BorderSide(color: KColors.red),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _DepRow extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _DepRow({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: KColors.textDim, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
        InkWell(
          onTap: onRemove,
          child: const Padding(
            padding: EdgeInsets.all(2),
            child: Icon(Icons.close, size: 13, color: KColors.textMuted),
          ),
        ),
      ]),
    );
  }
}

/// A draggable component node: a dot at its fractional point with the name
/// to the right. Drag updates the fractional position; tap dispatches to
/// select / link depending on mode.
class _ComponentNode extends StatefulWidget {
  final WardleyComponent component;
  final double gridW;
  final double gridH;
  final bool selected;
  final bool isLinkSource;
  final bool linkMode;
  final VoidCallback onTap;
  final void Function(double x, double y) onMove;

  const _ComponentNode({
    required super.key,
    required this.component,
    required this.gridW,
    required this.gridH,
    required this.selected,
    required this.isLinkSource,
    required this.linkMode,
    required this.onTap,
    required this.onMove,
  });

  @override
  State<_ComponentNode> createState() => _ComponentNodeState();
}

class _ComponentNodeState extends State<_ComponentNode> {
  double? _px;
  double? _py;

  double get _x => _px ?? widget.component.positionX;
  double get _y => _py ?? widget.component.positionY;

  @override
  Widget build(BuildContext context) {
    const dot = 14.0;
    final active = widget.selected || widget.isLinkSource;
    final ring = widget.isLinkSource
        ? KColors.phosphor
        : widget.selected
            ? KColors.text
            : KColors.amber;

    return Positioned(
      left: _x * widget.gridW - dot / 2,
      top: _y * widget.gridH - dot / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // Drag always moves the component; a tap (within the gesture slop)
        // still selects / links. So link mode never freezes movement —
        // you can reposition and connect in the same session.
        onPanUpdate: (d) {
          if (widget.gridW <= 0 || widget.gridH <= 0) return;
          setState(() {
            _px = (_x + d.delta.dx / widget.gridW).clamp(0.0, 1.0);
            _py = (_y + d.delta.dy / widget.gridH).clamp(0.0, 1.0);
          });
        },
        onPanEnd: (_) {
          final x = _px, y = _py;
          setState(() {
            _px = null;
            _py = null;
          });
          if (x != null && y != null) widget.onMove(x, y);
        },
        child: MouseRegion(
          cursor: widget.linkMode
              ? SystemMouseCursors.click
              : SystemMouseCursors.grab,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: active ? ring : KColors.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 2),
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                widget.component.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.selected ? KColors.text : KColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Add-component dialog that owns its own controller (disposed on unmount,
/// after the route's exit animation finishes) so it never rebuilds against
/// a disposed controller.
class _AddComponentDialog extends StatefulWidget {
  const _AddComponentDialog();

  @override
  State<_AddComponentDialog> createState() => _AddComponentDialogState();
}

class _AddComponentDialogState extends State<_AddComponentDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KColors.surface,
      title: const Text('Add component',
          style: TextStyle(color: KColors.text, fontSize: 15)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        style: const TextStyle(color: KColors.text),
        decoration:
            const InputDecoration(hintText: 'e.g. Website, Auth, CDN'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: KColors.textDim))),
        ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_ctrl.text),
            child: const Text('Add')),
      ],
    );
  }
}
