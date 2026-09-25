import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/journal/journal_match.dart';

const _body = '''
Weekly vendor sync, 14 Sept. Present: Sam, Priya, Acme PM.

Acme confirmed the signed API contract will not land before 15 October.
Sam flagged this blocks the adapter build; we agreed to escalate if it
slips again.

Priya raised that the UAT environment has been down for three days and
test cycle 2 cannot start until it is rebuilt.

Action: Sam to draft the steering pack narrative by Friday.
''';

void main() {
  group('splitParagraphs', () {
    test('splits on blank lines and trims, keeping inner newlines', () {
      final ps = splitParagraphs(_body);
      expect(ps, hasLength(4));
      expect(ps.first, startsWith('Weekly vendor sync'));
      expect(ps[1], contains('\n')); // wrapped lines stay together
      expect(ps.last, startsWith('Action:'));
    });

    test('empty body yields no paragraphs', () {
      expect(splitParagraphs('  \n\n '), isEmpty);
    });
  });

  group('distinctiveWords', () {
    test('drops stop words and short tokens, stems plurals and -ing', () {
      final w = distinctiveWords('The vendors are delivering signed keys');
      expect(w, isNot(contains('the')));
      expect(w, isNot(contains('are')));
      expect(w, contains('vendor'));
      expect(w, contains('deliver'));
      expect(w, contains('sign'));
      expect(w, contains('key'));
    });
  });

  group('bestMatchingParagraph', () {
    test('finds the paragraph an extracted dependency came from', () {
      final m = bestMatchingParagraph(
          _body, 'Vendor delivers the signed API contract');
      expect(m, isNotNull);
      expect(m!.paragraphIndex, 1);
      expect(m.paragraph, contains('signed API contract'));
      expect(m.score, greaterThanOrEqualTo(kMinMatchScore));
    });

    test('finds the paragraph an extracted issue came from', () {
      final m = bestMatchingParagraph(_body, 'UAT environment down');
      expect(m!.paragraphIndex, 2);
    });

    test('finds the paragraph an extracted action came from', () {
      final m = bestMatchingParagraph(
          _body, 'Draft the steering pack narrative');
      expect(m!.paragraphIndex, 3);
    });

    test('returns null when nothing overlaps enough', () {
      expect(bestMatchingParagraph(_body, 'Quarterly budget reforecast'),
          isNull);
    });

    test('returns null for a needle made only of stop words', () {
      expect(bestMatchingParagraph(_body, 'the and of'), isNull);
    });

    test('ties resolve to the earlier paragraph', () {
      const body = 'Alpha beta gamma.\n\nAlpha beta gamma.';
      final m = bestMatchingParagraph(body, 'alpha beta');
      expect(m!.paragraphIndex, 0);
    });
  });
}
