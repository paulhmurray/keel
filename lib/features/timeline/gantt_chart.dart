import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';
import 'timeline_chart.dart';

// ---------------------------------------------------------------------------
// Public model
// ---------------------------------------------------------------------------

class GanttWorkstream {
  final String id;
  final String name;
  final String lane;
  final String? lead;
  final String status; // not_started | in_progress | complete | blocked
  final DateTime? start;
  final DateTime? end;
  final List<String> dependsOnIds; // IDs of workstreams this one depends on

  const GanttWorkstream({
    required this.id,
    required this.name,
    required this.lane,
    this.lead,
    required this.status,
    this.start,
    this.end,
    this.dependsOnIds = const [],
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
const _kEventH = 48.0;
const _kPxPerDay = 16.0;

// ---------------------------------------------------------------------------
// Row layout model
// ---------------------------------------------------------------------------

class _RowInfo {
  final bool isLane;
  final String label;
  final double y;
  final double h;
  final GanttWorkstream? ws;

  const _RowInfo({
    required this.isLane,
    required this.label,
    required this.y,
    required this.h,
    this.ws,
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
    default:            return KColors.border2; // not_started
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

// ---------------------------------------------------------------------------
// Event dot colours — category overrides type default
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

// Colour used for linked-action dotted lines
const _kLinkColor = Color(0xFF00D4FF);

// ---------------------------------------------------------------------------
// GanttChart widget
// ---------------------------------------------------------------------------

class GanttChart extends StatefulWidget {
  final List<GanttWorkstream> workstreams;
  final List<TimelineEvent> events;
  final void Function(TimelineEvent)? onEventTap;

  const GanttChart({
    super.key,
    required this.workstreams,
    required this.events,
    this.onEventTap,
  });

  @override
  State<GanttChart> createState() => _GanttChartState();
}

// Dot position for hit-testing
class _DotHit {
  final double x;
  final double y;
  final TimelineEvent event;
  const _DotHit(this.x, this.y, this.event);
}

class _GanttChartState extends State<GanttChart> {
  final ScrollController _hScroll = ScrollController();
  List<_DotHit> _dotHits = [];
  bool _scrolledToToday = false;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
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
      // Show today with ~120px of left context
      final target = (todayX - 120).clamp(0.0, _hScroll.position.maxScrollExtent);
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

  void _handleTap(Offset localPos) {
    if (widget.onEventTap == null) return;
    for (final dot in _dotHits) {
      if ((localPos - Offset(dot.x, dot.y)).distance <= 12) {
        widget.onEventTap!(dot.event);
        return;
      }
    }
  }

  List<_RowInfo> _buildRows() {
    final Map<String, List<GanttWorkstream>> laneMap = {};
    for (final ws in widget.workstreams) {
      laneMap.putIfAbsent(ws.lane, () => []).add(ws);
    }

    final rows = <_RowInfo>[];
    double y = _kHeaderH;
    for (final lane in laneMap.keys.toList()..sort()) {
      rows.add(_RowInfo(isLane: true, label: lane, y: y, h: _kLaneH));
      y += _kLaneH;
      for (final ws in laneMap[lane]!) {
        rows.add(_RowInfo(isLane: false, label: ws.name, y: y, h: _kRowH, ws: ws));
        y += _kRowH;
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
    }
    for (final ev in widget.events) {
      if (ev.date != null) {
        final d = DateTime(ev.date!.year, ev.date!.month, ev.date!.day)
            .add(const Duration(days: 14));
        if (d.isAfter(winEnd)) winEnd = d;
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

    _scrollToToday(winStart);

    final rightCanvas = SizedBox(
      width: canvasW,
      height: totalH,
      child: CustomPaint(
        painter: _RightPainter(
          rows: rows,
          allWorkstreams: widget.workstreams,
          events: widget.events,
          winStart: winStart,
          totalDays: totalDays,
          pxPerDay: _kPxPerDay,
          todayNorm: todayNorm,
          totalH: totalH,
        ),
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
                child: widget.onEventTap != null
                    ? GestureDetector(
                        onTapUp: (d) => _handleTap(d.localPosition),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: rightCanvas,
                        ),
                      )
                    : rightCanvas,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Left panel painter — lane headers + workstream labels
// ---------------------------------------------------------------------------

class _LeftPainter extends CustomPainter {
  final List<_RowInfo> rows;
  final double totalH;

  const _LeftPainter({required this.rows, required this.totalH});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = KColors.surface);

    // Date header zone
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, _kHeaderH),
        Paint()..color = KColors.surface2);

    for (final row in rows) {
      if (row.isLane) {
        canvas.drawRect(
          Rect.fromLTWH(0, row.y, size.width, row.h),
          Paint()..color = KColors.amberDim,
        );
        _drawText(canvas, row.label.toUpperCase(),
            const TextStyle(
                color: KColors.amber,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1),
            Offset(10, row.y + (row.h - 10) / 2),
            maxWidth: size.width - 14);
      } else {
        final ws = row.ws!;
        // Status dot
        canvas.drawCircle(Offset(10, row.y + row.h / 2), 4,
            Paint()..color = _statusDot(ws.status));
        // Name
        _drawText(canvas, ws.name,
            const TextStyle(
                color: KColors.text, fontSize: 11, fontWeight: FontWeight.w500),
            Offset(22, row.y + (row.h - 12) / 2),
            maxWidth: size.width - 28);
        // Row separator
        canvas.drawLine(Offset(0, row.y + row.h), Offset(size.width, row.y + row.h),
            Paint()
              ..color = KColors.border
              ..strokeWidth = 0.5);
      }
    }

    // Events label
    final evY = rows.isEmpty ? _kHeaderH : rows.last.y + rows.last.h;
    _drawText(canvas, 'EVENTS',
        const TextStyle(
            color: KColors.textMuted,
            fontSize: 9,
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
// Right panel painter — bars, grid, arrows, events
// ---------------------------------------------------------------------------

class _RightPainter extends CustomPainter {
  final List<_RowInfo> rows;
  final List<GanttWorkstream> allWorkstreams;
  final List<TimelineEvent> events;
  final DateTime winStart;
  final int totalDays;
  final double pxPerDay;
  final DateTime todayNorm;
  final double totalH;

  const _RightPainter({
    required this.rows,
    required this.allWorkstreams,
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
    _drawDependencyArrows(canvas, size);
    _drawTodayLine(canvas, size);
    _drawEvents(canvas, size);
    _drawDateHeader(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1C2A38)
      ..strokeWidth = 0.5;

    // Alternating row background
    for (final row in rows) {
      if (!row.isLane) {
        final idx = rows.where((r) => !r.isLane).toList().indexOf(row);
        if (idx.isEven) {
          canvas.drawRect(
            Rect.fromLTWH(0, row.y, size.width, row.h),
            Paint()..color = const Color(0xFF0C1820),
          );
        }
      }
    }

    // Week vertical lines
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
    // Header background
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
    final weekStyle = const TextStyle(color: Color(0xFF4A6070), fontSize: 8);

    DateTime cursor = winStart;
    String? lastMonth;
    while (!cursor.isAfter(winStart.add(Duration(days: totalDays)))) {
      final x = _xFor(cursor);
      if (cursor.day == 1) {
        final label =
            '${_monthAbbr(cursor.month)} ${cursor.year}';
        if (label != lastMonth) {
          lastMonth = label;
          _drawText(canvas, label, monthStyle, Offset(x + 3, 4),
              maxWidth: 72);
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
      if (row.isLane || row.ws == null) continue;
      final ws = row.ws!;
      if (ws.start == null || ws.end == null) {
        // Undated — draw a dashed placeholder
        _drawUndatedBar(canvas, row);
        continue;
      }

      final x1 = _xFor(ws.start!);
      final x2 = _xFor(ws.end!.add(const Duration(days: 1)));
      final barW = (x2 - x1).clamp(4.0, double.infinity);
      final barY = row.y + (row.h - _kBarH) / 2;

      final fillRect = Rect.fromLTWH(x1, barY, barW, _kBarH);

      // Fill
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(3)),
        Paint()..color = _barFill(ws.status),
      );
      // Stroke
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(3)),
        Paint()
          ..color = _barStroke(ws.status)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );

      // Label inside bar if wide enough
      if (barW > 40) {
        _drawText(
          canvas,
          ws.name,
          TextStyle(
              color: ws.status == 'not_started'
                  ? KColors.textDim
                  : _barStroke(ws.status),
              fontSize: 9,
              fontWeight: FontWeight.w600),
          Offset(x1 + 5, barY + (_kBarH - 10) / 2),
          maxWidth: barW - 8,
        );
      }
    }
  }

  void _drawUndatedBar(Canvas canvas, _RowInfo row) {
    final barY = row.y + (row.h - _kBarH) / 2;
    const dashW = 20.0;
    const gapW = 6.0;
    double x = 8;
    final paint = Paint()
      ..color = KColors.border2
      ..strokeWidth = 1;
    while (x < 120) {
      canvas.drawLine(Offset(x, barY + _kBarH / 2),
          Offset(math.min(x + dashW, 120), barY + _kBarH / 2), paint);
      x += dashW + gapW;
    }
    _drawText(canvas, 'no dates set',
        const TextStyle(color: KColors.textMuted, fontSize: 9),
        Offset(8, barY + (_kBarH - 10) / 2),
        maxWidth: 100);
  }

  void _drawDependencyArrows(Canvas canvas, Size size) {
    // Build a lookup from id → row
    final Map<String, _RowInfo> wsRows = {};
    for (final row in rows) {
      if (!row.isLane && row.ws != null) wsRows[row.ws!.id] = row;
    }

    final arrowPaint = Paint()
      ..color = KColors.amber.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final toRow in rows) {
      if (toRow.isLane || toRow.ws == null) continue;
      final toWs = toRow.ws!;
      if (toWs.dependsOnIds.isEmpty || toWs.start == null) continue;

      for (final fromId in toWs.dependsOnIds) {
        final fromRow = wsRows[fromId];
        if (fromRow == null || fromRow.ws?.end == null) continue;

        final x1 = _xFor(fromRow.ws!.end!.add(const Duration(days: 1)));
        final y1 = fromRow.y + fromRow.h / 2;
        final x2 = _xFor(toWs.start!);
        final y2 = toRow.y + toRow.h / 2;

        const margin = 10.0;
        final midX = x1 + margin;

        final path = Path()
          ..moveTo(x1, y1)
          ..lineTo(midX, y1)
          ..lineTo(midX, y2)
          ..lineTo(x2, y2);
        canvas.drawPath(path, arrowPaint);

        // Arrowhead
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
    canvas.drawPath(path, Paint()..color = paint.color..style = PaintingStyle.fill);
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
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + dash, size.height)), paint);
      y += dash + gap;
    }

    _drawText(canvas, 'Today',
        const TextStyle(color: KColors.amber, fontSize: 8, fontWeight: FontWeight.w700),
        Offset(x - 14, _kHeaderH + 3),
        maxWidth: 36);
  }

  void _drawEvents(Canvas canvas, Size size) {
    final evY = rows.isEmpty ? _kHeaderH : rows.last.y + rows.last.h;

    // Event strip separator
    canvas.drawLine(Offset(0, evY), Offset(size.width, evY),
        Paint()
          ..color = KColors.border
          ..strokeWidth = 0.5);

    // Axis line in middle of strip
    final axisY = evY + _kEventH / 2;
    canvas.drawLine(Offset(0, axisY), Offset(size.width, axisY),
        Paint()
          ..color = const Color(0xFF1C2A38)
          ..strokeWidth = 1.0);

    // Draw dots — collect positions for linked-line rendering
    final placed = <double>[];
    final dotPositions = <String, Offset>{}; // action id -> dot centre

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

    // Draw dotted lines between linked actions
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
      final seg = math.min(traveled + (drawing ? dashLen : gapLen), dist);
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
      old.allWorkstreams != allWorkstreams;
}
