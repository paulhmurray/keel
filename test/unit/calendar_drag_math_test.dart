import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/calendar_drag_math.dart';

void main() {
  group('snapToDays', () {
    test('rounds to nearest whole day at the configured day width', () {
      // 28 px per day → 14 px is half a day; .round() picks 1.
      expect(CalendarDragMath.snapToDays(14, 28), 1);
      // Anything under half a day rounds down to 0.
      expect(CalendarDragMath.snapToDays(13, 28), 0);
      // Negative deltas snap the same way.
      expect(CalendarDragMath.snapToDays(-30, 28), -1);
      // 7 days forward.
      expect(CalendarDragMath.snapToDays(196, 28), 7);
    });

    test('returns 0 when dayWidth is non-positive', () {
      expect(CalendarDragMath.snapToDays(100, 0), 0);
      expect(CalendarDragMath.snapToDays(100, -5), 0);
    });
  });

  group('shift', () {
    test('preserves length exactly when moving forward', () {
      final start = DateTime(2026, 8, 1);
      final end = DateTime(2026, 8, 10);
      final r = CalendarDragMath.shift(start, end, 14);
      expect(r.start, DateTime(2026, 8, 15));
      expect(r.end, DateTime(2026, 8, 24));
      expect(
        r.end.difference(r.start),
        end.difference(start),
      );
    });

    test('preserves length when moving backward', () {
      final start = DateTime(2026, 8, 10);
      final end = DateTime(2026, 8, 20);
      final r = CalendarDragMath.shift(start, end, -30);
      expect(r.start, DateTime(2026, 7, 11));
      expect(r.end, DateTime(2026, 7, 21));
    });

    test('zero shift is a no-op', () {
      final start = DateTime(2026, 8, 1);
      final end = DateTime(2026, 8, 10);
      final r = CalendarDragMath.shift(start, end, 0);
      expect(r.start, start);
      expect(r.end, end);
    });
  });

  group('resizeStart', () {
    test('moves the start later within bounds', () {
      final start = DateTime(2026, 8, 1);
      final end = DateTime(2026, 8, 10);
      expect(CalendarDragMath.resizeStart(start, end, 3),
          DateTime(2026, 8, 4));
    });

    test('clamps when the start would cross the end', () {
      final start = DateTime(2026, 8, 1);
      final end = DateTime(2026, 8, 10);
      // Pushing 20 days forward should clamp at end.
      expect(CalendarDragMath.resizeStart(start, end, 20), end);
    });

    test('extends the start backward', () {
      final start = DateTime(2026, 8, 5);
      final end = DateTime(2026, 8, 10);
      expect(CalendarDragMath.resizeStart(start, end, -4),
          DateTime(2026, 8, 1));
    });
  });

  group('resizeEnd', () {
    test('moves the end later', () {
      final start = DateTime(2026, 8, 1);
      final end = DateTime(2026, 8, 10);
      expect(CalendarDragMath.resizeEnd(start, end, 5),
          DateTime(2026, 8, 15));
    });

    test('clamps when the end would cross the start', () {
      final start = DateTime(2026, 8, 5);
      final end = DateTime(2026, 8, 10);
      // Pull 20 days back — clamp at start.
      expect(CalendarDragMath.resizeEnd(start, end, -20), start);
    });
  });

  group('iso', () {
    test('formats as YYYY-MM-DD with zero-padding', () {
      expect(CalendarDragMath.iso(DateTime(2026, 1, 5)), '2026-01-05');
      expect(CalendarDragMath.iso(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('round-trip', () {
    test('shift forward then back returns to the original range', () {
      final start = DateTime(2026, 8, 1);
      final end = DateTime(2026, 8, 10);
      final f = CalendarDragMath.shift(start, end, 30);
      final b = CalendarDragMath.shift(f.start, f.end, -30);
      expect(b.start, start);
      expect(b.end, end);
    });
  });

  group('spanFromDrop', () {
    final drop = DateTime(2026, 8, 10);

    test('uses card effortDays when set (inclusive range)', () {
      final r = CalendarDragMath.spanFromDrop(drop, 14);
      expect(r.start, drop);
      expect(r.end, DateTime(2026, 8, 23)); // 14 days inclusive
    });

    test('defaults to 7 days when effort is null', () {
      final r = CalendarDragMath.spanFromDrop(drop, null);
      expect(r.start, drop);
      expect(r.end, DateTime(2026, 8, 16)); // 7 days inclusive
      expect(CalendarDragMath.defaultEffortDays, 7);
    });

    test('defaults to 7 days when effort is zero or negative', () {
      expect(
        CalendarDragMath.spanFromDrop(drop, 0).end,
        DateTime(2026, 8, 16),
      );
      expect(
        CalendarDragMath.spanFromDrop(drop, -5).end,
        DateTime(2026, 8, 16),
      );
    });

    test('effort of 1 produces a single-day span', () {
      final r = CalendarDragMath.spanFromDrop(drop, 1);
      expect(r.start, drop);
      expect(r.end, drop);
    });
  });

  group('dayIndexFromOffset', () {
    test('floors to the day boundary', () {
      // dayWidth=28: x in [0,28) → 0, [28,56) → 1, etc.
      expect(CalendarDragMath.dayIndexFromOffset(0, 28), 0);
      expect(CalendarDragMath.dayIndexFromOffset(27.9, 28), 0);
      expect(CalendarDragMath.dayIndexFromOffset(28, 28), 1);
      expect(CalendarDragMath.dayIndexFromOffset(100, 28), 3);
    });

    test('clamps negative offsets to 0 and tolerates dayWidth ≤ 0', () {
      expect(CalendarDragMath.dayIndexFromOffset(-10, 28), 0);
      expect(CalendarDragMath.dayIndexFromOffset(50, 0), 0);
    });
  });
}
