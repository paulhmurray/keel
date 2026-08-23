import 'package:flutter_test/flutter_test.dart';
import 'package:keel/shared/utils/money.dart';

void main() {
  group('Money.parseToMinor', () {
    test('plain integers', () {
      expect(Money.parseToMinor('120000'), 12000000);
      expect(Money.parseToMinor('0'), 0);
      expect(Money.parseToMinor('7'), 700);
    });

    test('thousands separators and decimals', () {
      expect(Money.parseToMinor('1,234.56'), 123456);
      expect(Money.parseToMinor('120,000'), 12000000);
      expect(Money.parseToMinor('.5'), 50);
      expect(Money.parseToMinor('0.05'), 5);
    });

    test('k and m suffixes', () {
      expect(Money.parseToMinor('120k'), 12000000);
      expect(Money.parseToMinor('1.5k'), 150000);
      expect(Money.parseToMinor('1.25k'), 125000);
      expect(Money.parseToMinor('2m'), 200000000);
      expect(Money.parseToMinor('1.2m'), 120000000);
      expect(Money.parseToMinor('42M'), 4200000000);
    });

    test('currency symbols and whitespace stripped', () {
      expect(Money.parseToMinor(r'$120,000'), 12000000);
      expect(Money.parseToMinor('£1,000.50'), 100050);
      expect(Money.parseToMinor(' 500 '), 50000);
    });

    test('negatives', () {
      expect(Money.parseToMinor('-500'), -50000);
      expect(Money.parseToMinor('-1.5k'), -150000);
    });

    test('rejects ambiguous or malformed input', () {
      expect(Money.parseToMinor(''), isNull);
      expect(Money.parseToMinor('abc'), isNull);
      expect(Money.parseToMinor('1.234'), isNull); // >2dp without suffix
      expect(Money.parseToMinor('1.2.3'), isNull);
      expect(Money.parseToMinor('k'), isNull);
      expect(Money.parseToMinor('12a'), isNull);
    });

    test('k/m fractions must resolve to exact cents', () {
      expect(Money.parseToMinor('1.2345k'), 123450); // 1234.50 exact
      expect(Money.parseToMinor('1.234567k'), isNull); // sub-cent
    });
  });

  group('Money.formatMinor', () {
    test('formats with symbol, separators, and 2dp', () {
      expect(Money.formatMinor(12000050, 'GBP'), '£120,000.50');
      expect(Money.formatMinor(0, 'GBP'), '£0.00');
      expect(Money.formatMinor(5, 'GBP'), '£0.05');
    });

    test('null renders em dash', () {
      expect(Money.formatMinor(null, 'AUD'), '—');
    });

    test('negative amounts keep the sign', () {
      expect(Money.formatMinor(-50, 'GBP'), '£-0.50');
      expect(Money.formatMinor(-12345, 'GBP'), '£-123.45');
    });

    test('compact drops .00 on whole amounts only', () {
      expect(Money.formatMinorCompact(12000000, 'GBP'), '£120,000');
      expect(Money.formatMinorCompact(12000050, 'GBP'), '£120,000.50');
      expect(Money.formatMinorCompact(null, 'GBP'), '—');
    });

    test('formatBp renders signed 1dp percentages, half-away rounded', () {
      expect(Money.formatBp(830), '+8.3%');
      expect(Money.formatBp(825), '+8.3%');
      expect(Money.formatBp(824), '+8.2%');
      expect(Money.formatBp(-50), '-0.5%');
      expect(Money.formatBp(0), '0.0%');
      expect(Money.formatBp(10000), '+100.0%');
      expect(Money.formatBp(null), '—');
    });

    test('plain form drops symbol for edit fields', () {
      expect(Money.formatMinorPlain(12000050), '120,000.50');
      expect(Money.formatMinorPlain(12000000), '120,000');
      expect(Money.formatMinorPlain(-12345), '-123.45');
      expect(Money.formatMinorPlain(0), '0');
    });

    test('round-trips with parseToMinor', () {
      for (final minor in [0, 5, 100, 123456, 12000000, 4200000000]) {
        final formatted = Money.formatMinor(minor, 'GBP');
        expect(Money.parseToMinor(formatted), minor,
            reason: 'round-trip failed for $formatted');
      }
    });
  });
}
