import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/timeline/gantt/date_precision.dart';

void main() {
  final m0 = DateTime(2026, 6, 1); // Jun 26 = month 0

  group('monthIndexOf / monthFractionOf', () {
    test('whole month indices, across year boundary', () {
      expect(monthIndexOf(DateTime(2026, 6, 15), m0), 0);
      expect(monthIndexOf(DateTime(2026, 8, 1), m0), 2);
      expect(monthIndexOf(DateTime(2027, 1, 10), m0), 7);
    });

    test('fraction reflects day progress within the month', () {
      expect(monthFractionOf(DateTime(2026, 6, 1), m0), 0.0);
      // 16 June of a 30-day month → 15/30 = .5 through month 0.
      expect(monthFractionOf(DateTime(2026, 6, 16), m0), closeTo(0.5, 1e-9));
      expect(monthFractionOf(DateTime(2026, 8, 1), m0), 2.0);
    });
  });

  group('monthSpanForDates', () {
    test('derives inclusive month span from dates', () {
      final span = monthSpanForDates(
        startDate: '2026-07-10',
        endDate: '2026-09-15',
        month0Date: '2026-06-01',
      );
      expect(span, (startMonth: 1, endMonth: 3));
    });

    test('missing dates or anchor → null (months stay manual)', () {
      expect(
          monthSpanForDates(
              startDate: null, endDate: null, month0Date: '2026-06-01'),
          isNull);
      expect(
          monthSpanForDates(
              startDate: '2026-07-01', endDate: null, month0Date: null),
          isNull);
    });

    test('single date → single-month span', () {
      final span = monthSpanForDates(
        startDate: '2026-08-20',
        endDate: null,
        month0Date: '2026-06-01',
      );
      expect(span, (startMonth: 2, endMonth: 2));
    });
  });

  group('dateInsetsForCell', () {
    const w = 100.0;

    test('undated → zero insets', () {
      final i = dateInsetsForCell(
          startDate: null,
          endDate: null,
          month0Date: '2026-06-01',
          colStart: 0,
          colEnd: 0,
          colWidth: w);
      expect(i, (left: 0.0, right: 0.0));
    });

    test('start cell insets the left edge to the start day', () {
      // Starts 16 Jun (halfway through the 30-day month).
      final i = dateInsetsForCell(
          startDate: '2026-06-16',
          endDate: '2026-08-31',
          month0Date: '2026-06-01',
          colStart: 0,
          colEnd: 0,
          colWidth: w);
      expect(i.left, closeTo(50, 0.01));
      expect(i.right, 0);
    });

    test('end cell insets the right edge past the end day', () {
      // Ends 15 Aug (31-day month): bar covers through the 15th.
      final i = dateInsetsForCell(
          startDate: '2026-06-16',
          endDate: '2026-08-15',
          month0Date: '2026-06-01',
          colStart: 2,
          colEnd: 2,
          colWidth: w);
      expect(i.left, 0);
      expect(i.right, closeTo((1 - 15 / 31) * 100, 0.01));
    });

    test('middle cell of the span gets no insets', () {
      final i = dateInsetsForCell(
          startDate: '2026-06-16',
          endDate: '2026-08-15',
          month0Date: '2026-06-01',
          colStart: 1,
          colEnd: 1,
          colWidth: w);
      expect(i, (left: 0.0, right: 0.0));
    });

    test('quarter-mode column scales insets across the month range', () {
      // Column covers months 0–2; bar starts exactly at month 1.
      final i = dateInsetsForCell(
          startDate: '2026-07-01',
          endDate: '2026-08-31',
          month0Date: '2026-06-01',
          colStart: 0,
          colEnd: 2,
          colWidth: 300);
      expect(i.left, closeTo(100, 0.01));
      expect(i.right, closeTo(0, 0.01));
    });

    test('degenerate short span keeps a visible sliver', () {
      final i = dateInsetsForCell(
          startDate: '2026-06-30',
          endDate: '2026-06-30',
          month0Date: '2026-06-01',
          colStart: 0,
          colEnd: 0,
          colWidth: w);
      expect(w - i.left - i.right, greaterThanOrEqualTo(2));
    });
  });
}
