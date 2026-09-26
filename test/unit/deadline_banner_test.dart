import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/plan/deadline_banner.dart';

void main() {
  final today = DateTime(2026, 9, 25);

  group('parseDeadlineText', () {
    test('the TAC statement resolves to end September 2025', () {
      expect(
          parseDeadlineText(
              'All environments live on M-POWER (AWS/Azure) by end September 2025'),
          DateTime(2025, 9, 30));
    });
    test('day month year, two- or four-digit year', () {
      expect(parseDeadlineText('Go-live 1 Nov 26'), DateTime(2026, 11, 1));
      expect(parseDeadlineText('SIT exit 15 August 2027'), DateTime(2027, 8, 15));
      expect(parseDeadlineText('31 Feb 27 (typo)'), DateTime(2027, 2, 28));
    });
    test('month year is the month end; quarters are the quarter end', () {
      expect(parseDeadlineText('Release Aug 27'), DateTime(2027, 8, 31));
      expect(parseDeadlineText('Prod ready by Q2 2027'), DateTime(2027, 6, 30));
    });
    test('ISO passes through; prose without a date is null', () {
      expect(parseDeadlineText('Hard stop 2026-12-01'), DateTime(2026, 12, 1));
      expect(parseDeadlineText('Before the board meets'), isNull);
      expect(parseDeadlineText(''), isNull);
      expect(parseDeadlineText(null), isNull);
    });
  });

  group('effectiveDeadline', () {
    test('explicit date wins over the statement', () {
      expect(
          effectiveDeadline(
              explicitIso: '2026-11-30', statement: 'by end September 2025'),
          DateTime(2026, 11, 30));
      expect(effectiveDeadline(explicitIso: null, statement: 'Aug 27'),
          DateTime(2027, 8, 31));
      expect(effectiveDeadline(explicitIso: 'junk', statement: 'no date'), isNull);
    });
  });

  group('tone and countdown', () {
    test('overdue, near, ahead, unknown', () {
      expect(deadlineTone(DateTime(2025, 9, 30), today), DeadlineTone.overdue);
      expect(deadlineTone(DateTime(2026, 10, 9), today), DeadlineTone.near); // 14 days
      expect(deadlineTone(DateTime(2026, 10, 10), today), DeadlineTone.ahead); // 15
      expect(deadlineTone(today, today), DeadlineTone.near);
      expect(deadlineTone(null, today), DeadlineTone.unknown);
    });
    test('countdown text', () {
      expect(deadlineCountdown(DateTime(2025, 9, 30), today), '360 days overdue');
      expect(deadlineCountdown(DateTime(2026, 9, 26), today), 'due in 1 day');
      expect(deadlineCountdown(today, today), 'due today');
      expect(deadlineCountdown(DateTime(2026, 9, 24), today), '1 day overdue');
      expect(deadlineCountdown(null, today), isNull);
    });
  });
}
