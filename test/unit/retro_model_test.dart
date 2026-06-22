import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/templates/instances/retrospective/retro_model.dart';

void main() {
  group('RetroColumn', () {
    test('all lists every column id', () {
      expect(RetroColumn.all, hasLength(4));
      expect(RetroColumn.all.toSet(), {
        RetroColumn.start,
        RetroColumn.stop,
        RetroColumn.cont,
        RetroColumn.learn,
      });
    });

    test('canPromoteToAction is true only for Start (per retro pattern)',
        () {
      expect(RetroColumn.canPromoteToAction(RetroColumn.start), isTrue);
      expect(RetroColumn.canPromoteToAction(RetroColumn.stop), isFalse);
      expect(RetroColumn.canPromoteToAction(RetroColumn.cont), isFalse);
      expect(RetroColumn.canPromoteToAction(RetroColumn.learn), isFalse);
    });

    test('uses "continue" as the storage / JSON key', () {
      expect(RetroColumn.cont, 'continue');
    });
  });

  group('RetroContent JSON', () {
    test('round-trips a full payload', () {
      const original = RetroContent(
        start: [
          RetroItem(id: 's1', title: 'Weekly sponsor catch-up', votes: 3),
        ],
        stop: [
          RetroItem(
              id: 'st1', title: 'Status in 3 tools', notes: 'consolidate'),
        ],
        continueItems: [
          RetroItem(id: 'c1', title: 'Fortnightly retros'),
        ],
        learn: [
          RetroItem(id: 'l1', title: 'More time for arch'),
        ],
      );
      final back = RetroContent.decode(original.encode());
      expect(back.start.single.title, 'Weekly sponsor catch-up');
      expect(back.start.single.votes, 3);
      expect(back.stop.single.notes, 'consolidate');
      expect(back.continueItems.single.title, 'Fortnightly retros');
      expect(back.learn.single.title, 'More time for arch');
    });

    test('decode tolerates null / empty / wrong-shape / malformed', () {
      expect(RetroContent.decode(null).start, isEmpty);
      expect(RetroContent.decode('').stop, isEmpty);
      expect(RetroContent.decode('not-json').continueItems, isEmpty);
      expect(RetroContent.decode('[1,2,3]').learn, isEmpty);
    });

    test('items in each column sort by votes desc, then sortOrder asc',
        () {
      const c = RetroContent(start: [
        RetroItem(id: 'a', title: 'one vote', votes: 1, sortOrder: 0),
        RetroItem(id: 'b', title: 'three votes', votes: 3, sortOrder: 5),
        RetroItem(id: 'c', title: 'zero votes', votes: 0, sortOrder: 1),
        RetroItem(id: 'd', title: 'one vote later', votes: 1, sortOrder: 2),
      ]);
      final back = RetroContent.decode(c.encode());
      // Order should be: b (3 votes), then a + d (1 each, sortOrder
      // breaks tie), then c (0 votes).
      expect(back.start.map((i) => i.id), ['b', 'a', 'd', 'c']);
    });

    test('promotedToActionId round-trips and is omitted when null', () {
      const c = RetroContent(start: [
        RetroItem(id: 's1', title: 't1', promotedToActionId: 'a-1'),
        RetroItem(id: 's2', title: 't2'),
      ]);
      final raw = c.encode();
      final back = RetroContent.decode(raw);
      expect(back.start[0].promotedToActionId, 'a-1');
      expect(back.start[1].promotedToActionId, isNull);

      // Serialised form omits the key for s2.
      final s2Frag = raw.split('"id":"s2"').last;
      expect(s2Frag.contains('promoted_to_action_id'), isFalse);
    });

    test('notes omitted from JSON when null or empty', () {
      const c = RetroContent(start: [
        RetroItem(id: 's1', title: 't', notes: 'present'),
        RetroItem(id: 's2', title: 't'),
        RetroItem(id: 's3', title: 't', notes: ''),
      ]);
      final raw = c.encode();
      final back = RetroContent.decode(raw);
      expect(back.start.firstWhere((i) => i.id == 's1').notes, 'present');
      expect(back.start.firstWhere((i) => i.id == 's2').notes, isNull);
      expect(back.start.firstWhere((i) => i.id == 's3').notes, isNull);
    });
  });

  group('itemsFor / withColumn', () {
    test('itemsFor returns the right column', () {
      const c = RetroContent(
        start: [RetroItem(id: 's')],
        learn: [RetroItem(id: 'l')],
      );
      expect(c.itemsFor(RetroColumn.start), hasLength(1));
      expect(c.itemsFor(RetroColumn.learn), hasLength(1));
      expect(c.itemsFor(RetroColumn.stop), isEmpty);
      expect(c.itemsFor('nope'), isEmpty);
    });

    test('withColumn replaces only the named column', () {
      const c = RetroContent(
        start: [RetroItem(id: 's')],
        learn: [RetroItem(id: 'l')],
      );
      final next = c.withColumn(
          RetroColumn.start, [const RetroItem(id: 's2')]);
      expect(next.start.single.id, 's2');
      expect(next.learn.single.id, 'l');
    });
  });

  group('RetroItem.copyWith', () {
    test('notes sentinel: no arg preserves, explicit null clears', () {
      const a = RetroItem(id: 'x', title: 't', notes: 'n');
      expect(a.copyWith(title: 'u').notes, 'n');
      expect(a.copyWith(notes: null).notes, isNull);
    });

    test('promotedToActionId sentinel semantics', () {
      const a =
          RetroItem(id: 'x', title: 't', promotedToActionId: 'a1');
      expect(a.copyWith(title: 'u').promotedToActionId, 'a1');
      expect(a.copyWith(promotedToActionId: null).promotedToActionId,
          isNull);
    });
  });
}
