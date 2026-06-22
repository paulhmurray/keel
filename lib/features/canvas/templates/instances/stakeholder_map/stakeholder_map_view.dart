import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../../core/database/database.dart';
import '../../../../../shared/theme/keel_colors.dart';
import 'stakeholder_map_model.dart';

/// View for a single Stakeholder Map template.
///
/// Layout:
///   ┌────────────────────────────────────┬──────────┐
///   │ 2×2 grid with dots                 │ Side     │
///   │  HI                                │ panel    │
///   │  ┌──────────┬──────────┐           │ (when a  │
///   │  │ Keep Sat │ Manage   │           │  dot is  │
///   │  │          │ Closely  │           │  selected│
///   │  ├──────────┼──────────┤           │          │
///   │  │ Monitor  │ Keep     │           │          │
///   │  │          │ Informed │           │          │
///   │  └──────────┴──────────┘           │          │
///   │  LO         INTEREST →             │          │
///   │   ← LOW       HIGH                 │          │
///   │                                    │          │
///   │  [+ Add stakeholder]               │          │
///   └────────────────────────────────────┴──────────┘
class StakeholderMapView extends StatefulWidget {
  final CanvasTemplate template;

  const StakeholderMapView({super.key, required this.template});

  @override
  State<StakeholderMapView> createState() => _StakeholderMapViewState();
}

class _StakeholderMapViewState extends State<StakeholderMapView> {
  late StakeholderMapContent _content;

  /// id of the currently-selected dot (drives the side panel). null
  /// means no panel shown.
  String? _selectedDotId;

  /// Controller for the notes TextField in the side panel — keyed off
  /// the selected dot's id and reset when the selection changes.
  TextEditingController? _notesCtrl;

  /// Used to compute drag → fractional-position math.
  final _gridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _content = StakeholderMapContent.decode(widget.template.content);
  }

  @override
  void didUpdateWidget(covariant StakeholderMapView old) {
    super.didUpdateWidget(old);
    if (old.template.id != widget.template.id) {
      _content = StakeholderMapContent.decode(widget.template.content);
      _selectedDotId = null;
      _notesCtrl?.dispose();
      _notesCtrl = null;
    }
  }

  @override
  void dispose() {
    _notesCtrl?.dispose();
    super.dispose();
  }

  // ---- Mutations ----------------------------------------------------------

  Future<void> _save(StakeholderMapContent next) async {
    setState(() => _content = next);
    final db = context.read<AppDatabase>();
    await db.canvasTemplatesDao.patchTemplate(
      widget.template.id,
      CanvasTemplatesCompanion(content: Value(next.encode())),
    );
  }

  void _addPerson(Person person) {
    // Default to centre — analyst drags from there.
    final dot = StakeholderDot(
      id: const Uuid().v4(),
      personId: person.id,
    );
    _save(_content.copyWith(
      stakeholders: [..._content.stakeholders, dot],
    ));
  }

  void _moveDot(String id, double newX, double newY) {
    final updated = _content.stakeholders.map((d) {
      return d.id == id
          ? d.copyWith(positionX: newX, positionY: newY)
          : d;
    }).toList();
    _save(_content.copyWith(stakeholders: updated));
  }

  void _updateNotes(String id, String? notes) {
    final updated = _content.stakeholders.map((d) {
      return d.id == id ? d.copyWith(notes: notes) : d;
    }).toList();
    _save(_content.copyWith(stakeholders: updated));
  }

  void _removeDot(String id) {
    final updated =
        _content.stakeholders.where((d) => d.id != id).toList();
    if (_selectedDotId == id) {
      _selectedDotId = null;
      _notesCtrl?.dispose();
      _notesCtrl = null;
    }
    _save(_content.copyWith(stakeholders: updated));
  }

  void _selectDot(StakeholderDot dot) {
    setState(() {
      _selectedDotId = dot.id;
      _notesCtrl?.dispose();
      _notesCtrl = TextEditingController(text: dot.notes ?? '');
    });
  }

  void _closeSidePanel() {
    setState(() {
      _selectedDotId = null;
      _notesCtrl?.dispose();
      _notesCtrl = null;
    });
  }

  // ---- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return StreamBuilder<List<Person>>(
      stream: db.peopleDao.watchPersonsForProject(widget.template.projectId),
      builder: (context, snap) {
        final people = snap.data ?? const <Person>[];
        final personById = {for (final p in people) p.id: p};
        // Persons NOT yet placed — fuel for the Add dropdown.
        final placedIds =
            _content.stakeholders.map((d) => d.personId).toSet();
        final addable = people
            .where((p) => !placedIds.contains(p.id))
            .toList();
        final selected = _selectedDotId == null
            ? null
            : _content.stakeholders
                .where((d) => d.id == _selectedDotId)
                .cast<StakeholderDot?>()
                .firstOrNull;
        return Row(
          children: [
            Expanded(
              child: _GridArea(
                content: _content,
                personById: personById,
                addable: addable,
                gridKey: _gridKey,
                selectedDotId: _selectedDotId,
                onAddPerson: _addPerson,
                onSelectDot: _selectDot,
                onMoveDot: _moveDot,
              ),
            ),
            if (selected != null && _notesCtrl != null)
              _DetailsSidePanel(
                dot: selected,
                person: personById[selected.personId],
                notesCtrl: _notesCtrl!,
                onNotesChanged: (v) =>
                    _updateNotes(selected.id, v.isEmpty ? null : v),
                onRemove: () => _removeDot(selected.id),
                onClose: _closeSidePanel,
              ),
          ],
        );
      },
    );
  }
}

class _GridArea extends StatelessWidget {
  final StakeholderMapContent content;
  final Map<String, Person> personById;
  final List<Person> addable;
  final GlobalKey gridKey;
  final String? selectedDotId;
  final ValueChanged<Person> onAddPerson;
  final ValueChanged<StakeholderDot> onSelectDot;
  final void Function(String id, double x, double y) onMoveDot;

  const _GridArea({
    required this.content,
    required this.personById,
    required this.addable,
    required this.gridKey,
    required this.selectedDotId,
    required this.onAddPerson,
    required this.onSelectDot,
    required this.onMoveDot,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      child: Column(
        children: [
          // Top toolbar: Add button.
          Row(
            children: [
              const Text(
                'STAKEHOLDER MAP',
                style: TextStyle(
                  color: KColors.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${content.stakeholders.length} placed',
                style: const TextStyle(
                  color: KColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              _AddStakeholderButton(
                addable: addable,
                onSelected: onAddPerson,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Y-axis label rail.
                SizedBox(
                  width: 28,
                  child: Column(
                    children: const [
                      Expanded(
                        child: Center(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Text(
                              // Reads bottom-to-top after the 270°
                              // rotation, so "LOW" lands at the bottom
                              // and "HIGH" at the top — aligning with
                              // the conventional Mendelow layout where
                              // Manage Closely sits in the high-influence
                              // + high-interest corner.
                              'LOW INFLUENCE          HIGH INFLUENCE',
                              style: TextStyle(
                                color: KColors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 22),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _MapGrid(
                          gridKey: gridKey,
                          content: content,
                          personById: personById,
                          selectedDotId: selectedDotId,
                          onSelectDot: onSelectDot,
                          onMoveDot: onMoveDot,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // X-axis label row.
                      const Row(
                        children: [
                          Text(
                            'LOW INTEREST',
                            style: TextStyle(
                              color: KColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                          Spacer(),
                          Text(
                            'HIGH INTEREST',
                            style: TextStyle(
                              color: KColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
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

class _AddStakeholderButton extends StatelessWidget {
  final List<Person> addable;
  final ValueChanged<Person> onSelected;

  const _AddStakeholderButton({
    required this.addable,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = addable.isEmpty;
    return PopupMenuButton<String>(
      tooltip: disabled
          ? 'Every project person is already on the map'
          : 'Add stakeholder',
      enabled: !disabled,
      onSelected: (id) {
        final p = addable.firstWhere((x) => x.id == id);
        onSelected(p);
      },
      itemBuilder: (_) {
        return addable
            .map((p) => PopupMenuItem<String>(
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
                      if (p.role != null && p.role!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '· ${p.role}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: KColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ))
            .toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: disabled
              ? KColors.surface2
              : KColors.amberDim.withValues(alpha: 0.6),
          border: Border.all(
            color: disabled
                ? KColors.border
                : KColors.amber.withValues(alpha: 0.7),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 14,
              color: disabled ? KColors.textMuted : KColors.amber,
            ),
            const SizedBox(width: 4),
            Text(
              'Add stakeholder',
              style: TextStyle(
                color: disabled ? KColors.textMuted : KColors.amber,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapGrid extends StatelessWidget {
  final GlobalKey gridKey;
  final StakeholderMapContent content;
  final Map<String, Person> personById;
  final String? selectedDotId;
  final ValueChanged<StakeholderDot> onSelectDot;
  final void Function(String id, double x, double y) onMoveDot;

  const _MapGrid({
    required this.gridKey,
    required this.content,
    required this.personById,
    required this.selectedDotId,
    required this.onSelectDot,
    required this.onMoveDot,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Container(
          key: gridKey,
          decoration: BoxDecoration(
            color: KColors.surface,
            border: Border.all(color: KColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            children: [
              // Faint quadrant labels (background).
              const Positioned.fill(child: _QuadrantLabels()),
              // Centre cross-hair.
              Positioned(
                left: 0,
                right: 0,
                top: h / 2 - 0.5,
                height: 1,
                child:
                    Container(color: KColors.border.withValues(alpha: 0.7)),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: w / 2 - 0.5,
                width: 1,
                child:
                    Container(color: KColors.border.withValues(alpha: 0.7)),
              ),
              // Dots.
              ...content.stakeholders.map((dot) {
                final person = personById[dot.personId];
                return _DraggableDot(
                  key: ValueKey(dot.id),
                  dot: dot,
                  person: person,
                  gridWidth: w,
                  gridHeight: h,
                  isSelected: selectedDotId == dot.id,
                  onTap: () => onSelectDot(dot),
                  onMove: (x, y) => onMoveDot(dot.id, x, y),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _QuadrantLabels extends StatelessWidget {
  const _QuadrantLabels();

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, Alignment a) {
      return Align(
        alignment: a,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: KColors.textMuted.withValues(alpha: 0.65),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Stack(
        children: [
          // Top half = HIGH INFLUENCE; left = LOW INTEREST, right = HIGH INTEREST.
          Align(
            alignment: Alignment.topLeft,
            child: cell(StakeholderQuadrant.keepSatisfied, Alignment.topLeft),
          ),
          Align(
            alignment: Alignment.topRight,
            child:
                cell(StakeholderQuadrant.manageClosely, Alignment.topRight),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: cell(StakeholderQuadrant.monitor, Alignment.bottomLeft),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child:
                cell(StakeholderQuadrant.keepInformed, Alignment.bottomRight),
          ),
        ],
      ),
    );
  }
}

class _DraggableDot extends StatefulWidget {
  final StakeholderDot dot;
  final Person? person;
  final double gridWidth;
  final double gridHeight;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(double x, double y) onMove;

  const _DraggableDot({
    super.key,
    required this.dot,
    required this.person,
    required this.gridWidth,
    required this.gridHeight,
    required this.isSelected,
    required this.onTap,
    required this.onMove,
  });

  @override
  State<_DraggableDot> createState() => _DraggableDotState();
}

class _DraggableDotState extends State<_DraggableDot> {
  // Preview position during drag; null when not dragging.
  double? _previewX;
  double? _previewY;

  double get _x => _previewX ?? widget.dot.positionX;
  double get _y => _previewY ?? widget.dot.positionY;

  void _onPanUpdate(DragUpdateDetails details) {
    final w = widget.gridWidth;
    final h = widget.gridHeight;
    if (w <= 0 || h <= 0) return;
    setState(() {
      _previewX = (_x + details.delta.dx / w).clamp(0.0, 1.0);
      _previewY = (_y + details.delta.dy / h).clamp(0.0, 1.0);
    });
  }

  void _onPanEnd(DragEndDetails _) {
    final x = _previewX;
    final y = _previewY;
    setState(() {
      _previewX = null;
      _previewY = null;
    });
    if (x != null && y != null) widget.onMove(x, y);
  }

  @override
  Widget build(BuildContext context) {
    const dotSize = 28.0;
    const labelOffset = 4.0;
    final px = _x * widget.gridWidth - dotSize / 2;
    final py = _y * widget.gridHeight - dotSize / 2;
    final name = widget.person?.name ?? '(missing person)';
    final role = widget.person?.role;

    return Positioned(
      left: px,
      top: py,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Tooltip(
            message: role == null || role.isEmpty
                ? name
                : '$name — $role',
            waitDuration: const Duration(milliseconds: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: KColors.amber.withValues(
                        alpha: widget.isSelected ? 1.0 : 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.isSelected
                          ? KColors.text
                          : KColors.amber,
                      width: widget.isSelected ? 2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _initials(name),
                      style: const TextStyle(
                        color: KColors.bg,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: labelOffset),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: KColors.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KColors.text,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _DetailsSidePanel extends StatelessWidget {
  final StakeholderDot dot;
  final Person? person;
  final TextEditingController notesCtrl;
  final ValueChanged<String> onNotesChanged;
  final VoidCallback onRemove;
  final VoidCallback onClose;

  const _DetailsSidePanel({
    required this.dot,
    required this.person,
    required this.notesCtrl,
    required this.onNotesChanged,
    required this.onRemove,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: KColors.surface,
        border: Border(left: BorderSide(color: KColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: KColors.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  'STAKEHOLDER',
                  style: TextStyle(
                    color: KColors.textDim,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close,
                      size: 16, color: KColors.textDim),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    person?.name ?? '(missing person)',
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (person?.role != null && person!.role!.isNotEmpty)
                    Text(
                      person!.role!,
                      style: const TextStyle(
                        color: KColors.textDim,
                        fontSize: 12,
                      ),
                    ),
                  if (person?.organisation != null &&
                      person!.organisation!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        person!.organisation!,
                        style: const TextStyle(
                          color: KColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: KColors.surface2,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'Quadrant · ${StakeholderQuadrant.at(dot.positionX, dot.positionY)}',
                      style: const TextStyle(
                        color: KColors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'NOTES',
                    style: TextStyle(
                      color: KColors.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 5,
                    minLines: 3,
                    style: const TextStyle(
                      color: KColors.text,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Engagement strategy, last conversation, blockers…',
                      hintStyle: const TextStyle(
                          color: KColors.textMuted, fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.all(8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide:
                            const BorderSide(color: KColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide:
                            const BorderSide(color: KColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide:
                            const BorderSide(color: KColors.amber),
                      ),
                    ),
                    onChanged: onNotesChanged,
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('Remove from map'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KColors.red,
                      side: const BorderSide(color: KColors.red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
