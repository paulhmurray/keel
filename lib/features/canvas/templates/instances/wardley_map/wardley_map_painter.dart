import 'package:flutter/material.dart';

import '../../../../../shared/theme/keel_colors.dart';
import 'wardley_map_model.dart';

/// Paints the Wardley grid backdrop: four evolution bands (Genesis,
/// Custom-Built, Product, Commodity) with dividers, plus the Y-axis
/// "value chain" guide. Component nodes + labels are widgets on top.
class WardleyGridPainter extends CustomPainter {
  const WardleyGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final divider = Paint()
      ..color = KColors.border.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    // Three vertical dividers at the quarter lines.
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), divider);
    }
    // Faint alternating band shading to separate the stages.
    final shade = Paint()..color = KColors.surface2.withValues(alpha: 0.25);
    for (var i = 0; i < 4; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(size.width * i / 4, 0, size.width / 4, size.height),
        shade,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WardleyGridPainter oldDelegate) => false;
}

/// Paints the directed dependency edges between component nodes. A line
/// runs from each component to the thing it needs, with a small arrowhead
/// at the dependency end. [highlightId] fades edges not touching that
/// component so a selection's chain stands out.
class WardleyDependencyPainter extends CustomPainter {
  final List<WardleyComponent> components;
  final List<WardleyDependency> dependencies;
  final String? highlightId;

  const WardleyDependencyPainter({
    required this.components,
    required this.dependencies,
    this.highlightId,
  });

  static const double _nodeRadius = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final c in components) c.id: c};
    for (final dep in dependencies) {
      final from = byId[dep.fromComponentId];
      final to = byId[dep.toComponentId];
      if (from == null || to == null) continue;

      final touches = highlightId == null ||
          dep.fromComponentId == highlightId ||
          dep.toComponentId == highlightId;
      final alpha = touches ? 0.7 : 0.18;

      final a = Offset(from.positionX * size.width, from.positionY * size.height);
      final b = Offset(to.positionX * size.width, to.positionY * size.height);
      final dir = b - a;
      final len = dir.distance;
      if (len < _nodeRadius * 2 + 2) continue;
      final unit = dir / len;
      // Stop the line at each node's edge, not its centre.
      final start = a + unit * _nodeRadius;
      final end = b - unit * _nodeRadius;

      final paint = Paint()
        ..color = KColors.amber.withValues(alpha: alpha)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      canvas.drawLine(start, end, paint);
      _arrowHead(canvas, end, unit, paint.color);
    }
  }

  void _arrowHead(Canvas canvas, Offset tip, Offset unit, Color color) {
    const headLen = 8.0;
    const spread = 4.0;
    final perp = Offset(-unit.dy, unit.dx);
    final base = tip - unit * headLen;
    final left = base + perp * spread;
    final right = base - perp * spread;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant WardleyDependencyPainter old) =>
      old.components != components ||
      old.dependencies != dependencies ||
      old.highlightId != highlightId;
}
