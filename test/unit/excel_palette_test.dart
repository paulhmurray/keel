import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/export/excel_palette.dart';

void main() {
  group('xlTint', () {
    test('always returns exactly 8 hex digits with an opaque FF alpha',
        () {
      // The old exporter appended alpha to an 8-digit hex, producing an
      // invalid 10-digit colour — this pins that it can't come back.
      final tinted = xlTint('FF3B82F6');
      expect(tinted.length, 8);
      expect(tinted.startsWith('FF'), isTrue);
      expect(RegExp(r'^[0-9A-F]{8}$').hasMatch(tinted), isTrue);
    });

    test('factor 0 keeps the RGB channels, factor 1 is white', () {
      expect(xlTint('FF3B82F6', 0), 'FF3B82F6');
      expect(xlTint('FF3B82F6', 1), 'FFFFFFFF');
    });

    test('default tint is much lighter than the source', () {
      // 80% toward white: every channel ends high.
      final t = xlTint('FF3B82F6');
      for (var i = 2; i < 8; i += 2) {
        final channel = int.parse(t.substring(i, i + 2), radix: 16);
        expect(channel, greaterThan(0xB0));
      }
    });
  });

  group('xlContrastText', () {
    test('dark fills get white text', () {
      expect(xlContrastText(kXlTitleBand), kXlWhite); // near-black band
      expect(xlContrastText('FF3B82F6'), kXlWhite); // wp1 blue
      expect(xlContrastText('FF8B5CF6'), kXlWhite); // wp3 violet
    });

    test('light fills get ink, not white', () {
      expect(xlContrastText('FFFFFFFF'), kXlInk);
      expect(xlContrastText(kXlHeaderBg), kXlInk);
      expect(xlContrastText('FFF59E0B'), kXlInk); // wp4 amber — the
      // combination the old exporter rendered as white-on-amber.
    });
  });

  group('row layout', () {
    test('short text is one line; long text wraps by column width', () {
      // 40 units at 1.15 characters per unit is 46 characters a line.
      expect(xlWrappedLines('Ship it', 40), 1);
      expect(xlWrappedLines('', 40), 1);
      expect(xlWrappedLines('x' * 46, 40), 1);
      expect(xlWrappedLines('x' * 47, 40), 2);
      expect(xlWrappedLines('x' * 120, 40), 3);
    });

    test('explicit line breaks each start a new line', () {
      expect(xlWrappedLines('one\ntwo\nthree', 40), 3);
      expect(xlWrappedLines('${'x' * 50}\nshort', 40), 3);
    });

    test('row height follows the tallest wrapped cell, never under the floor', () {
      expect(xlRowHeight([('short', 40)]), 18);
      expect(xlRowHeight([('short', 40)], min: 24), 24);
      final three = xlRowHeight([('x' * 120, 40), ('y' * 10, 16)]);
      expect(three, 3 * kXlLineHeight + kXlRowPadding);
      expect(xlRowHeight(const []), 18);
    });

    test('a wall of text stops at the Excel ceiling', () {
      expect(xlRowHeight([('x' * 100000, 40)]), kXlMaxRowHeight);
    });
  });
}
