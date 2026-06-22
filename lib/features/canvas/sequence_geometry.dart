import 'dart:ui' show Offset, Rect;

/// Pure geometry for sequence-arrow rendering. Lifted out of the painter
/// so it can be unit-tested without spinning up a Canvas.
class SequenceGeometry {
  /// Returns the point where the directed line from [from] to [target]
  /// first crosses the boundary of [rect], walking from [from] toward
  /// [target].
  ///
  /// In Canvas terms: [from] is the source card's centre, [target] is
  /// the target card's centre (inside [rect]), and we want the point on
  /// the target's edge where the arrow should terminate so the arrowhead
  /// lands just outside the target card rather than masked behind it.
  ///
  /// Returns [target] unchanged if the line doesn't cross any edge of
  /// [rect] in the (0, 1] parametric range (e.g. when [from] is already
  /// inside [rect], or when [from] equals [target]).
  static Offset clipLineToRect(Offset from, Offset target, Rect rect) {
    final dx = target.dx - from.dx;
    final dy = target.dy - from.dy;
    if (dx == 0 && dy == 0) return target;

    // For each edge, compute the parameter t where the parametric line
    // from-to-target crosses it. We want the smallest t in (0, 1] that
    // lands on the edge's extent — that's the first edge encountered
    // when walking from `from` toward `target`.
    const eps = 0.001;
    double minT = double.infinity;

    void consider(double t, double along, double minBound, double maxBound) {
      if (t <= 0 || t > 1) return;
      if (along < minBound - eps || along > maxBound + eps) return;
      if (t < minT) minT = t;
    }

    if (dx != 0) {
      // Left edge: x = rect.left
      final tL = (rect.left - from.dx) / dx;
      consider(tL, from.dy + tL * dy, rect.top, rect.bottom);
      // Right edge: x = rect.right
      final tR = (rect.right - from.dx) / dx;
      consider(tR, from.dy + tR * dy, rect.top, rect.bottom);
    }
    if (dy != 0) {
      // Top edge: y = rect.top
      final tT = (rect.top - from.dy) / dy;
      consider(tT, from.dx + tT * dx, rect.left, rect.right);
      // Bottom edge: y = rect.bottom
      final tB = (rect.bottom - from.dy) / dy;
      consider(tB, from.dx + tB * dx, rect.left, rect.right);
    }

    if (minT == double.infinity) return target;
    return Offset(from.dx + minT * dx, from.dy + minT * dy);
  }
}
