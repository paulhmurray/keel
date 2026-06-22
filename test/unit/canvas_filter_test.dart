import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/canvas_filter.dart';
import 'package:keel/features/canvas/canvas_tags.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P1'));
  });

  tearDown(() async => db.close());

  Future<CanvasCard> seed({
    required String id,
    String band = 'this_week',
    String title = 'card',
    String? body,
    String? colour,
    String? linkedType,
    DateTime? promotedAt,
    List<String> tags = const [],
  }) async {
    await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
      id: id,
      projectId: 'p1',
      title: title,
      body: Value(body),
      band: Value(band),
      colour: Value(colour),
      linkedItemType: Value(linkedType),
      linkedItemId: Value(linkedType == null ? null : 'x'),
      promotedAt: Value(promotedAt),
      tags: Value(CanvasTags.encode(tags)),
    ));
    return (await db.canvasCardsDao.getCardById(id))!;
  }

  group('CanvasFilter.empty', () {
    test('returns every card untouched and reports zero active', () async {
      final a = await seed(id: 'a');
      final b = await seed(id: 'b', band: 'horizon');
      final out = CanvasFilter.empty.apply([a, b]);
      expect(out, hasLength(2));
      expect(CanvasFilter.empty.activeCount, 0);
    });
  });

  group('band filter', () {
    test('restricts to the named band', () async {
      final tw = await seed(id: 'a', band: 'this_week');
      final hz = await seed(id: 'b', band: 'horizon');
      final out =
          const CanvasFilter(band: 'this_week').apply([tw, hz]);
      expect(out.single.id, 'a');
    });
  });

  group('colour filter', () {
    test('"none" matches uncoloured cards only', () async {
      final plain = await seed(id: 'a');
      final amber = await seed(id: 'b', colour: 'amber');
      final out = const CanvasFilter(colour: 'none').apply([plain, amber]);
      expect(out.single.id, 'a');
    });

    test('exact-colour match', () async {
      final amber = await seed(id: 'a', colour: 'amber');
      final red = await seed(id: 'b', colour: 'red');
      final out = const CanvasFilter(colour: 'amber').apply([amber, red]);
      expect(out.single.id, 'a');
    });
  });

  group('linked filter', () {
    test('"linked" keeps cards with a link only', () async {
      final linked = await seed(id: 'a', linkedType: 'action');
      final free = await seed(id: 'b');
      final out = const CanvasFilter(linked: 'linked').apply([linked, free]);
      expect(out.single.id, 'a');
    });

    test('"free" keeps cards without a link', () async {
      final linked = await seed(id: 'a', linkedType: 'risk');
      final free = await seed(id: 'b');
      final out = const CanvasFilter(linked: 'free').apply([linked, free]);
      expect(out.single.id, 'b');
    });
  });

  group('promoted filter', () {
    test('"promoted" keeps promoted cards', () async {
      final yes = await seed(id: 'a', promotedAt: DateTime(2026, 6, 1));
      final no = await seed(id: 'b');
      final out =
          const CanvasFilter(promoted: 'promoted').apply([yes, no]);
      expect(out.single.id, 'a');
    });

    test('"not_promoted" keeps un-promoted cards', () async {
      final yes = await seed(id: 'a', promotedAt: DateTime(2026, 6, 1));
      final no = await seed(id: 'b');
      final out =
          const CanvasFilter(promoted: 'not_promoted').apply([yes, no]);
      expect(out.single.id, 'b');
    });
  });

  group('search', () {
    test('matches title substring case-insensitively', () async {
      final hit = await seed(id: 'a', title: 'M-POWER slip risk');
      final miss = await seed(id: 'b', title: 'Anna exit');
      final out = const CanvasFilter(search: 'm-power').apply([hit, miss]);
      expect(out.single.id, 'a');
    });

    test('matches body substring', () async {
      final hit = await seed(id: 'a', body: 'Budget board in August');
      final miss = await seed(id: 'b');
      final out = const CanvasFilter(search: 'budget').apply([hit, miss]);
      expect(out.single.id, 'a');
    });

    test('whitespace-only search disables the filter', () async {
      final a = await seed(id: 'a');
      final out = const CanvasFilter(search: '   ').apply([a]);
      expect(out, hasLength(1));
    });
  });

  group('combinations', () {
    test('all filters AND together', () async {
      final keep = await seed(
        id: 'keep',
        band: 'this_week',
        title: 'CEO brief draft',
        body: 'Budget board in August',
        colour: 'amber',
        linkedType: 'action',
      );
      final wrongBand = await seed(
        id: 'wb',
        band: 'horizon',
        title: 'CEO brief draft',
        body: 'Budget board in August',
        colour: 'amber',
        linkedType: 'action',
      );
      final wrongLink = await seed(
        id: 'wl',
        band: 'this_week',
        title: 'CEO brief draft',
        body: 'Budget board in August',
        colour: 'amber',
      );
      final wrongSearch = await seed(
        id: 'ws',
        band: 'this_week',
        title: 'Unrelated',
        colour: 'amber',
        linkedType: 'action',
      );
      const filter = CanvasFilter(
        band: 'this_week',
        colour: 'amber',
        linked: 'linked',
        search: 'CEO',
      );
      final out = filter.apply([keep, wrongBand, wrongLink, wrongSearch]);
      expect(out.map((c) => c.id), ['keep']);
      expect(filter.activeCount, 3); // band + colour + linked (search excluded)
    });
  });

  group('copyWith', () {
    test('preserves untouched fields and overrides explicit ones', () {
      const a = CanvasFilter(
        band: 'this_week',
        colour: 'amber',
        linked: 'linked',
        search: 'q',
      );
      final b = a.copyWith(colour: null, search: 'q2');
      expect(b.band, 'this_week');
      expect(b.colour, isNull);
      expect(b.linked, 'linked');
      expect(b.search, 'q2');
    });

    test('clears tag when explicitly set to null', () {
      const a = CanvasFilter(tag: 'cutover');
      final b = a.copyWith(tag: null);
      expect(b.tag, isNull);
    });

    test('leaves tag untouched when not in copyWith args', () {
      const a = CanvasFilter(tag: 'cutover', band: 'this_week');
      final b = a.copyWith(band: 'horizon');
      expect(b.tag, 'cutover');
      expect(b.band, 'horizon');
    });
  });

  group('tag filter', () {
    test('keeps only cards whose tags list contains the tag', () async {
      final a = await seed(id: 'a', tags: ['cutover', 'risk']);
      final b = await seed(id: 'b', tags: ['risk']);
      final c = await seed(id: 'c'); // no tags
      final out = const CanvasFilter(tag: 'cutover').apply([a, b, c]);
      expect(out.map((x) => x.id), ['a']);
    });

    test('lowercases the tag query against stored tags', () async {
      final a = await seed(id: 'a', tags: ['cutover']);
      final out = const CanvasFilter(tag: 'CUTOVER').apply([a]);
      expect(out, hasLength(1));
    });

    test('null tag means all cards', () async {
      final a = await seed(id: 'a', tags: ['cutover']);
      final b = await seed(id: 'b');
      expect(const CanvasFilter().apply([a, b]), hasLength(2));
    });

    test('counts as an active filter', () {
      const f = CanvasFilter(tag: 'cutover');
      expect(f.activeCount, 1);
    });

    test('combines with other filters (AND semantics)', () async {
      final a = await seed(
          id: 'a', band: 'this_week', tags: ['cutover']);
      final b = await seed(
          id: 'b', band: 'horizon', tags: ['cutover']);
      const f = CanvasFilter(tag: 'cutover', band: 'this_week');
      expect(f.apply([a, b]).map((x) => x.id), ['a']);
    });
  });
}
