import 'package:flutter_test/flutter_test.dart';
import 'package:keel/shared/utils/date_utils.dart' as du;

void main() {
  group('formatDate (ISO → display)', () {
    test('converts a valid ISO date', () {
      expect(du.formatDate('2025-03-28'), '28-03-2025');
    });

    test('returns empty string for null', () {
      expect(du.formatDate(null), '');
    });

    test('returns empty string for empty string', () {
      expect(du.formatDate(''), '');
    });

    test('returns input as-is if not three parts', () {
      expect(du.formatDate('2025-03'), '2025-03');
    });

    test('handles leading zeros correctly', () {
      expect(du.formatDate('2025-01-05'), '05-01-2025');
    });
  });

  group('parseDisplayDate (display → ISO)', () {
    test('converts a valid display date', () {
      expect(du.parseDisplayDate('28-03-2025'), '2025-03-28');
    });

    test('returns null for empty string', () {
      expect(du.parseDisplayDate(''), null);
    });

    test('returns null for whitespace', () {
      expect(du.parseDisplayDate('   '), null);
    });

    test('falls back to input if not three parts', () {
      expect(du.parseDisplayDate('28-03'), '28-03');
    });
  });

  group('toIsoDate', () {
    test('formats a DateTime to ISO', () {
      expect(du.toIsoDate(DateTime(2025, 3, 5)), '2025-03-05');
    });

    test('pads day and month with leading zero', () {
      expect(du.toIsoDate(DateTime(2025, 1, 1)), '2025-01-01');
    });
  });

  group('toDisplayDate', () {
    test('formats a DateTime to dd-mm-yyyy', () {
      expect(du.toDisplayDate(DateTime(2025, 3, 5)), '05-03-2025');
    });

    test('pads single-digit values', () {
      expect(du.toDisplayDate(DateTime(2025, 1, 9)), '09-01-2025');
    });
  });

  group('parseIsoDate', () {
    test('parses a valid ISO date string', () {
      final dt = du.parseIsoDate('2025-03-28');
      expect(dt, isNotNull);
      expect(dt!.year, 2025);
      expect(dt.month, 3);
      expect(dt.day, 28);
    });

    test('returns null for null input', () {
      expect(du.parseIsoDate(null), isNull);
    });

    test('returns null for empty string', () {
      expect(du.parseIsoDate(''), isNull);
    });

    test('returns null for invalid date', () {
      expect(du.parseIsoDate('not-a-date'), isNull);
    });
  });

  group('roundtrip', () {
    test('ISO → display → ISO roundtrips correctly', () {
      const iso = '2025-11-30';
      final display = du.formatDate(iso);
      final backToIso = du.parseDisplayDate(display);
      expect(backToIso, iso);
    });
  });
}
