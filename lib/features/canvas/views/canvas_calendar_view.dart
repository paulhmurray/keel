import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/database.dart';
import '../../../shared/theme/keel_colors.dart';
import '../calendar_drag_math.dart';
import '../canvas_constants.dart';
import '../canvas_link_badge.dart';

/// A real calendar grid for Canvas cards. Time runs left→right by day,
/// cards stack top-to-bottom as horizontal bars across their date range.
/// Cards without dates land in a "No date" sidebar on the right.
///
/// Date resolution order, per card:
///   1. The card's own `startDate`/`endDate` (always wins when set).
///   2. The date on the linked formal item (action.dueDate, milestone.date,
///      activity.startDate–endDate, decision.dueDate, …).
///   3. Treated as undated → sidebar.
class CanvasCalendarView extends StatefulWidget {
  final String projectId;
  final List<CanvasCard> cards;
  final void Function(CanvasCard) onTap;

  const CanvasCalendarView({
    super.key,
    required this.projectId,
    required this.cards,
    required this.onTap,
  });

  @override
  State<CanvasCalendarView> createState() => _CanvasCalendarViewState();
}

class _CanvasCalendarViewState extends State<CanvasCalendarView> {
  static const double _dayWidth = 28;
  static const double _laneHeight = 26;
  static const double _laneGap = 4;
  static const double _leftLabelWidth = 220;

  Map<String, _DateSpan> _resolved = const {};
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  @override
  void didUpdateWidget(covariant CanvasCalendarView old) {
    super.didUpdateWidget(old);
    if (!_listsEqual(old.cards, widget.cards)) _resolve();
  }

  bool _listsEqual(List<CanvasCard> a, List<CanvasCard> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ax = a[i], bx = b[i];
      if (ax.id != bx.id ||
          ax.startDate != bx.startDate ||
          ax.endDate != bx.endDate ||
          ax.linkedItemType != bx.linkedItemType ||
          ax.linkedItemId != bx.linkedItemId) {
        return false;
      }
    }
    return true;
  }

  Future<void> _resolve() async {
    if (_resolving) return;
    _resolving = true;
    final db = context.read<AppDatabase>();
    final map = <String, _DateSpan>{};
    for (final c in widget.cards) {
      // Card's own range wins.
      final cardSpan = _DateSpan.tryParse(c.startDate, c.endDate);
      if (cardSpan != null) {
        map[c.id] = cardSpan;
        continue;
      }
      // Fall back to the linked formal item's date.
      final linked = await _dateForLinked(db, c.linkedItemType, c.linkedItemId);
      if (linked != null) map[c.id] = linked;
    }
    if (mounted) {
      setState(() {
        _resolved = map;
        _resolving = false;
      });
    } else {
      _resolving = false;
    }
  }

  Future<_DateSpan?> _dateForLinked(
      AppDatabase db, String? type, String? id) async {
    if (type == null || id == null) return null;
    switch (type) {
      case 'action':
        final row = await db.actionsDao.getActionById(id);
        return _DateSpan.fromSingle(row?.dueDate);
      case 'milestone':
        final list = await db.milestonesDao.getForProject(widget.projectId);
        return _DateSpan.fromSingle(
            list.where((e) => e.id == id).map((e) => e.date).firstOrNull);
      case 'activity':
        final list =
            await db.workstreamActivitiesDao.getForProject(widget.projectId);
        final a = list.where((e) => e.id == id).firstOrNull;
        if (a == null) return null;
        return _DateSpan.tryParse(a.startDate, a.endDate);
      case 'issue':
        final list = await db.raidDao.getIssuesForProject(widget.projectId);
        return _DateSpan.fromSingle(
            list.where((e) => e.id == id).map((e) => e.dueDate).firstOrNull);
      case 'dependency':
        final list =
            await db.raidDao.getDependenciesForProject(widget.projectId);
        return _DateSpan.fromSingle(
            list.where((e) => e.id == id).map((e) => e.dueDate).firstOrNull);
      case 'decision':
        final row = await db.decisionsDao.getDecisionById(id);
        return _DateSpan.fromSingle(row?.dueDate);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dated = <_PositionedCard>[];
    final undated = <CanvasCard>[];
    for (final c in widget.cards) {
      final span = _resolved[c.id];
      if (span == null) {
        undated.add(c);
      } else {
        dated.add(_PositionedCard(card: c, span: span));
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: dated.isEmpty
              ? _EmptyState(onDropFromSidebar: _commitDropFromSidebar)
              : _Grid(
                  positioned: dated,
                  dayWidth: _dayWidth,
                  laneHeight: _laneHeight,
                  laneGap: _laneGap,
                  leftLabelWidth: _leftLabelWidth,
                  onTap: widget.onTap,
                  onCommitDates: _commitDates,
                  onDropFromSidebar: _commitDropFromSidebar,
                ),
        ),
        _UndatedSidebar(cards: undated, onTap: widget.onTap),
      ],
    );
  }

  /// Called when an undated card is dropped onto the grid at [dropDay].
  /// Materialises start/end based on the card's effortDays (or a 7-day
  /// default) and persists.
  Future<void> _commitDropFromSidebar(
      CanvasCard card, DateTime dropDay) async {
    final span = CalendarDragMath.spanFromDrop(dropDay, card.effortDays);
    await _commitDates(card, span.start, span.end);
  }

  /// Writes card-local start/end dates. When the card was using a linked
  /// item's date until now, this is the moment the canvas thinking
  /// "detaches" from the source — the source item is left alone.
  Future<void> _commitDates(
      CanvasCard card, DateTime start, DateTime end) async {
    final db = context.read<AppDatabase>();
    await db.canvasCardsDao.patchCard(
      card.id,
      CanvasCardsCompanion(
        startDate: Value(CalendarDragMath.iso(start)),
        endDate: Value(CalendarDragMath.iso(end)),
      ),
    );
    // Optimistically reflect the move locally so the bar doesn't snap
    // back to its old position between the DAO write and the next
    // stream tick.
    if (mounted) {
      setState(() {
        _resolved = {
          ..._resolved,
          card.id: _DateSpan(start, end),
        };
      });
    }
  }
}

class _Grid extends StatefulWidget {
  final List<_PositionedCard> positioned;
  final double dayWidth;
  final double laneHeight;
  final double laneGap;
  final double leftLabelWidth;
  final void Function(CanvasCard) onTap;
  final Future<void> Function(CanvasCard, DateTime, DateTime) onCommitDates;
  final Future<void> Function(CanvasCard, DateTime) onDropFromSidebar;

  const _Grid({
    required this.positioned,
    required this.dayWidth,
    required this.laneHeight,
    required this.laneGap,
    required this.leftLabelWidth,
    required this.onTap,
    required this.onCommitDates,
    required this.onDropFromSidebar,
  });

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Compute the window: earliest start → latest end + a one-week pad.
    DateTime minStart = widget.positioned.first.span.start;
    DateTime maxEnd = widget.positioned.first.span.end;
    for (final p in widget.positioned) {
      if (p.span.start.isBefore(minStart)) minStart = p.span.start;
      if (p.span.end.isAfter(maxEnd)) maxEnd = p.span.end;
    }
    // Pad to start of week (Mon) and to end of week (Sun).
    final paddedStart = _startOfWeek(minStart);
    final paddedEnd = _endOfWeek(maxEnd);
    final totalDays = paddedEnd.difference(paddedStart).inDays + 1;
    final gridWidth = totalDays * widget.dayWidth;

    // Lane assignment: greedy "first lane with no overlap" — cards stack
    // vertically when their ranges overlap.
    widget.positioned.sort((a, b) => a.span.start.compareTo(b.span.start));
    final laneEnds = <DateTime>[];
    for (final p in widget.positioned) {
      var lane = -1;
      for (var i = 0; i < laneEnds.length; i++) {
        if (!laneEnds[i].isAfter(p.span.start.subtract(const Duration(days: 1)))) {
          lane = i;
          laneEnds[i] = p.span.end;
          break;
        }
      }
      if (lane < 0) {
        laneEnds.add(p.span.end);
        lane = laneEnds.length - 1;
      }
      p.lane = lane;
    }
    final totalLanes = laneEnds.isEmpty ? 1 : laneEnds.length;
    final naturalGridHeight =
        totalLanes * (widget.laneHeight + widget.laneGap) +
            widget.laneGap +
            48; // 48 = axis

    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        // LayoutBuilder lets us stretch the Stack to fill the calendar
        // area vertically so sidebar drops can land anywhere over the
        // grid, not just on the narrow strip of visible bars.
        child: LayoutBuilder(builder: (context, constraints) {
          final gridHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight.clamp(naturalGridHeight, double.infinity)
              : naturalGridHeight;
          return SizedBox(
            width: gridWidth,
            height: gridHeight,
            child: DragTarget<CanvasCard>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(details.offset);
              final dayIdx = CalendarDragMath.dayIndexFromOffset(
                  local.dx, widget.dayWidth);
              final dropDay = paddedStart.add(Duration(days: dayIdx));
              widget.onDropFromSidebar(details.data, dropDay);
            },
            builder: (context, candidate, _) {
              return Stack(
                children: [
                  _DateAxis(
                    start: paddedStart,
                    totalDays: totalDays,
                    dayWidth: widget.dayWidth,
                  ),
                  for (final p in widget.positioned)
                    _CardBar(
                      key: ValueKey(p.card.id),
                      card: p.card,
                      span: p.span,
                      paddedStart: paddedStart,
                      dayWidth: widget.dayWidth,
                      laneHeight: widget.laneHeight,
                      laneGap: widget.laneGap,
                      lane: p.lane,
                      topOffset: 48 + widget.laneGap,
                      onTap: () => widget.onTap(p.card),
                      onCommit: (s, e) =>
                          widget.onCommitDates(p.card, s, e),
                    ),
                  if (candidate.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: KColors.amber.withValues(alpha: 0.06),
                          alignment: Alignment.topCenter,
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: KColors.amberDim,
                              border: Border.all(color: KColors.amber),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              candidate.first!.effortDays != null
                                  ? 'Drop to place as a '
                                      '${candidate.first!.effortDays}-day bar'
                                  : 'Drop to place as a 7-day bar '
                                      '(default)',
                              style: const TextStyle(
                                color: KColors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          );
        }),
      ),
    );
  }

  static DateTime _startOfWeek(DateTime d) {
    final monday = d.subtract(Duration(days: (d.weekday - DateTime.monday) % 7));
    return DateTime(monday.year, monday.month, monday.day);
  }

  static DateTime _endOfWeek(DateTime d) {
    final sunday = d.add(Duration(days: (DateTime.sunday - d.weekday) % 7));
    return DateTime(sunday.year, sunday.month, sunday.day);
  }
}

class _DateAxis extends StatelessWidget {
  final DateTime start;
  final int totalDays;
  final double dayWidth;

  const _DateAxis({
    required this.start,
    required this.totalDays,
    required this.dayWidth,
  });

  @override
  Widget build(BuildContext context) {
    final monthStarts = <int>[]; // day-index where a new month begins
    for (var i = 0; i < totalDays; i++) {
      final d = start.add(Duration(days: i));
      if (i == 0 || d.day == 1) monthStarts.add(i);
    }
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 48,
      child: Stack(
        children: [
          // Month band.
          ...List.generate(monthStarts.length, (i) {
            final from = monthStarts[i];
            final to = i + 1 < monthStarts.length
                ? monthStarts[i + 1]
                : totalDays;
            final width = (to - from) * dayWidth;
            final monthDate = start.add(Duration(days: from));
            return Positioned(
              left: from * dayWidth,
              top: 0,
              width: width,
              height: 22,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: KColors.border, width: 0.5),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_monthName(monthDate.month)} ${monthDate.year}',
                  // Keep Month + Year side-by-side even when only a few
                  // days of this month are visible — narrow widths
                  // should clip rather than wrap onto two lines.
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    color: KColors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            );
          }),
          // Day cells.
          ...List.generate(totalDays, (i) {
            final d = start.add(Duration(days: i));
            final isWeekend = d.weekday > 5;
            return Positioned(
              left: i * dayWidth,
              top: 22,
              width: dayWidth,
              height: 26,
              child: Container(
                decoration: BoxDecoration(
                  color: isWeekend
                      ? KColors.surface
                      : Colors.transparent,
                  border: const Border(
                    right:
                        BorderSide(color: KColors.border, width: 0.3),
                    bottom:
                        BorderSide(color: KColors.border, width: 0.5),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${d.day}',
                  style: TextStyle(
                    color: isWeekend ? KColors.textMuted : KColors.textDim,
                    fontSize: 10,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  static String _monthName(int m) {
    const names = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[m];
  }
}

/// A draggable timeline bar.
///
/// Three drag zones:
///   - **Left edge** (6 px gripper): pan adjusts `startDate`. Clamps so
///     start never crosses end (resulting in a single-day span if pushed
///     past).
///   - **Right edge** (6 px gripper): pan adjusts `endDate` with the
///     mirror clamp.
///   - **Middle**: pan shifts both endpoints by the same delta, so the
///     length is preserved exactly. This is the "move it forward a
///     month without changing the effort" interaction.
///
/// Drag is visual-only during the gesture (no DAO writes per pointer
/// move); the new dates are committed once on pan-end via `onCommit`.
class _CardBar extends StatefulWidget {
  final CanvasCard card;
  final _DateSpan span;
  final DateTime paddedStart;
  final double dayWidth;
  final double laneHeight;
  final double laneGap;
  final int lane;
  final double topOffset;
  final VoidCallback onTap;
  final Future<void> Function(DateTime, DateTime) onCommit;

  const _CardBar({
    super.key,
    required this.card,
    required this.span,
    required this.paddedStart,
    required this.dayWidth,
    required this.laneHeight,
    required this.laneGap,
    required this.lane,
    required this.topOffset,
    required this.onTap,
    required this.onCommit,
  });

  @override
  State<_CardBar> createState() => _CardBarState();
}

enum _DragMode { none, resizeStart, resizeEnd, shift }

class _CardBarState extends State<_CardBar> {
  /// Pixel hit-area for the resize grippers at each edge.
  static const double _gripperWidth = 8;

  _DragMode _mode = _DragMode.none;
  double _dragAccumulator = 0;

  // Visual overrides applied during an in-progress drag. When null the
  // bar uses widget.span as-is.
  DateTime? _previewStart;
  DateTime? _previewEnd;

  DateTime get _effStart => _previewStart ?? widget.span.start;
  DateTime get _effEnd => _previewEnd ?? widget.span.end;

  void _onPanStart(_DragMode mode) {
    setState(() {
      _mode = mode;
      _dragAccumulator = 0;
      _previewStart = widget.span.start;
      _previewEnd = widget.span.end;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    _dragAccumulator += details.delta.dx;
    final days =
        CalendarDragMath.snapToDays(_dragAccumulator, widget.dayWidth);
    if (days == 0) return;
    final base = widget.span;
    setState(() {
      switch (_mode) {
        case _DragMode.shift:
          final shifted = CalendarDragMath.shift(base.start, base.end, days);
          _previewStart = shifted.start;
          _previewEnd = shifted.end;
          break;
        case _DragMode.resizeStart:
          _previewStart =
              CalendarDragMath.resizeStart(base.start, base.end, days);
          break;
        case _DragMode.resizeEnd:
          _previewEnd =
              CalendarDragMath.resizeEnd(base.start, base.end, days);
          break;
        case _DragMode.none:
          break;
      }
    });
  }

  Future<void> _onPanEnd(DragEndDetails _) async {
    final s = _previewStart;
    final e = _previewEnd;
    final mode = _mode;
    setState(() {
      _mode = _DragMode.none;
      _previewStart = null;
      _previewEnd = null;
      _dragAccumulator = 0;
    });
    if (mode == _DragMode.none || s == null || e == null) return;
    if (s == widget.span.start && e == widget.span.end) return;
    await widget.onCommit(s, e);
  }

  @override
  Widget build(BuildContext context) {
    final startOffset =
        _effStart.difference(widget.paddedStart).inDays * widget.dayWidth;
    final spanDays = _effEnd.difference(_effStart).inDays + 1;
    final width =
        (spanDays * widget.dayWidth).clamp(widget.dayWidth * 0.6, double.infinity);
    final top = widget.topOffset + widget.lane * (widget.laneHeight + widget.laneGap);
    final fill = CanvasCardColours.colourFor(widget.card.colour) ??
        KColors.amber.withValues(alpha: 0.6);

    return Positioned(
      left: startOffset,
      top: top,
      width: width,
      height: widget.laneHeight,
      child: Tooltip(
        message: _tooltip(),
        child: Stack(
          children: [
            // The bar's visible body — middle zone (shift) gets the tap
            // and pan handlers; the resize gripper Stack children sit
            // above for hit-priority.
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onPanStart: (_) => _onPanStart(_DragMode.shift),
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: Container(
                    decoration: BoxDecoration(
                      color: fill.withValues(alpha: 0.18),
                      border: Border.all(color: fill, width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        if (widget.card.linkedItemType != null) ...[
                          Icon(
                            CanvasLinkBadge.iconForType(
                                widget.card.linkedItemType!),
                            size: 10,
                            color: fill,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            widget.card.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: KColors.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Left gripper.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _gripperWidth,
              child: _Gripper(
                onPanStart: () => _onPanStart(_DragMode.resizeStart),
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
              ),
            ),
            // Right gripper.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _gripperWidth,
              child: _Gripper(
                onPanStart: () => _onPanStart(_DragMode.resizeEnd),
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _tooltip() {
    final s = CalendarDragMath.iso(_effStart);
    final e = CalendarDragMath.iso(_effEnd);
    if (s == e) return '${widget.card.title}\n$s';
    return '${widget.card.title}\n$s → $e';
  }
}

class _Gripper extends StatelessWidget {
  final VoidCallback onPanStart;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final Future<void> Function(DragEndDetails) onPanEnd;

  const _Gripper({
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onPanStart(),
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        // A subtle inner stripe so the gripper is visible on hover/drag.
        child: Container(
          alignment: Alignment.center,
          child: Container(
            width: 2,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: KColors.text.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _UndatedSidebar extends StatelessWidget {
  final List<CanvasCard> cards;
  final void Function(CanvasCard) onTap;

  const _UndatedSidebar({required this.cards, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: KColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: KColors.border, width: 0.5)),
            ),
            child: Text(
              'NO DATE · ${cards.length}',
              style: const TextStyle(
                color: KColors.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
          Expanded(
            child: cards.isEmpty
                ? const Center(
                    child: Text(
                      '—',
                      style:
                          TextStyle(color: KColors.textMuted, fontSize: 18),
                    ),
                  )
                : ListView(
                    children: cards
                        .map((c) => _MiniCard(
                              card: c,
                              onTap: () => onTap(c),
                              draggable: true,
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final CanvasCard card;
  final VoidCallback onTap;
  final bool draggable;

  const _MiniCard({
    required this.card,
    required this.onTap,
    this.draggable = false,
  });

  @override
  Widget build(BuildContext context) {
    final tile = InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: KColors.surface,
          border: Border.all(color: KColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            if (card.linkedItemType != null) ...[
              Icon(
                CanvasLinkBadge.iconForType(card.linkedItemType!),
                size: 12,
                color: CanvasLinkBadge.colourForType(card.linkedItemType!),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: KColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (draggable)
              const Icon(
                Icons.drag_indicator,
                size: 14,
                color: KColors.textMuted,
              ),
          ],
        ),
      ),
    );
    if (!draggable) return tile;
    return Draggable<CanvasCard>(
      data: card,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: KColors.surface,
            border: Border.all(color: KColors.amber),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_indicator,
                  size: 14, color: KColors.amber),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: KColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }
}

/// Empty grid placeholder that still accepts sidebar drops — so the
/// first dated card can be created by dragging straight onto the empty
/// calendar. The drop day is today, since there's no axis to read from
/// yet.
class _EmptyState extends StatelessWidget {
  final Future<void> Function(CanvasCard, DateTime) onDropFromSidebar;

  const _EmptyState({required this.onDropFromSidebar});

  @override
  Widget build(BuildContext context) {
    return DragTarget<CanvasCard>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        onDropFromSidebar(details.data, today);
      },
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        return Container(
          color: hovering
              ? KColors.amber.withValues(alpha: 0.05)
              : Colors.transparent,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                hovering
                    ? 'Drop here — starts today, default 7-day length '
                        '(or this card\'s Effort).'
                    : 'No dated cards yet. Give a card a start/end date '
                        'in the editor, drag one in from the sidebar, or '
                        'link it to a milestone, action or activity.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: KColors.textMuted),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PositionedCard {
  final CanvasCard card;
  final _DateSpan span;
  int lane = 0;
  _PositionedCard({required this.card, required this.span});
}

class _DateSpan {
  final DateTime start;
  final DateTime end;

  const _DateSpan(this.start, this.end);

  /// Builds a single-day span from an ISO date string. Returns null when
  /// the input is empty or unparsable.
  static _DateSpan? fromSingle(String? iso) {
    final d = _tryParseIso(iso);
    if (d == null) return null;
    return _DateSpan(d, d);
  }

  /// Builds a range from two ISO date strings. If only one is set, the
  /// span is a single day; if [end] is before [start] we return null so
  /// the calendar treats the card as undated rather than show garbage.
  static _DateSpan? tryParse(String? startIso, String? endIso) {
    final s = _tryParseIso(startIso);
    final e = _tryParseIso(endIso);
    if (s == null && e == null) return null;
    if (s != null && e == null) return _DateSpan(s, s);
    if (s == null && e != null) return _DateSpan(e, e);
    if (e!.isBefore(s!)) return null;
    return _DateSpan(s, e);
  }

  static DateTime? _tryParseIso(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      final d = DateTime.parse(iso);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }
}
