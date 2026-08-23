import 'package:intl/intl.dart';

/// Money helpers for Project Finance. Amounts live as integer minor
/// units (cents/pence) everywhere; doubles appear only transiently
/// inside NumberFormat display calls, never in stored or computed
/// amounts.
class Money {
  Money._();

  /// Formats minor units as a currency string: 12000050 + 'AUD' →
  /// "A$120,000.50". Null → em dash.
  static String formatMinor(int? amountMinor, String currency) {
    if (amountMinor == null) return '—';
    final fmt = NumberFormat.simpleCurrency(name: currency);
    // Compose from the absolute value's integer parts to keep the money
    // path float-free (Dart's % is Euclidean, so -12345 % 100 == 55).
    final abs = amountMinor.abs();
    final digits = NumberFormat('#,##0').format(abs ~/ 100);
    final cents = abs % 100;
    final sign = amountMinor < 0 ? '-' : '';
    return '${fmt.currencySymbol}$sign$digits.${cents.toString().padLeft(2, '0')}';
  }

  /// Grid-cell format: drops the ".00" on whole amounts, keeps full
  /// precision otherwise — never rounds.
  static String formatMinorCompact(int? amountMinor, String currency) {
    if (amountMinor == null) return '—';
    if (amountMinor % 100 == 0) {
      final fmt = NumberFormat.simpleCurrency(name: currency);
      final digits = NumberFormat('#,##0').format(amountMinor ~/ 100);
      return '${fmt.currencySymbol}$digits';
    }
    return formatMinor(amountMinor, currency);
  }

  /// Formats basis points as a signed percentage to one decimal place,
  /// rounded half away from zero: 830 → "+8.3%", 825 → "+8.3%",
  /// -50 → "-0.5%", null → "—".
  static String formatBp(int? bp) {
    if (bp == null) return '—';
    final sign = bp > 0 ? '+' : bp < 0 ? '-' : '';
    final tenths = (bp.abs() * 2 + 10) ~/ 20; // 0.1%-units, half-away
    return '$sign${tenths ~/ 10}.${tenths % 10}%';
  }

  /// Symbol-free editable form for pre-filling amount fields:
  /// 12000050 → "120,000.50", 12000000 → "120,000".
  static String formatMinorPlain(int amountMinor) {
    final abs = amountMinor.abs();
    final digits = NumberFormat('#,##0').format(abs ~/ 100);
    final cents = abs % 100;
    final sign = amountMinor < 0 ? '-' : '';
    return cents == 0
        ? '$sign$digits'
        : '$sign$digits.${cents.toString().padLeft(2, '0')}';
  }

  /// Parses user grid input to minor units. Accepts "120000",
  /// "120,000.50", "120k", "1.2m", "$120,000". Returns null on
  /// anything ambiguous or malformed rather than guessing.
  static int? parseToMinor(String input) {
    var s = input.trim().toLowerCase();
    if (s.isEmpty) return null;
    // Strip currency symbols and spaces.
    s = s.replaceAll(RegExp(r'[£$€\s]|a\$'), '');
    if (s.isEmpty) return null;

    var multiplier = 1;
    if (s.endsWith('k')) {
      multiplier = 1000;
      s = s.substring(0, s.length - 1);
    } else if (s.endsWith('m')) {
      multiplier = 1000000;
      s = s.substring(0, s.length - 1);
    }
    s = s.replaceAll(',', '');
    if (s.isEmpty) return null;

    final negative = s.startsWith('-');
    if (negative) s = s.substring(1);

    final match = RegExp(r'^(\d*)(?:\.(\d+))?$').firstMatch(s);
    if (match == null) return null;
    final wholePart = match.group(1) ?? '';
    final fracPart = match.group(2) ?? '';
    if (wholePart.isEmpty && fracPart.isEmpty) return null;

    final whole = wholePart.isEmpty ? 0 : int.parse(wholePart);
    // Fractional input: with a k/m multiplier the fraction scales into
    // whole currency (1.5k = 1500.00); without one it's cents and more
    // than 2 decimal places is rejected as ambiguous.
    int minor;
    if (multiplier == 1) {
      if (fracPart.length > 2) return null;
      final cents = fracPart.isEmpty
          ? 0
          : int.parse(fracPart.padRight(2, '0'));
      minor = whole * 100 + cents;
    } else {
      // Scale fraction against the multiplier in pure integer maths:
      // 1.25k → whole=1, frac=25 → (1*1000 + 25*1000/100) * 100.
      final fracScale = fracPart.isEmpty ? 0 : int.parse(fracPart);
      final denom = _pow10(fracPart.length);
      final scaledFrac = fracScale * multiplier * 100;
      if (scaledFrac % denom != 0) return null; // e.g. "1.2345k" → 123.45 ok; reject non-exact
      minor = whole * multiplier * 100 + scaledFrac ~/ denom;
    }
    return negative ? -minor : minor;
  }

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}
