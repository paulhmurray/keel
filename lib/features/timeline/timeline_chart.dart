import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';

// Parses a '#RRGGBB' hex string to a Flutter Color.
Color parseHexColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

// ---------------------------------------------------------------------------
// Public model
// ---------------------------------------------------------------------------

enum TimelineEventType { action, decision, issue, dependency }

class TimelineEvent {
  final String? id;            // DB action id — used for linked-line lookup
  final String title;
  final String? ref;
  final DateTime? date;
  final TimelineEventType type;
  final String? owner;
  final Object? item;          // original DB object for tap handlers
  final Color? categoryColor;  // overrides default type colour in charts
  final String? linkedActionId; // draws a dotted line to this action in Gantt

  const TimelineEvent({
    this.id,
    required this.title,
    this.ref,
    this.date,
    required this.type,
    this.owner,
    this.item,
    this.categoryColor,
    this.linkedActionId,
  });
}

// ---------------------------------------------------------------------------
// Colour helpers
// ---------------------------------------------------------------------------

Color _colorForEventType(TimelineEventType t, {bool overdue = false}) {
  if (overdue) return KColors.red;
  switch (t) {
    case TimelineEventType.action:
      return KColors.amber;
    case TimelineEventType.decision:
      return KColors.blue;
    case TimelineEventType.issue:
      return KColors.amber;
    case TimelineEventType.dependency:
      return KColors.phosphor;
  }
}

// ---------------------------------------------------------------------------
// TimelineChart widget
// ---------------------------------------------------------------------------

class TimelineChart extends StatefulWidget {
  final List<TimelineEvent> events;
  final double height;
  final bool compact;

  const TimelineChart({
    super.key,
    required this.events,
    this.height = 220,
    this.compact = false,
  });

  @override
  State<TimelineChart> createState() => _TimelineChartState();
}

class _TimelineChartState extends State<TimelineChart> {
  final ScrollController _scrollController = ScrollController();
  bool _scrolledToToday = false;

  // Tooltip state for compact mode
  String? _tooltipText;
  Offset? _tooltipPos;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToToday(DateTime windowStart) {
    if (_scrolledToToday) return;
    _scrolledToToday = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      const pxPerDay = 12.0;
      final today = DateTime.now();
      final todayNorm = DateTime(today.year, today.month, today.day);
      final daysFromStart = todayNorm.difference(windowStart).inDays;
      final todayX = daysFromStart * pxPerDay;
      // Centre today with a ~120px left margin so context is visible
      final target = (todayX - 120).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);

    // Compute time window
    final DateTime windowStart;
    final DateTime windowEnd;
    if (widget.compact) {
      windowStart = todayNorm.subtract(const Duration(days: 7));
      windowEnd = todayNorm.add(const Duration(days: 49));
    } else {
      windowStart = todayNorm.subtract(const Duration(days: 14));
      DateTime latestEvent = todayNorm.add(const Duration(days: 90));
      for (final e in widget.events) {
        if (e.date != null) {
          final ed = DateTime(e.date!.year, e.date!.month, e.date!.day);
          if (ed.isAfter(latestEvent)) latestEvent = ed;
        }
      }
      windowEnd = latestEvent.add(const Duration(days: 14));
    }

    final totalDays = windowEnd.difference(windowStart).inDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.compact)
          _buildCompactChart(context, todayNorm, windowStart, windowEnd, totalDays)
        else
          _buildScrollableChart(context, todayNorm, windowStart, windowEnd, totalDays),
        const SizedBox(height: 8),
        _LegendRow(compact: widget.compact),
      ],
    );
  }

  // ---- Compact chart -------------------------------------------------------

  Widget _buildCompactChart(
    BuildContext context,
    DateTime todayNorm,
    DateTime windowStart,
    DateTime windowEnd,
    int totalDays,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final pxPerDay = availableWidth / totalDays;
        final chartHeight = widget.height;

        final placedDots = _computePlacedDots(
          todayNorm: todayNorm,
          windowStart: windowStart,
          windowEnd: windowEnd,
          totalDays: totalDays,
          pxPerDay: pxPerDay,
          chartHeight: chartHeight,
          compact: true,
        );

        return MouseRegion(
          onHover: (event) => _handleHover(event.localPosition, placedDots),
          onExit: (_) => setState(() {
            _tooltipText = null;
            _tooltipPos = null;
          }),
          child: Stack(
            children: [
              SizedBox(
                width: availableWidth,
                height: chartHeight,
                child: CustomPaint(
                  painter: _TimelinePainter(
                    todayNorm: todayNorm,
                    windowStart: windowStart,
                    windowEnd: windowEnd,
                    totalDays: totalDays,
                    pxPerDay: pxPerDay,
                    chartHeight: chartHeight,
                    compact: true,
                    placedDots: placedDots,
                  ),
                ),
              ),
              if (_tooltipText != null && _tooltipPos != null)
                _buildTooltipOverlay(availableWidth, chartHeight),
            ],
          ),
        );
      },
    );
  }

  void _handleHover(Offset localPos, List<_PlacedDot> placedDots) {
    for (final dot in placedDots) {
      final dx = localPos.dx - dot.x;
      final dy = localPos.dy - dot.y;
      if (math.sqrt(dx * dx + dy * dy) <= 10) {
        setState(() {
          _tooltipText = dot.label;
          _tooltipPos = Offset(dot.x, dot.y);
        });
        return;
      }
    }
    setState(() {
      _tooltipText = null;
      _tooltipPos = null;
    });
  }

  Widget _buildTooltipOverlay(double availableWidth, double chartHeight) {
    final pos = _tooltipPos!;
    const tooltipWidth = 160.0;
    const tooltipHeight = 32.0;
    double left = pos.dx - tooltipWidth / 2;
    double top = pos.dy - tooltipHeight - 8;
    if (left < 0) left = 0;
    if (left + tooltipWidth > availableWidth) left = availableWidth - tooltipWidth;
    if (top < 0) top = pos.dy + 12;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: tooltipWidth,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2A38),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF2E4057)),
          ),
          child: Text(
            _tooltipText!,
            style: const TextStyle(
              color: Color(0xFFE0E8F0),
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // ---- Full scrollable chart -----------------------------------------------

  Widget _buildScrollableChart(
    BuildContext context,
    DateTime todayNorm,
    DateTime windowStart,
    DateTime windowEnd,
    int totalDays,
  ) {
    const pxPerDay = 12.0;
    final paintWidth = totalDays * pxPerDay;
    _scrollToToday(windowStart);
    final chartHeight = widget.height;

    final placedDots = _computePlacedDots(
      todayNorm: todayNorm,
      windowStart: windowStart,
      windowEnd: windowEnd,
      totalDays: totalDays,
      pxPerDay: pxPerDay,
      chartHeight: chartHeight,
      compact: false,
    );

    return ClipRect(
      child: SizedBox(
        height: chartHeight,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: paintWidth,
              height: chartHeight,
              child: CustomPaint(
                painter: _TimelinePainter(
                  todayNorm: todayNorm,
                  windowStart: windowStart,
                  windowEnd: windowEnd,
                  totalDays: totalDays,
                  pxPerDay: pxPerDay,
                  chartHeight: chartHeight,
                  compact: false,
                  placedDots: placedDots,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Compute dot positions -----------------------------------------------

  List<_PlacedDot> _computePlacedDots({
    required DateTime todayNorm,
    required DateTime windowStart,
    required DateTime windowEnd,
    required int totalDays,
    required double pxPerDay,
    required double chartHeight,
    required bool compact,
  }) {
    final axisY = chartHeight / 2;
    final dotRadius = compact ? 5.0 : 6.0;

    // Filter events that fall in the window
    final eventsInWindow = <TimelineEvent>[];
    for (final e in widget.events) {
      if (e.date == null) continue;
      final ed = DateTime(e.date!.year, e.date!.month, e.date!.day);
      if (ed.isBefore(windowStart) || ed.isAfter(windowEnd)) continue;
      eventsInWindow.add(e);
    }

    // Sort by date so overlap algorithm is deterministic
    eventsInWindow.sort((a, b) {
      final ad = a.date!;
      final bd = b.date!;
      return ad.compareTo(bd);
    });

    // Place dots alternating above/below
    final placed = <_PlacedDot>[];
    // Track placements per side to detect overlap
    final abovePlacements = <double>[]; // x positions placed above
    final belowPlacements = <double>[]; // x positions placed below

    for (int i = 0; i < eventsInWindow.length; i++) {
      final e = eventsInWindow[i];
      final ed = DateTime(e.date!.year, e.date!.month, e.date!.day);
      final daysFromStart = ed.difference(windowStart).inDays;
      final x = daysFromStart * pxPerDay + pxPerDay / 2;

      final isPast = ed.isBefore(todayNorm);
      final isOverdue = isPast;
      final color = _colorForEventType(e.type, overdue: isOverdue);
      final opacity = isPast ? 0.6 : 1.0;

      // Determine which side to place on
      final preferAbove = i.isEven;
      bool placeAbove;

      if (preferAbove) {
        // Check if overlap above (within 14px)
        final hasOverlapAbove = abovePlacements.any((px) => (px - x).abs() < 14);
        if (hasOverlapAbove) {
          placeAbove = false; // flip to below
        } else {
          placeAbove = true;
        }
      } else {
        // Check if overlap below
        final hasOverlapBelow = belowPlacements.any((px) => (px - x).abs() < 14);
        if (hasOverlapBelow) {
          placeAbove = true; // flip to above
        } else {
          placeAbove = false;
        }
      }

      // Calculate y offset from axis
      // Stack further if still overlapping on chosen side
      final chosenPlacements = placeAbove ? abovePlacements : belowPlacements;
      while (chosenPlacements.any((px) => (px - x).abs() < 14)) {
        // Flip to the opposite side if still overlapping
        placeAbove = !placeAbove;
        break;
      }

      final offsetFromAxis = dotRadius + 8 + (placeAbove ? 0 : 0);
      final y = placeAbove
          ? axisY - offsetFromAxis
          : axisY + offsetFromAxis;

      // Clamp y to chart bounds
      final yFinal = y.clamp(dotRadius + 2, chartHeight - dotRadius - 2);

      if (placeAbove) {
        abovePlacements.add(x);
      } else {
        belowPlacements.add(x);
      }

      final label = (e.ref != null && e.ref!.isNotEmpty)
          ? '${e.ref} ${e.title}'
          : e.title;
      final shortLabel = label.length > 18 ? '${label.substring(0, 18)}…' : label;

      placed.add(_PlacedDot(
        x: x,
        y: yFinal,
        color: color,
        opacity: opacity,
        label: shortLabel,
        fullLabel: label,
        aboveAxis: placeAbove,
        dotRadius: dotRadius,
      ));
    }

    return placed;
  }
}

// ---------------------------------------------------------------------------
// Data class for placed dots
// ---------------------------------------------------------------------------

class _PlacedDot {
  final double x;
  final double y;
  final Color color;
  final double opacity;
  final String label;
  final String fullLabel;
  final bool aboveAxis;
  final double dotRadius;

  const _PlacedDot({
    required this.x,
    required this.y,
    required this.color,
    required this.opacity,
    required this.label,
    required this.fullLabel,
    required this.aboveAxis,
    required this.dotRadius,
  });
}

// ---------------------------------------------------------------------------
// CustomPainter
// ---------------------------------------------------------------------------

class _TimelinePainter extends CustomPainter {
  final DateTime todayNorm;
  final DateTime windowStart;
  final DateTime windowEnd;
  final int totalDays;
  final double pxPerDay;
  final double chartHeight;
  final bool compact;
  final List<_PlacedDot> placedDots;

  const _TimelinePainter({
    required this.todayNorm,
    required this.windowStart,
    required this.windowEnd,
    required this.totalDays,
    required this.pxPerDay,
    required this.chartHeight,
    required this.compact,
    required this.placedDots,
  });

  double _xForDate(DateTime d) {
    final days = d.difference(windowStart).inDays;
    return days * pxPerDay + pxPerDay / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final axisY = size.height / 2;

    // 1. Grid lines & labels
    _drawGridAndLabels(canvas, size, axisY);

    // 2. Axis line
    final axisPaint = Paint()
      ..color = const Color(0xFF2E4057)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, axisY), Offset(size.width, axisY), axisPaint);

    // 3. Today line
    final todayX = _xForDate(todayNorm);
    if (todayX >= 0 && todayX <= size.width) {
      _drawTodayLine(canvas, size, todayX, axisY);
    }

    // 4. Event dots
    for (final dot in placedDots) {
      _drawDot(canvas, dot);
    }

    // 5. Labels (full mode only)
    if (!compact) {
      for (final dot in placedDots) {
        _drawDotLabel(canvas, size, dot, axisY);
      }
    }
  }

  void _drawGridAndLabels(Canvas canvas, Size size, double axisY) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1C2A38)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final monthLabelStyle = TextStyle(
      color: const Color(0xFF8EA8C0).withValues(alpha: 0.8),
      fontSize: compact ? 9.0 : 10.0,
      fontWeight: FontWeight.w500,
    );
    final weekLabelStyle = TextStyle(
      color: const Color(0xFF4A6070),
      fontSize: compact ? 8.0 : 9.0,
    );

    // Iterate over days in the window, find week and month starts
    DateTime cursor = windowStart;
    String? lastMonth;

    while (!cursor.isAfter(windowEnd)) {
      final x = _xForDate(cursor);

      // Week start (Monday)
      if (cursor.weekday == DateTime.monday) {
        // Vertical grid line
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

        if (!compact) {
          // Week tick mark below axis
          final tickPaint = Paint()
            ..color = const Color(0xFF2E4057)
            ..strokeWidth = 1.0;
          canvas.drawLine(
            Offset(x, axisY + 4),
            Offset(x, axisY + 8),
            tickPaint,
          );

          // Week label (dd/mm) below axis
          final weekStr =
              '${cursor.day.toString().padLeft(2, '0')}/${cursor.month.toString().padLeft(2, '0')}';
          _drawText(
            canvas,
            weekStr,
            weekLabelStyle,
            Offset(x + 2, axisY + 10),
            maxWidth: pxPerDay * 7 - 4,
          );
        } else {
          // Compact: just a small week tick
          final tickPaint = Paint()
            ..color = const Color(0xFF2E4057)
            ..strokeWidth = 1.0;
          canvas.drawLine(
            Offset(x, axisY - 3),
            Offset(x, axisY + 3),
            tickPaint,
          );
        }
      }

      // Month start
      if (cursor.day == 1) {
        final monthName = _monthAbbr(cursor.month);
        if (monthName != lastMonth) {
          lastMonth = monthName;
          if (!compact) {
            // Month name above axis
            final label = '$monthName ${cursor.year}';
            _drawText(
              canvas,
              label,
              monthLabelStyle,
              Offset(x + 2, 4),
              maxWidth: 60,
            );
          } else {
            // Compact: small month label above axis
            _drawText(
              canvas,
              monthName,
              weekLabelStyle,
              Offset(x + 2, 4),
              maxWidth: 28,
            );
          }
        }
      }

      cursor = cursor.add(const Duration(days: 1));
    }
  }

  void _drawTodayLine(Canvas canvas, Size size, double x, double axisY) {
    final paint = Paint()
      ..color = KColors.amber
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Dashed line
    const dashHeight = 5.0;
    const gapHeight = 3.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dashHeight, size.height)),
        paint,
      );
      y += dashHeight + gapHeight;
    }

    // "Today" label
    const labelStyle = TextStyle(
      color: KColors.amber,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    _drawText(
      canvas,
      'Today',
      labelStyle,
      Offset(x - 12, compact ? 14 : 16),
      maxWidth: 36,
    );
  }

  void _drawDot(Canvas canvas, _PlacedDot dot) {
    final paint = Paint()
      ..color = dot.color.withValues(alpha: dot.opacity)
      ..style = PaintingStyle.fill;

    // Clip to canvas
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, totalDays * pxPerDay, chartHeight));

    canvas.drawCircle(Offset(dot.x, dot.y), dot.dotRadius, paint);

    // Subtle border
    final borderPaint = Paint()
      ..color = dot.color.withValues(alpha: dot.opacity * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(dot.x, dot.y), dot.dotRadius, borderPaint);

    canvas.restore();
  }

  void _drawDotLabel(Canvas canvas, Size size, _PlacedDot dot, double axisY) {
    const labelStyle = TextStyle(
      color: Color(0xFF8EA8C0),
      fontSize: 10,
    );

    final offsetY = dot.aboveAxis
        ? dot.y - dot.dotRadius - 11
        : dot.y + dot.dotRadius + 2;

    // Clip label to canvas bounds
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    _drawText(
      canvas,
      dot.label,
      labelStyle,
      Offset(dot.x - 20, offsetY),
      maxWidth: 50,
    );
    canvas.restore();
  }

  void _drawText(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset offset, {
    double maxWidth = 100,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  String _monthAbbr(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) {
    return oldDelegate.placedDots != placedDots ||
        oldDelegate.compact != compact ||
        oldDelegate.chartHeight != chartHeight;
  }
}

// ---------------------------------------------------------------------------
// Legend row
// ---------------------------------------------------------------------------

class _LegendRow extends StatelessWidget {
  final bool compact;

  const _LegendRow({required this.compact});

  @override
  Widget build(BuildContext context) {
    const items = [
      (label: 'Actions', color: KColors.amber),
      (label: 'Decisions', color: KColors.blue),
      (label: 'Issues', color: KColors.amber),
      (label: 'Dependencies', color: KColors.phosphor),
      (label: 'Overdue', color: KColors.red),
    ];

    return Wrap(
      spacing: compact ? 10 : 16,
      runSpacing: 4,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: item.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              item.label,
              style: TextStyle(
                color: const Color(0xFF8EA8C0),
                fontSize: compact ? 10 : 11,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
