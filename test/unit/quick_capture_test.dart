import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/quick_capture.dart';

void main() {
  group('QuickCaptureLayout.positionFor', () {
    test('first card lands at the origin', () {
      final p = QuickCaptureLayout.positionFor(0);
      expect(p, QuickCaptureLayout.origin);
    });

    test('cards cascade vertically within a column', () {
      final p1 = QuickCaptureLayout.positionFor(1);
      final p2 = QuickCaptureLayout.positionFor(2);
      expect(p1.dx, QuickCaptureLayout.origin.dx);
      expect(p1.dy,
          QuickCaptureLayout.origin.dy + QuickCaptureLayout.rowStep);
      expect(p2.dx, QuickCaptureLayout.origin.dx);
      expect(p2.dy,
          QuickCaptureLayout.origin.dy + 2 * QuickCaptureLayout.rowStep);
    });

    test('wraps to a new column once rowsPerColumn is full', () {
      final last = QuickCaptureLayout.positionFor(
          QuickCaptureLayout.rowsPerColumn - 1);
      final firstNextCol =
          QuickCaptureLayout.positionFor(QuickCaptureLayout.rowsPerColumn);
      expect(last.dx, QuickCaptureLayout.origin.dx);
      expect(firstNextCol.dx,
          QuickCaptureLayout.origin.dx + QuickCaptureLayout.columnStep);
      expect(firstNextCol.dy, QuickCaptureLayout.origin.dy);
    });

    test('negative index clamps to origin', () {
      expect(QuickCaptureLayout.positionFor(-1),
          QuickCaptureLayout.origin);
    });
  });

  group('QuickCaptureLayout.splitLines', () {
    test('null and empty input produce empty list', () {
      expect(QuickCaptureLayout.splitLines(null), isEmpty);
      expect(QuickCaptureLayout.splitLines(''), isEmpty);
      expect(QuickCaptureLayout.splitLines('   '), isEmpty);
    });

    test('single line produces a single trimmed entry', () {
      expect(QuickCaptureLayout.splitLines('  hello  '), ['hello']);
    });

    test('multi-line input produces one entry per non-blank line', () {
      final out = QuickCaptureLayout.splitLines(
          '  first\nsecond\n\n  \nthird  \n');
      expect(out, ['first', 'second', 'third']);
    });

    test('preserves line order', () {
      final out = QuickCaptureLayout.splitLines('alpha\nbeta\ngamma');
      expect(out, ['alpha', 'beta', 'gamma']);
    });
  });
}
