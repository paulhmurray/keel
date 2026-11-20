import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/search/fuzzy_match.dart';
import 'package:keel/features/timeline/gantt/raid_picker_dialog.dart';

const _items = [
  RaidPickItem(
    type: 'risk',
    id: 'r1',
    ref: 'R19',
    text: 'Supplier capacity for SIT environment',
    owner: 'Priya Shah',
  ),
  RaidPickItem(
    type: 'risk',
    id: 'r2',
    ref: 'R4',
    text: 'Vendor build phase is running late',
    detail: 'Weekly checkpoints with the vendor',
  ),
  RaidPickItem(
    type: 'assumption',
    id: 'a1',
    ref: 'A3',
    text: 'Azure tenancy is available by July',
    owner: 'Tom',
  ),
  RaidPickItem(
    type: 'dependency',
    id: 'd1',
    ref: 'D2',
    text: 'Claims platform release from the vendor',
  ),
  RaidPickItem(
    type: 'issue',
    id: 'i1',
    ref: 'I1',
    text: 'Data migration rehearsal failed',
  ),
];

List<String> ids(String q, {String? type}) =>
    [for (final i in rankRaidItems(_items, q, type: type)) i.id];

void main() {
  group('fuzzyMatch', () {
    test('empty query keeps every item in its order', () {
      expect(ids(''), ['r1', 'r2', 'a1', 'd1', 'i1']);
      expect(ids('   '), ['r1', 'r2', 'a1', 'd1', 'i1']);
    });

    test('a ref wins outright, in any case', () {
      expect(ids('r19').first, 'r1');
      expect(ids('R4').first, 'r2');
    });

    test('every word must land; order of words does not matter', () {
      expect(ids('environment sit'), ['r1']);
      expect(ids('sit vendor'), isEmpty);
    });

    test('typos still find the word', () {
      expect(ids('suplier'), ['r1']); // missing letter
      expect(ids('tennacy'), ['a1']); // extra letter
      expect(ids('migartion'), ['i1']); // swapped letters
      expect(ids('suplie'), ['r1']); // half-typed with a typo
    });

    test('letters in order inside a word', () {
      expect(ids('vndr'), containsAll(['r2', 'd1']));
      expect(ids('qqq'), isEmpty);
    });

    test('owner and detail are searchable but rank below the title', () {
      expect(ids('priya'), ['r1']);
      // "vendor" is in r2's title and detail, d1's title — both, title hits.
      expect(ids('checkpoints'), ['r2']);
    });

    test('a whole-word hit beats a word-start hit beats an inside hit', () {
      const fields = [FuzzyField('platform plat replatform')];
      final whole = fuzzyMatch('platform', fields)!.score;
      final start = fuzzyMatch('plat', [const FuzzyField('platform')])!.score;
      final inside = fuzzyMatch('latf', [const FuzzyField('platform')])!.score;
      expect(whole, greaterThan(start));
      expect(start, greaterThan(inside));
    });

    test('register name filters by type, and the type filter applies', () {
      expect(ids('assumption'), ['a1']);
      expect(ids('vendor', type: 'dependency'), ['d1']);
      expect(ids('', type: 'risk'), ['r1', 'r2']);
    });

    test('highlight spans cover what matched', () {
      final m = fuzzyMatch('sup cap', _items.first.searchFields)!;
      final text = _items.first.text;
      final hits = [for (final (s, e) in m.spansFor(1)) text.substring(s, e)];
      expect(hits, ['Sup', 'cap']);
    });

    test('short words do not typo-match (too noisy)', () {
      expect(fuzzyMatch('sut', [const FuzzyField('sit')]), isNull);
    });
  });
}
