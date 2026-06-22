import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/canvas_tags.dart';

void main() {
  group('CanvasTags.extractFromBody', () {
    test('null and empty body produce no tags', () {
      expect(CanvasTags.extractFromBody(null), isEmpty);
      expect(CanvasTags.extractFromBody(''), isEmpty);
      expect(CanvasTags.extractFromBody('   '), isEmpty);
    });

    test('finds a single tag', () {
      expect(
        CanvasTags.extractFromBody('cutover plan #risk for august'),
        ['risk'],
      );
    });

    test('finds multiple tags in body order', () {
      expect(
        CanvasTags.extractFromBody(
            'Need #cutover plan #stakeholder comms #risk'),
        ['cutover', 'stakeholder', 'risk'],
      );
    });

    test('lowercases tag names', () {
      expect(
        CanvasTags.extractFromBody('#Cutover and #RISK and #IntEgration'),
        ['cutover', 'risk', 'integration'],
      );
    });

    test('deduplicates within the same body, preserving first order', () {
      expect(
        CanvasTags.extractFromBody('#risk #cutover #risk #cutover'),
        ['risk', 'cutover'],
      );
    });

    test('case-insensitive dedup', () {
      expect(
        CanvasTags.extractFromBody('#Risk and later #risk'),
        ['risk'],
      );
    });

    test('hyphenated and underscored tags are kept whole', () {
      expect(
        CanvasTags.extractFromBody('#go-live and #pre_mortem'),
        ['go-live', 'pre_mortem'],
      );
    });

    test('tags ending with punctuation strip the punctuation', () {
      expect(
        CanvasTags.extractFromBody('#risk, and #cutover. Done #integration!'),
        ['risk', 'cutover', 'integration'],
      );
    });

    test('mid-word hashes are not tags (e.g. URL fragments)', () {
      expect(
        CanvasTags.extractFromBody('See https://example.com#section here'),
        isEmpty,
      );
      expect(
        CanvasTags.extractFromBody('word#middle is not a tag'),
        isEmpty,
      );
    });

    test('lone hashes without trailing word chars are ignored', () {
      expect(CanvasTags.extractFromBody('# # ##'), isEmpty);
    });

    test('markdown headings are NOT treated as tags', () {
      // `## Heading` — the `#` after the first `#` isn't a word char,
      // and "Heading" isn't directly after a `#`, so the parser
      // correctly skips it. A real `#tag` further in the body is still
      // picked up.
      expect(
        CanvasTags.extractFromBody('## Heading\n\nSome #tag here'),
        ['tag'],
      );
    });
  });

  group('encode / decode round-trip', () {
    test('empty list encodes to null', () {
      expect(CanvasTags.encode(const []), isNull);
    });

    test('non-empty list round-trips through JSON', () {
      final original = ['cutover', 'risk', 'integration'];
      final encoded = CanvasTags.encode(original);
      expect(encoded, isNotNull);
      expect(CanvasTags.decode(encoded), original);
    });

    test('decode returns empty list on null/empty/malformed input', () {
      expect(CanvasTags.decode(null), isEmpty);
      expect(CanvasTags.decode(''), isEmpty);
      expect(CanvasTags.decode('not-json'), isEmpty);
      // JSON that decodes to something other than a list of strings
      expect(CanvasTags.decode('{"foo": "bar"}'), isEmpty);
      expect(CanvasTags.decode('[1, 2, 3]'), isEmpty);
    });

    test('decode keeps only string entries from mixed arrays', () {
      expect(CanvasTags.decode('["a", 1, "b", null, "c"]'),
          ['a', 'b', 'c']);
    });
  });

  group('CanvasTags.suggestionAt', () {
    const known = ['risk', 'integration', 'cutover', 'release'];

    test('returns null when the caret is not in a #tag context', () {
      // No `#` anywhere before the caret.
      expect(CanvasTags.suggestionAt('plain prose', 5, known), isNull);
      // Caret after a `#` whose previous char is a word char (mid-URL).
      expect(
        CanvasTags.suggestionAt('see page#sec', 12, known),
        isNull,
      );
    });

    test('returns matches sorted shortest-first then alphabetical', () {
      final s = CanvasTags.suggestionAt('typing #r', 9, known);
      expect(s, isNotNull);
      expect(s!.prefix, 'r');
      // 'risk' (4) before 'release' (7).
      expect(s.matches, ['risk', 'release']);
      expect(s.start, 7);
      expect(s.end, 9);
    });

    test('an empty prefix (just `#`) returns ALL known tags', () {
      final s = CanvasTags.suggestionAt('typing #', 8, known);
      expect(s, isNotNull);
      expect(s!.prefix, '');
      // Sorted shortest-first then alphabetical.
      expect(s.matches, ['risk', 'cutover', 'release', 'integration']);
    });

    test('caret in the middle of a tag word still suggests', () {
      // body: "the #cu plan", caret right after 'cu' at offset 7.
      final s = CanvasTags.suggestionAt('the #cu plan', 7, known);
      expect(s, isNotNull);
      expect(s!.prefix, 'cu');
      expect(s.matches, ['cutover']);
      // end should extend to where the tag word ends (' ' at index 7).
      expect(s.end, 7);
    });

    test('exact-prefix match drops the literal tag from the list', () {
      // The user has typed the full word `#risk` — no point suggesting
      // `risk` again, but `release` etc shouldn't show because they
      // don't start with "risk".
      final s = CanvasTags.suggestionAt('#risk', 5, known);
      expect(s, isNotNull);
      expect(s!.matches, isEmpty);
    });

    test('matching is case-insensitive against known tags', () {
      final s = CanvasTags.suggestionAt('#Re', 3, ['Risk', 'Release']);
      expect(s, isNotNull);
      expect(s!.matches, ['release']);
    });

    test('returns null when caret sits past a completed tag word', () {
      // body: "#risk plan", caret after the space — no longer in tag.
      expect(
        CanvasTags.suggestionAt('#risk plan', 6, known),
        isNull,
      );
    });

    test('accept() replaces the in-progress tag and parks the caret', () {
      const body = 'typing #r and more';
      final s = CanvasTags.suggestionAt(body, 9, known)!;
      final r = s.accept(body, 'risk');
      expect(r.body, 'typing #risk and more');
      // caret = start (7) + length of "#risk" (5) = 12.
      expect(r.caret, 12);
    });

    test('respects maxResults', () {
      final s = CanvasTags.suggestionAt(
        '#',
        1,
        ['a', 'ab', 'abc', 'abcd', 'abcde', 'abcdef', 'abcdefg'],
        maxResults: 3,
      );
      expect(s!.matches, hasLength(3));
      // Shortest first.
      expect(s.matches, ['a', 'ab', 'abc']);
    });
  });
}
