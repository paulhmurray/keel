import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/sequence_geometry.dart';

void main() {
  // A card-sized rect at (100, 100) with the default medium card dims.
  final cardRect = Rect.fromLTWH(100, 100, 240, 160);
  final cardCentre = cardRect.center; // (220, 180)

  group('clipLineToRect', () {
    test('horizontal approach from the left clips at the left edge', () {
      final from = const Offset(0, 180); // dead-level with the centre
      final clipped =
          SequenceGeometry.clipLineToRect(from, cardCentre, cardRect);
      expect(clipped.dx, closeTo(100, 0.01));
      expect(clipped.dy, closeTo(180, 0.01));
    });

    test('horizontal approach from the right clips at the right edge', () {
      final from = const Offset(600, 180);
      final clipped =
          SequenceGeometry.clipLineToRect(from, cardCentre, cardRect);
      expect(clipped.dx, closeTo(340, 0.01));
      expect(clipped.dy, closeTo(180, 0.01));
    });

    test('vertical approach from above clips at the top edge', () {
      final from = const Offset(220, 0);
      final clipped =
          SequenceGeometry.clipLineToRect(from, cardCentre, cardRect);
      expect(clipped.dx, closeTo(220, 0.01));
      expect(clipped.dy, closeTo(100, 0.01));
    });

    test('vertical approach from below clips at the bottom edge', () {
      final from = const Offset(220, 500);
      final clipped =
          SequenceGeometry.clipLineToRect(from, cardCentre, cardRect);
      expect(clipped.dx, closeTo(220, 0.01));
      expect(clipped.dy, closeTo(260, 0.01));
    });

    test('oblique approach clips at the first edge encountered', () {
      // Coming from the top-left corner; the diagonal hits the top
      // edge before the left edge for this aspect ratio.
      final from = const Offset(0, 0);
      final clipped =
          SequenceGeometry.clipLineToRect(from, cardCentre, cardRect);
      // The line is y = (180/220) * x. It hits y = rect.top (100) at
      // x = 100 * 220/180 ≈ 122.22. That's inside the top edge (within
      // x in [100, 340]), so the top edge is hit first.
      expect(clipped.dx, closeTo(122.22, 0.05));
      expect(clipped.dy, closeTo(100, 0.01));
    });

    test('returns the target unchanged when from is inside the rect',
        () {
      final from = const Offset(200, 180); // inside cardRect
      final clipped =
          SequenceGeometry.clipLineToRect(from, cardCentre, cardRect);
      expect(clipped, cardCentre);
    });

    test('returns the target unchanged when from equals target', () {
      final clipped =
          SequenceGeometry.clipLineToRect(cardCentre, cardCentre, cardRect);
      expect(clipped, cardCentre);
    });

    test('symmetric: clipping target side gives a point on the target edge',
        () {
      // Pair of cards: target rect at (400, 100), source centre at (220, 180).
      final fromCentre = const Offset(220, 180);
      final tRect = Rect.fromLTWH(400, 100, 240, 160);
      final tCentre = tRect.center; // (520, 180)
      final end =
          SequenceGeometry.clipLineToRect(fromCentre, tCentre, tRect);
      // Horizontal approach — should clip exactly at target's left edge.
      expect(end.dx, closeTo(400, 0.01));
      expect(end.dy, closeTo(180, 0.01));
    });

    test(
        'symmetric: clipping the source side from the target gives a '
        'point on the source edge', () {
      // Walking from target centre back toward source centre, stop at
      // source rect's right edge.
      final fromCentre = const Offset(220, 180);
      final tCentre = const Offset(520, 180);
      final sourceRect = Rect.fromLTWH(100, 100, 240, 160);
      final start = SequenceGeometry.clipLineToRect(
          tCentre, fromCentre, sourceRect);
      expect(start.dx, closeTo(340, 0.01));
      expect(start.dy, closeTo(180, 0.01));
    });
  });
}
