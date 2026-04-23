import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';
import 'timeline_chart.dart';

// ---------------------------------------------------------------------------
// Public models
// ---------------------------------------------------------------------------

class GanttActivity {
  final String id;
  final String name;
  final String status;
  final DateTime? start;
  final DateTime? end;
  final String? ownerName;
  final int sortOrder;

  const GanttActivity({
    required this.id,
    required this.name,
    required this.status,
    this.start,
    this.end,
    this.ownerName,
    required this.sortOrder,
  });
}

class GanttMilestone {
  final String id;
  final String name;
  final String date; // ISO string
  final String? ownerName;
  final String status; // upcoming | achieved | at_risk | missed
  final bool isHardDeadline;
  final String? notes;
  final String? workstreamId;

  const GanttMilestone({
    required this.id,
    required this.name,
    required this.date,
    this.ownerName,
    required this.status,
    required this.isHardDeadline,
    this.notes,
    this.workstreamId,
  });
}

class GanttWorkstream {
  final String id;
  final String name;
  final String lane;
  final String? lead;
  final String status;
  final DateTime? start;
  final DateTime? end;
  final List<String> dependsOnIds;
  final List<GanttActivity> activities;

  const GanttWorkstream({
    required this.id,
    required this.name,
    required this.lane,
    this.lead,
    required this.status,
    this.start,
    this.end,
    this.dependsOnIds = const [],
    this.activities = const [],
  });
}

// ---------------------------------------------------------------------------
// Layout constants
// ---------------------------------------------------------------------------

const _kLeftW = 170.0;
const _kHeaderH = 34.0;
const _kLaneH = 22.0;
const _kRowH = 32.0;
const _kBarH = 16.0;
const _kActivityBarH = 10.0;
const _kActivityRowH = 20.0;
const _kEventH = 48.0;
const _kPxPerDay = 16.0;
const _kDiamondR = 8.0;

// ---------------------------------------------------------------------------
// Row layout model
// ---------------------------------------------------------------------------

class _RowInfo {
  final bool isLane;
  final bool isKeyDates;
  final String label;
  final double y;
  final double h;
  final GanttWorkstream? ws;
  final List<GanttActivity> activities;
  final List<GanttMilestone> milestonesInRow;

  const _RowInfo({
    required this.isLane,
    this.isKeyDates = false,
    required this.label,
    required this.y,
    required this.h,
    this.ws,
    this.activities = const [],
    this.milestonesInRow = const [],
  });
}

// ---------------------------------------------------------------------------
// Status colours
// ---------------------------------------------------------------------------

Color _barStroke(String status) {
  switch (status) {
    case 'in_progress': return KColors.phosphor;
    case 'complete':    return KColors.phosphor;
    case 'blocked':     return KColors.red;
    default:            return KColors.border2;
  }
}

Color _barFill(String status) {
  switch (status) {
    case 'in_progress': return const Color(0xFF0E2318);
    case 'complete':    return const Color(0xFF081A10);
    case 'blocked':     return KColors.redDim;
    default:            return KColors.surface2;
  }
}

Color _statusDot(String status) {
  switch (status) {
    case 'in_progress': return KColors.phosphor;
    case 'complete':    return KColors.phosphor;
    case 'blocked':     return KColors.red;
    default:            return KColors.textMuted;
  }
}

Color _milestoneColor(GanttMilestone ms) {
  if (ms.isHardDeadline) return KColors.red;
  switch (ms.status) {
    case 'achieved': return KColors.phosphor;
    case 'at_risk':  return KColors.amber;
    case 'missed':   return KColors.red;
    default:         return KColors.text; // upcoming
  }
}

// ---------------------------------------------------------------------------
// Event dot colours
// ---------------------------------------------------------------------------

Color _eventColor(TimelineEvent ev) {
  if (ev.categoryColor != null) return ev.categoryColor!;
  switch (ev.type) {
    case TimelineEventType.action:     return KColors.amber;
    case TimelineEventType.decision:   return KColors.blue;
    case TimelineEventType.issue:      return KColors.red;
    case TimelineEventType.dependency: return KColors.phosphor;
  }
}

const _kLinkColor = Color(0xFF00D4FF);

// ---------------------------------------------------------------------------
// GanttChart widget
// ---------------------------------------------------------------------------

class GanttChart extends StatefulWidget {
  final List<GanttWorkstream> workstreams;
  final List<TimelineEvent> events;
  final List<GanttMilestone> milestones;
  final void Function(TimelineEvent)? onEventTap;
  final void Function(GanttMilestone)? onMilestoneTap;
  final void Function(GanttActivity, GanttWorkstream)? onActivityTap;

  const GanttChart({
    super.key,
    required this.workstreams,
    required this.events,
    this.milestones = const [],
    this.onEventTap,
    this.onMilestoneTap,
    this.onActivityTap,
  });

  @override
  State<GanttChart> createState() => _GanttChartState();
}

class _DotHit {
  final double x;
  final double y;
  final TimelineEvent event;
  const _DotHit(this.x, this.y, this.event);
}

class _MilestoneHit {
  final double x;
  final double y;
  final GanttMilestone milestone;
  const _MilestoneHit(this.x, this.y, this.milestone);
}

class _ActivityHit {
  final Rect rect;
  final GanttActivity activity;
  final GanttWorkstream workstream;
  const _ActivityHit(this.rect, this.activity, this.workstream);
}

class _GanttChartState extends State<GanttChart> {
  final ScrollController _hScroll = ScrollController();
  List<_DotHit> _dotHits = [];
  List<_MilestoneHit> _milestoneHits = [];
  List<_ActivityHit> _activityHits = [];
  bool _scrolledToToday = false;

  // Hover tooltip state
  OverlayEntry? _tooltipOverlay;

  @override
  void dispose() {
    _hideTooltip();
    _hScroll.dispose();
    super.dispose();
  }

  void _showMilestoneTooltip(GanttMilestone ms, Offset globalPos) {
    _hideTooltip();
    _tooltipOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: globalPos.dx + 14,
        top: globalPos.dy - 30,
        child: _MilestoneTooltipBox(milestone: ms),
      ),
    );
    Overlay.of(context).insert(_tooltipOverlay!);
  }

  void _hideTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
  }

  void _scrollToToday(DateTime winStart) {
    if (_scrolledToToday) return;
    _scrolledToToday = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hScroll.hasClients) return;
      final today = DateTime.now();
      final todayNorm = DateTime(today.year, today.month, today.day);
      final daysFromStart = todayNorm.difference(winStart).inDays;
      final todayX = daysFromStart * _kPxPerDay;
      final target =
          (todayX - 120).clamp(0.0, _hScroll.position.maxScrollExtent);
      _hScroll.jumpTo(target);
    });
  }

  List<_DotHit> _computeDotPositions({
    required List<_RowInfo> rows,
    required DateTime winStart,
    required double pxPerDay,
  }) {
    if (widget.onEventTap == null) return [];

    double xFor(DateTime d) {
      final days = DateTime(d.year, d.month, d.day).difference(winStart).inDays;
      return days * pxPerDay;
    }

    final evY = rows.isEmpty ? _kHeaderH : rows.last.y + rows.last.h;
    final axisY = evY + _kEventH / 2;
    final hits = <_DotHit>[];
    final placed = <double>[];

    for (final ev in widget.events) {
      if (ev.date == null) continue;
      final x = xFor(ev.date!);
      final nearBy = placed.where((px) => (px - x).abs() < 10).length;
      final dotY = nearBy.isEven ? axisY - 8 : axisY + 8;
      placed.add(x);
      hits.add(_DotHit(x, dotY, ev));
    }
    return hits;
  }

  List<_MilestoneHit> _computeMilestoneHits({
    required List<_RowInfo> rows,
    required DateTime winStart,
    required double pxPerDay,
  }) {
    final hits = <_MilestoneHit>[];

    double xFor(DateTime d) {
      final days = DateTime(d.year, d.month, d.day).difference(winStart).inDays;
      return days * pxPerDay;
    }

    for (final row in rows) {
      for (final ms in row.milestonesInRow) {
        final date = DateTime.tryParse(ms.date);
        if (date == null) continue;
        final x = xFor(DateTime(date.year, date.month, date.day));
        final y = _diamondCenterY(row);
        hits.add(_MilestoneHit(x, y, ms));
      }
    }
    return hits;
  }

  List<_ActivityHit> _computeActivityHits({
    required List<_RowInfo> rows,
    required DateTime winStart,
    required double pxPerDay,
  }) {
    final hits = <_ActivityHit>[];

    double xFor(DateTime d) {
      final days = DateTime(d.year, d.month, d.day).difference(winStart).inDays;
      return days * pxPerDay;
    }

    for (final row in rows) {
      if (row.ws == null || row.activities.isEmpty) continue;
      for (int i = 0; i < row.activities.length; i++) {
        final act = row.activities[i];
        if (act.start == null || act.end == null) continue;
        final x1 = xFor(act.start!);
        final x2 = xFor(act.end!.add(const Duration(days: 1)));
        final barY = row.y + _kRowH + i * _kActivityRowH +
            (_kActivityRowH - _kActivityBarH) / 2;
        hits.add(_ActivityHit(
          Rect.fromLTWH(x1, barY, (x2 - x1).clamp(4.0, double.infinity), _kActivityBarH),
          act,
          row.ws!,
        ));
      }
    }
    return hits;
  }

  double _diamondCenterY(_RowInfo row) {
    if (row.isKeyDates || row.activities.isEmpty) {
      return row.y + _kRowH / 2;
    }
    // Workstream row with activities: diamond near top
    return row.y + _kDiamondR + 4;
  }

  void _handleTap(Offset localPos) {
    // Check milestones first
    if (widget.onMilestoneTap != null) {
      for (final hit in _milestoneHits) {
        if ((localPos - Offset(hit.x, hit.y)).distance <= _kDiamondR + 4) {
          widget.onMilestoneTap!(hit.milestone);
          return;
        }
      }
    }
    // Check activity bars
    if (widget.onActivityTap != null) {
      for (final hit in _activityHits) {
        if (hit.rect.contains(localPos)) {
          widget.onActivityTap!(hit.activity, hit.workstream);
          return;
        }
      }
    }
    // Check event dots
    if (widget.onEventTap != null) {
      for (final dot in _dotHits) {
        if ((localPos - Offset(dot.x, dot.y)).distance <= 12) {
          widget.onEventTap!(dot.event);
          return;
        }
      }
    }
  }

  void _handleHover(Offset localPos) {
    for (final hit in _milestoneHits) {
      if ((localPos - Offset(hit.x, hit.y)).distance <= _kDiamondR + 4) {
        // Convert local to global
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final globalPos = box.localToGlobal(localPos);
          _showMilestoneTooltip(hit.milestone, globalPos);
        }
        return;
      }
    }
    _hideTooltip();
  }

  List<_RowInfo> _buildRows() {
    final unassociated = widget.milestones
        .where((m) => m.workstreamId == null)
        .toList();

    final Map<String, List<GanttWorkstream>> laneMap = {};
    for (final ws in widget.workstreams) {
      laneMap.putIfAbsent(ws.lane, () => []).add(ws);
    }

    final rows = <_RowInfo>[];
    double y = _kHeaderH;

    // "Key Dates" row for unassociated milestones
    if (unassociated.isNotEmpty) {
      rows.add(_RowInfo(isLane: true, label: 'KEY DATES', y: y, h: _kLaneH));
      y += _kLaneH;
      rows.add(_RowInfo(
        isLane: false,
        isKeyDates: true,
        label: 'Key Dates',
        y: y,
        h: _kRowH,
        milestonesInRow: unassociated,
      ));
      y += _kRowH;
    }

    for (final lane in laneMap.keys.toList()..sort()) {
      rows.add(_RowInfo(isLane: true, label: lane, y: y, h: _kLaneH));
      y += _kLaneH;
      for (final ws in laneMap[lane]!) {
        final wsMilestones =
            widget.milestones.where((m) => m.workstreamId == ws.id).toList();
        final activities = List<GanttActivity>.from(ws.activities)
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        final rowH = _kRowH + activities.length * _kActivityRowH;
        rows.add(_RowInfo(
          isLane: false,
          label: ws.name,
          y: y,
          h: rowH,
          ws: ws,
          activities: activities,
          milestonesInRow: wsMilestones,
        ));
        y += rowH;
      }
    }
    return rows;
  }

  (DateTime, DateTime) _computeWindow() {
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);

    DateTime winStart = todayNorm.subtract(const Duration(days: 14));
    DateTime winEnd = todayNorm.add(const Duration(days: 90));

    for (final ws in widget.workstreams) {
      if (ws.start != null) {
        final s = DateTime(ws.start!.year, ws.start!.month, ws.start!.day)
            .subtract(const Duration(days: 7));
        if (s.isBefore(winStart)) winStart = s;
      }
      if (ws.end != null) {
        final e = DateTime(ws.end!.year, ws.end!.month, ws.end!.day)
            .add(const Duration(days: 14));
        if (e.isAfter(winEnd)) winEnd = e;
      }
      for (final act in ws.activities) {
        if (act.start != null) {
          final s =
              DateTime(act.start!.year, act.start!.month, act.start!.day)
                  .subtract(const Duration(days: 7));
          if (s.isBefore(winStart)) winStart = s;
        }
        if (act.end != null) {
          final e = DateTime(act.end!.year, act.end!.month, act.end!.day)
              .add(const Duration(days: 14));
          if (e.isAfter(winEnd)) winEnd = e;
        }
      }
    }
    for (final ev in widget.events) {
      if (ev.date != null) {
        final d = DateTime(ev.date!.year, ev.date!.month, ev.date!.day)
            .add(const Duration(days: 14));
        if (d.isAfter(winEnd)) winEnd = d;
      }
    }
    for (final ms in widget.milestones) {
      final d = DateTime.tryParse(ms.date);
      if (d != null) {
        final normalized = DateTime(d.year, d.month, d.day);
        final before = normalized.subtract(const Duration(days: 7));
        final after = normalized.add(const Duration(days: 14));
        if (before.isBefore(winStart)) winStart = before;
        if (after.isAfter(winEnd)) winEnd = after;
      }
    }
    return (winStart, winEnd);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    final contentH = rows.fold<double>(0.0, (s, r) => s + r.h);
    final totalH = _kHeaderH + contentH + _kEventH + 8;

    final (winStart, winEnd) = _computeWindow();
    final totalDays = winEnd.difference(winStart).inDays;
    final canvasW = (totalDays * _kPxPerDay).clamp(400.0, double.infinity);

    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);

    _dotHits = _computeDotPositions(
      rows: rows,
      winStart: winStart,
      pxPerDay: _kPxPerDay,
    );
    _milestoneHits = _computeMilestoneHits(
      rows: rows,
      winStart: winStart,
      pxPerDay: _kPxPerDay,
    );
    _activityHits = _computeActivityHits(
      rows: rows,
      winStart: winStart,
      pxPerDay: _kPxPerDay,
    );

    _scrollToToday(winStart);

    final rightCanvas = SizedBox(
      width: canvasW,
      height: totalH,
      child: CustomPaint(
        painter: _RightPainter(
          rows: rows,
          allWorkstreams: widget.workstreams,
          milestones: widget.milestones,
          events: widget.events,
          winStart: winStart,
          totalDays: totalDays,
          pxPerDay: _kPxPerDay,
          todayNorm: todayNorm,
          totalH: totalH,
        ),
      ),
    );

    final interactive = GestureDetector(
      onTapUp: (d) => _handleTap(d.localPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (ev) => _handleHover(ev.localPosition),
        onExit: (_) => _hideTooltip(),
        child: rightCanvas,
      ),
    );

    return SizedBox(
      height: math.max(totalH, _kHeaderH + _kEventH + 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _kLeftW,
            height: totalH,
            child: CustomPaint(
              painter: _LeftPainter(rows: rows, totalH: totalH),
            ),
          ),
          Container(width: 1, color: KColors.border),
          Expanded(
            child: Scrollbar(
              controller: _hScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                child: interactive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Milestone tooltip overlay
// ---------------------------------------------------------------------------

class _MilestoneTooltipBox extends StatelessWidget {
  final GanttMilestone milestone;

  const _MilestoneTooltipBox({required this.milestone});

  String _statusLabel(String s) {
    switch (s) {
      case 'achieved': return 'Achieved';
      case 'at_risk':  return 'At Risk';
      case 'missed':   return 'Missed';
      default:         return 'Upcoming';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _milestoneColor(milestone);
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: KColors.surface2,
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.diamond, size: 11, color: color),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(milestone.name,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                if (milestone.isHardDeadline) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: KColors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text('HARD',
                        style: TextStyle(color: KColors.red, fontSize: 8, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(milestone.date,
                style: const TextStyle(color: KColors.textDim, fontSize: 11)),
            const SizedBox(height: 2),
            Text(_statusLabel(milestone.status),
                style: TextStyle(color: color, fontSize: 11)),
            if (milestone.ownerName != null) ...[
              const SizedBox(height: 2),
              Text('Owner: ${milestone.ownerName}',
                  style: const TextStyle(color: KColors.textDim, fontSize: 11)),
            ],
            if (milestone.notes != null && milestone.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(milestone.notes!,
                  style: const TextStyle(color: KColors.textMuted, fontSize: 10),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left panel painter
// ---------------------------------------------------------------------------

class _LeftPainter extends CustomPainter {
  final List<_RowInfo> rows;
  final double totalH;

  const _LeftPainter({required this.rows, required this.totalH});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = KColors.surface);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, _kHeaderH),
        Paint()..color = KColors.surface2);

    for (final row in rows) {
      if (row.isLane) {
        canvas.drawRect(
          Rect.fromLTWH(0, row.y, size.width, row.h),
          Paint()..color = KColors.amberDim,
        );
        _drawText(
            canvas,
            row.label.toUpperCase(),
            const TextStyle(
                color: KColors.amber,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1),
            Offset(10, row.y + (row.h - 10) / 2),
            maxWidth: size.width - 14);
      } else if (row.isKeyDates) {
        _drawText(
            canvas,
            '◆  Key Dates',
            const TextStyle(
                color: KColors.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w500),
            Offset(10, row.y + (row.h - 11) / 2),
            maxWidth: size.width - 14);
        canvas.drawLine(
            Offset(0, row.y + row.h),
            Offset(size.width, row.y + row.h),
            Paint()
              ..color = KColors.border
              ..strokeWidth = 0.5);
      } else {
        final ws = row.ws!;
        // Status dot — centred in the parent bar zone
        canvas.drawCircle(
            Offset(10, row.y + _kRowH / 2),
            4,
            Paint()..color = _statusDot(ws.status));
        _drawText(
            canvas,
            ws.name,
            const TextStyle(
                color: KColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w500),
            Offset(22, row.y + (_kRowH - 12) / 2),
            maxWidth: size.width - 28);

        // Activity sub-rows
        for (int i = 0; i < row.activities.length; i++) {
          final act = row.activities[i];
          final actY = row.y + _kRowH + i * _kActivityRowH;
          canvas.drawLine(
              Offset(16, actY),
              Offset(size.width, actY),
              Paint()
                ..color = KColors.border
                ..strokeWidth = 0.5);
          canvas.drawCircle(
              Offset(20, actY + _kActivityRowH / 2),
              3,
              Paint()..color = _statusDot(act.status));
          _drawText(
              canvas,
              act.name,
              const TextStyle(color: KColors.textDim, fontSize: 9),
              Offset(28, actY + (_kActivityRowH - 10) / 2),
              maxWidth: size.width - 32);
        }

        // Row separator
        canvas.drawLine(
            Offset(0, row.y + row.h),
            Offset(size.width, row.y + row.h),
            Paint()
              ..color = KColors.border
              ..strokeWidth = 0.5);
      }
    }

    // Events label
    final evY = rows.isEmpty ? _kHeaderH : rows.last.y + rows.last.h;
    _drawText(
        canvas,
        'EVENTS',
        const TextStyle(
            color: KColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1),
        Offset(10, evY + 6),
        maxWidth: size.width - 16);
  }

  void _drawText(Canvas canvas, String text, TextStyle style, Offset offset,
      {double maxWidth = 140}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_LeftPainter old) => old.rows != rows;
}

// ---------------------------------------------------------------------------
// Right panel painter
// ---------------------------------------------------------------------------

class _RightPainter extends CustomPainter {
  final List<_RowInfo> rows;
  final List<GanttWorkstream> allWorkstreams;
  final List<GanttMilestone> milestones;
  final List<TimelineEvent> events;
  final DateTime winStart;
  final int totalDays;
  final double pxPerDay;
  final DateTime todayNorm;
  final double totalH;

  const _RightPainter({
    required this.rows,
    required this.allWorkstreams,
    required this.milestones,
    required this.events,
    required this.winStart,
    required this.totalDays,
    required this.pxPerDay,
    required this.todayNorm,
    required this.totalH,
  });

  double _xFor(DateTime d) {
    final days = DateTime(d.year, d.month, d.day).difference(winStart).inDays;
    return days * pxPerDay;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawBars(canvas, size);
    _drawMilestones(canvas, size);
    _drawDependencyArrows(canvas, size);
    _drawTodayLine(canvas, size);
    _drawEvents(canvas, size);
    _drawDateHeader(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1C2A38)
      ..strokeWidth = 0.5;

    for (final row in rows) {
      if (!row.isLane && !row.isKeyDates) {
        final wsRows = rows.where((r) => !r.isLane && !r.isKeyDates).toList();
        final idx = wsRows.indexOf(row);
        if (idx.isEven) {
          canvas.drawRect(
            Rect.fromLTWH(0, row.y, size.width, row.h),
            Paint()..color = const Color(0xFF0C1820),
          );
        }
      }
    }

    DateTime cursor = winStart;
    while (!cursor.isAfter(winStart.add(Duration(days: totalDays)))) {
      if (cursor.weekday == DateTime.monday) {
        final x = _xFor(cursor);
        canvas.drawLine(
            Offset(x, _kHeaderH), Offset(x, size.height), gridPaint);
      }
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  void _drawDateHeader(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, _kHeaderH),
      Paint()..color = KColors.surface2,
    );
    canvas.drawLine(Offset(0, _kHeaderH), Offset(size.width, _kHeaderH),
        Paint()
          ..color = KColors.border
          ..strokeWidth = 1);

    final monthStyle = TextStyle(
        color: const Color(0xFF8EA8C0).withValues(alpha: 0.9),
        fontSize: 10,
        fontWeight: FontWeight.w600);
    const weekStyle = TextStyle(color: Color(0xFF4A6070), fontSize: 8);

    DateTime cursor = winStart;
    String? lastMonth;
    while (!cursor.isAfter(winStart.add(Duration(days: totalDays)))) {
      final x = _xFor(cursor);
      if (cursor.day == 1) {
        final label = '${_monthAbbr(cursor.month)} ${cursor.year}';
        if (label != lastMonth) {
          lastMonth = label;
          _drawText(canvas, label, monthStyle, Offset(x + 3, 4), maxWidth: 72);
        }
      }
      if (cursor.weekday == DateTime.monday) {
        final wk =
            '${cursor.day.toString().padLeft(2, '0')}/${cursor.month.toString().padLeft(2, '0')}';
        _drawText(canvas, wk, weekStyle, Offset(x + 2, 20), maxWidth: 36);
      }
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  void _drawBars(Canvas canvas, Size size) {
    for (final row in rows) {
      if (row.isLane || row.isKeyDates || row.ws == null) continue;
      final ws = row.ws!;
      final hasActivities = row.activities.isNotEmpty;

      if (ws.start == null || ws.end == null) {
        _drawUndatedBar(canvas, row);
      } else {
        final x1 = _xFor(ws.start!);
        final x2 = _xFor(ws.end!.add(const Duration(days: 1)));
        final barW = (x2 - x1).clamp(4.0, double.infinity);
        final barY = row.y + (_kRowH - _kBarH) / 2;
        final fillRect = Rect.fromLTWH(x1, barY, barW, _kBarH);

        final opacity = hasActivities ? 0.4 : 1.0;

        canvas.drawRRect(
          RRect.fromRectAndRadius(fillRect, const Radius.circular(3)),
          Paint()..color = _barFill(ws.status).withValues(alpha: opacity),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(fillRect, const Radius.circular(3)),
          Paint()
            ..color = _barStroke(ws.status).withValues(alpha: opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );

        if (barW > 40 && !hasActivities) {
          _drawText(
            canvas,
            ws.name,
            TextStyle(
                color: (ws.status == 'not_started'
                        ? KColors.textDim
                        : _barStroke(ws.status))
                    .withValues(alpha: opacity),
                fontSize: 10,
                fontWeight: FontWeight.w600),
            Offset(x1 + 5, barY + (_kBarH - 10) / 2),
            maxWidth: barW - 8,
          );
        }
      }

      // Activity bars
      if (hasActivities) {
        _drawActivityBars(canvas, row);
      }
    }
  }

  void _drawActivityBars(Canvas canvas, _RowInfo row) {
    for (int i = 0; i < row.activities.length; i++) {
      final act = row.activities[i];
      if (act.start == null || act.end == null) continue;

      final x1 = _xFor(act.start!);
      final x2 = _xFor(act.end!.add(const Duration(days: 1)));
      final barW = (x2 - x1).clamp(4.0, double.infinity);
      final barY =
          row.y + _kRowH + i * _kActivityRowH + (_kActivityRowH - _kActivityBarH) / 2;

      final fillRect = Rect.fromLTWH(x1, barY, barW, _kActivityBarH);

      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(2)),
        Paint()..color = _barFill(act.status),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(2)),
        Paint()
          ..color = _barStroke(act.status)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      if (barW > 30) {
        final label = act.ownerName != null
            ? '${act.name} · ${act.ownerName}'
            : act.name;
        _drawText(
          canvas,
          label,
          TextStyle(
              color: act.status == 'not_started'
                  ? KColors.textDim
                  : _barStroke(act.status),
              fontSize: 8,
              fontWeight: FontWeight.w500),
          Offset(x1 + 4, barY + (_kActivityBarH - 9) / 2),
          maxWidth: barW - 6,
        );
      }
    }
  }

  void _drawMilestones(Canvas canvas, Size size) {
    for (final row in rows) {
      for (final ms in row.milestonesInRow) {
        final date = DateTime.tryParse(ms.date);
        if (date == null) continue;
        final x = _xFor(DateTime(date.year, date.month, date.day));
        final centerY = row.isKeyDates || row.activities.isEmpty
            ? row.y + _kRowH / 2
            : row.y + _kDiamondR + 4;
        _drawDiamond(canvas, x, centerY, ms);
      }
    }
  }

  void _drawDiamond(Canvas canvas, double x, double y, GanttMilestone ms) {
    const r = _kDiamondR;
    final color = _milestoneColor(ms);
    final isUpcoming = ms.status == 'upcoming' && !ms.isHardDeadline;

    final path = Path()
      ..moveTo(x, y - r)
      ..lineTo(x + r, y)
      ..lineTo(x, y + r)
      ..lineTo(x - r, y)
      ..close();

    if (!isUpcoming) {
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.25));
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawUndatedBar(Canvas canvas, _RowInfo row) {
    final barY = row.y + (_kRowH - _kBarH) / 2;
    const dashW = 20.0;
    const gapW = 6.0;
    double x = 8;
    final paint = Paint()
      ..color = KColors.border2
      ..strokeWidth = 1;
    while (x < 120) {
      canvas.drawLine(
          Offset(x, barY + _kBarH / 2),
          Offset(math.min(x + dashW, 120), barY + _kBarH / 2),
          paint);
      x += dashW + gapW;
    }
    _drawText(canvas, 'no dates set',
        const TextStyle(color: KColors.textMuted, fontSize: 9),
        Offset(8, barY + (_kBarH - 10) / 2),
        maxWidth: 100);
  }

  void _drawDependencyArrows(Canvas canvas, Size size) {
    final Map<String, _RowInfo> wsRows = {};
    for (final row in rows) {
      if (!row.isLane && !row.isKeyDates && row.ws != null) {
        wsRows[row.ws!.id] = row;
      }
    }

    final arrowPaint = Paint()
      ..color = KColors.amber.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final toRow in rows) {
      if (toRow.isLane || toRow.isKeyDates || toRow.ws == null) continue;
      final toWs = toRow.ws!;
      if (toWs.dependsOnIds.isEmpty || toWs.start == null) continue;

      for (final fromId in toWs.dependsOnIds) {
        final fromRow = wsRows[fromId];
        if (fromRow == null || fromRow.ws?.end == null) continue;

        final x1 = _xFor(fromRow.ws!.end!.add(const Duration(days: 1)));
        // Arrow anchors at the parent bar centre (within _kRowH), not full row
        final y1 = fromRow.y + _kRowH / 2;
        final x2 = _xFor(toWs.start!);
        final y2 = toRow.y + _kRowH / 2;

        const margin = 10.0;
        final midX = x1 + margin;

        final path = Path()
          ..moveTo(x1, y1)
          ..lineTo(midX, y1)
          ..lineTo(midX, y2)
          ..lineTo(x2, y2);
        canvas.drawPath(path, arrowPaint);
        _drawArrowhead(canvas, Offset(x2, y2), arrowPaint);
      }
    }
  }

  void _drawArrowhead(Canvas canvas, Offset tip, Paint paint) {
    const size = 5.0;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - size, tip.dy - size / 2)
      ..lineTo(tip.dx - size, tip.dy + size / 2)
      ..close();
    canvas.drawPath(
        path, Paint()..color = paint.color..style = PaintingStyle.fill);
  }

  void _drawTodayLine(Canvas canvas, Size size) {
    final x = _xFor(todayNorm);
    if (x < 0 || x > size.width) return;

    final paint = Paint()
      ..color = KColors.amber
      ..strokeWidth = 1.5;

    const dash = 5.0, gap = 3.0;
    double y = _kHeaderH;
    while (y < size.height) {
      canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + dash, size.height)),
          paint);
      y += dash + gap;
    }

    _drawText(canvas, 'Today',
        const TextStyle(
            color: KColors.amber, fontSize: 8, fontWeight: FontWeight.w700),
        Offset(x - 14, _kHeaderH + 3),
        maxWidth: 36);
  }

  void _drawEvents(Canvas canvas, Size size) {
    final evY = rows.isEmpty ? _kHeaderH : rows.last.y + rows.last.h;

    canvas.drawLine(Offset(0, evY), Offset(size.width, evY),
        Paint()
          ..color = KColors.border
          ..strokeWidth = 0.5);

    final axisY = evY + _kEventH / 2;
    canvas.drawLine(Offset(0, axisY), Offset(size.width, axisY),
        Paint()
          ..color = const Color(0xFF1C2A38)
          ..strokeWidth = 1.0);

    final placed = <double>[];
    final dotPositions = <String, Offset>{};

    for (final ev in events) {
      if (ev.date == null) continue;
      final x = _xFor(ev.date!);
      if (x < 0 || x > size.width) continue;

      final isPast = ev.date!.isBefore(todayNorm);
      final color = isPast ? KColors.red : _eventColor(ev);

      final nearBy = placed.where((px) => (px - x).abs() < 10).length;
      final dotY = nearBy.isEven ? axisY - 8 : axisY + 8;
      placed.add(x);

      if (ev.id != null) dotPositions[ev.id!] = Offset(x, dotY);

      canvas.drawCircle(Offset(x, dotY), 5,
          Paint()..color = color.withValues(alpha: isPast ? 0.5 : 1.0));
      canvas.drawCircle(Offset(x, dotY), 5,
          Paint()
            ..color = color.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }

    final linkPaint = Paint()
      ..color = _kLinkColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final ev in events) {
      if (ev.id == null || ev.linkedActionId == null) continue;
      final from = dotPositions[ev.id!];
      final to = dotPositions[ev.linkedActionId!];
      if (from == null || to == null) continue;
      _drawDashedLine(canvas, from, to, linkPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dashLen = 5.0;
    const gapLen = 3.0;
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return;
    final ux = dx / dist;
    final uy = dy / dist;
    double traveled = 0;
    bool drawing = true;
    while (traveled < dist) {
      final seg =
          math.min(traveled + (drawing ? dashLen : gapLen), dist);
      if (drawing) {
        canvas.drawLine(
          Offset(from.dx + ux * traveled, from.dy + uy * traveled),
          Offset(from.dx + ux * seg, from.dy + uy * seg),
          paint,
        );
      }
      traveled = seg;
      drawing = !drawing;
    }
  }

  void _drawText(Canvas canvas, String text, TextStyle style, Offset offset,
      {double maxWidth = 100}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  String _monthAbbr(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];

  @override
  bool shouldRepaint(_RightPainter old) =>
      old.rows != rows ||
      old.events != events ||
      old.milestones != milestones ||
      old.allWorkstreams != allWorkstreams;
}
