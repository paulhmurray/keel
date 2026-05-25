import 'package:flutter_test/flutter_test.dart';
import 'package:keel/shared/utils/avatar_utils.dart';

void main() {
  group('initialsFromName', () {
    test('two-word name → first letter of each word', () {
      expect(initialsFromName('Paul Murray'), 'PM');
      expect(initialsFromName('alice smith'), 'AS');
    });

    test('three+ words → first two only', () {
      expect(initialsFromName('Mary Jane Smith'), 'MJ');
      expect(initialsFromName('John Paul George Ringo'), 'JP');
    });

    test('single word → first two letters', () {
      expect(initialsFromName('alice'), 'AL');
      expect(initialsFromName('X'), 'X');
    });

    test('hyphenated first name is one word', () {
      // "Mary-Jane" is a single given name, so the surname provides the
      // second initial.
      expect(initialsFromName('Mary-Jane Smith'), 'MS');
      // Standalone hyphenated single name falls back to single-word handling
      // (first two letters).
      expect(initialsFromName('Anne-Marie'), 'AN');
    });

    test('non-letter characters stripped', () {
      expect(initialsFromName("O'Connor"), 'OC');
      expect(initialsFromName('   José   García   '), 'JG');
    });

    test('leading/trailing whitespace ignored', () {
      expect(initialsFromName('  Paul  Murray  '), 'PM');
    });

    test('empty or all-symbol input → ?', () {
      expect(initialsFromName(''), '?');
      expect(initialsFromName('   '), '?');
      expect(initialsFromName('--'), '?');
    });
  });

  group('colorFromName', () {
    test('same name → same colour', () {
      expect(colorFromName('Paul'), colorFromName('Paul'));
      expect(colorFromName('Alice Smith'), colorFromName('Alice Smith'));
    });

    test('case and whitespace insensitive', () {
      expect(colorFromName('Paul'), colorFromName('  PAUL  '));
    });

    test('different names usually map to different colours', () {
      final samples = [
        'Alice',
        'Bob',
        'Charlie',
        'Diana',
        'Edward',
        'Frances',
        'Greg',
        'Hannah',
      ];
      final colors = samples.map(colorFromName).toSet();
      // Hash collisions are possible but unlikely; expect at least 6 distinct.
      expect(colors.length, greaterThanOrEqualTo(6));
    });

    test('empty name returns a sensible fallback (not crash)', () {
      expect(colorFromName(''), isNotNull);
      expect(colorFromName('   '), isNotNull);
    });
  });
}
