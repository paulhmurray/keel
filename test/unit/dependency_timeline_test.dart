import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/raid/dependency_timeline.dart';

void main() {
  group('anchorForDependencyType', () {
    test('inbound and bilateral gate the activity start', () {
      expect(anchorForDependencyType('inbound'), SlackAnchor.activityStart);
      expect(anchorForDependencyType('bilateral'), SlackAnchor.activityStart);
    });

    test('outbound is measured against the activity end', () {
      expect(anchorForDependencyType('outbound'), SlackAnchor.activityEnd);
    });
  });

  group('resolveActivityAnchorDate', () {
    test('prefers a real ISO date over the month index', () {
      final r = resolveActivityAnchorDate(
        anchor: SlackAnchor.activityStart,
        startDate: '2026-10-14',
        endDate: null,
        startMonth: 3,
        endMonth: 4,
        month0Date: '2026-06-01',
      );
      expect(r!.date, DateTime.utc(2026, 10, 14));
      expect(r.isEstimate, isFalse);
    });

    test('falls back to the first of the start month', () {
      final r = resolveActivityAnchorDate(
        anchor: SlackAnchor.activityStart,
        startDate: null,
        endDate: null,
        startMonth: 3,
        endMonth: 4,
        month0Date: '2026-06-01',
      );
      expect(r!.date, DateTime.utc(2026, 9, 1));
      expect(r.isEstimate, isTrue);
    });

    test('falls back to the last day of the end month for the end anchor',
        () {
      final r = resolveActivityAnchorDate(
        anchor: SlackAnchor.activityEnd,
        startDate: null,
        endDate: null,
        startMonth: 3,
        endMonth: 4,
        month0Date: '2026-06-01',
      );
      // Month 4 from June = October → 31 Oct.
      expect(r!.date, DateTime.utc(2026, 10, 31));
      expect(r.isEstimate, isTrue);
    });

    test('month index wraps across a year boundary', () {
      final r = resolveActivityAnchorDate(
        anchor: SlackAnchor.activityStart,
        startDate: null,
        endDate: null,
        startMonth: 8,
        endMonth: 8,
        month0Date: '2026-06-01',
      );
      expect(r!.date, DateTime.utc(2027, 2, 1));
    });

    test('returns null when nothing resolves', () {
      expect(
        resolveActivityAnchorDate(
          anchor: SlackAnchor.activityStart,
          startDate: null,
          endDate: null,
          startMonth: null,
          endMonth: null,
          month0Date: '2026-06-01',
        ),
        isNull,
      );
      expect(
        resolveActivityAnchorDate(
          anchor: SlackAnchor.activityStart,
          startDate: null,
          endDate: null,
          startMonth: 2,
          endMonth: 2,
          month0Date: null,
        ),
        isNull,
      );
    });
  });

  group('dependencySlack', () {
    DependencySlack? inbound(String? due, {String? start, int? startMonth}) =>
        dependencySlack(
          dueDate: due,
          dependencyType: 'inbound',
          activityStartDate: start,
          activityEndDate: null,
          activityStartMonth: startMonth,
          activityEndMonth: startMonth,
          month0Date: '2026-06-01',
        );

    test('inbound: positive slack when it lands before the activity starts',
        () {
      final s = inbound('2026-09-01', start: '2026-10-01')!;
      expect(s.days, 30);
      expect(s.severity, SlackSeverity.ok);
      expect(s.anchor, SlackAnchor.activityStart);
      expect(s.label, contains('30 days slack'));
    });

    test('inbound: tight when under two weeks', () {
      final s = inbound('2026-09-25', start: '2026-10-01')!;
      expect(s.days, 6);
      expect(s.severity, SlackSeverity.tight);
    });

    test('inbound: late when it lands after the activity starts', () {
      final s = inbound('2026-10-20', start: '2026-10-01')!;
      expect(s.days, -19);
      expect(s.severity, SlackSeverity.late);
      expect(s.label, contains('AFTER'));
    });

    test('same day is zero slack and reads as tight', () {
      final s = inbound('2026-10-01', start: '2026-10-01')!;
      expect(s.days, 0);
      expect(s.severity, SlackSeverity.tight);
      expect(s.label, 'Due the day the activity starts');
    });

    test('month-only activity is flagged as an estimate', () {
      final s = inbound('2026-08-20', startMonth: 3)!; // Sept 2026
      expect(s.activityDate, DateTime.utc(2026, 9, 1));
      expect(s.days, 12);
      expect(s.activityDateIsEstimate, isTrue);
      expect(s.label, startsWith('≈'));
    });

    test('outbound: measured from the activity end to the needed-by date',
        () {
      final s = dependencySlack(
        dueDate: '2026-11-15',
        dependencyType: 'outbound',
        activityStartDate: '2026-09-01',
        activityEndDate: '2026-10-31',
        activityStartMonth: null,
        activityEndMonth: null,
        month0Date: null,
      )!;
      expect(s.anchor, SlackAnchor.activityEnd);
      expect(s.days, 15);
      expect(s.severity, SlackSeverity.ok);
    });

    test('outbound: late when we finish after they need it', () {
      final s = dependencySlack(
        dueDate: '2026-10-01',
        dependencyType: 'outbound',
        activityStartDate: '2026-09-01',
        activityEndDate: '2026-10-31',
        activityStartMonth: null,
        activityEndMonth: null,
        month0Date: null,
      )!;
      expect(s.days, -30);
      expect(s.severity, SlackSeverity.late);
    });

    test('null when the dependency has no needed-by date', () {
      expect(inbound(null, start: '2026-10-01'), isNull);
    });

    test('null when the activity is undated', () {
      expect(inbound('2026-10-01'), isNull);
    });

    test('ignores malformed dates', () {
      expect(inbound('not-a-date', start: '2026-10-01'), isNull);
      expect(inbound('2026-10-01', start: 'soon'), isNull);
    });
  });
}
