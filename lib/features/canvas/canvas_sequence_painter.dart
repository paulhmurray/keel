import 'package:flutter/material.dart';

import '../../core/database/database.dart';
import '../../shared/theme/keel_colors.dart';
import 'canvas_constants.dart';
import 'sequence_geometry.dart';

/// Painter that renders directional sequence arrows between cards inside a
/// single band. Sequences spanning bands aren't drawn (the bands scroll
/// independently in the current layout) — for those, the editor can still
/// show "↳ leads to: …" in metadata.
class CanvasSequencePainter extends CustomPainter {
  final List<CanvasCard> cards;
  final List<CanvasSequence> sequences;
  final String? draggingCardId;

  CanvasSequencePainter({
    required this.cards,
    required this.sequences,
    this.draggingCardId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cardById = {for (final c in cards) c.id: c};
    final paint = Paint()
      ..color = KColors.amber.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final seq in sequences) {
      final from = cardById[seq.fromCardId];
      final to = cardById[seq.toCardId];
      if (from == null || to == null) continue;
      // Only draw if both cards are in the band currently being painted
      // (the caller pre-filters this list).
      if (from.band != to.band) continue;

      final fromSize = CanvasCardDimensions.forSize(from.size);
      final toSize = CanvasCardDimensions.forSize(to.size);
      final fromRect = Rect.fromLTWH(
        from.positionX.toDouble(),
        from.positionY.toDouble(),
        fromSize.width,
        fromSize.height,
      );
      final toRect = Rect.fromLTWH(
        to.positionX.toDouble(),
        to.positionY.toDouble(),
        toSize.width,
        toSize.height,
      );
      final fromCentre = fromRect.center;
      final toCentre = toRect.center;
      // Clip both endpoints to the card edges. The visible line was
      // already only the bit between the cards (the painter sits behind
      // them in the stack), but the arrowhead used to land at the
      // target's centre — inside the card — so it was masked. Clipping
      // puts the head right at the target's edge where it can be seen.
      final start = SequenceGeometry.clipLineToRect(
          toCentre, fromCentre, fromRect);
      final end = SequenceGeometry.clipLineToRect(
          fromCentre, toCentre, toRect);
      _drawArrow(canvas, paint, start, end);
    }
  }

  void _drawArrow(Canvas canvas, Paint paint, Offset from, Offset to) {
    canvas.drawLine(from, to, paint);

    // Arrowhead — small triangle at the 'to' end.
    final direction = (to - from);
    final length = direction.distance;
    if (length < 6) return;
    final unit = direction / length;
    const headLen = 8.0;
    const headAngle = 0.5; // ≈ 28°
    final left = to -
        Offset(
          unit.dx * headLen * 1.4 - unit.dy * headLen * headAngle,
          unit.dy * headLen * 1.4 + unit.dx * headLen * headAngle,
        );
    final right = to -
        Offset(
          unit.dx * headLen * 1.4 + unit.dy * headLen * headAngle,
          unit.dy * headLen * 1.4 - unit.dx * headLen * headAngle,
        );
    final fill = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant CanvasSequencePainter old) {
    return old.cards != cards ||
        old.sequences != sequences ||
        old.draggingCardId != draggingCardId;
  }
}
