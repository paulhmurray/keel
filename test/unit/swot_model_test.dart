import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/templates/instances/swot/swot_model.dart';

void main() {
  group('SwotQuadrant', () {
    test('all lists every quadrant id', () {
      expect(SwotQuadrant.all, hasLength(4));
      expect(SwotQuadrant.all.toSet(), {
        SwotQuadrant.strengths,
        SwotQuadrant.weaknesses,
        SwotQuadrant.opportunities,
        SwotQuadrant.threats,
      });
    });

    test('only Weaknesses and Threats can promote to Risk', () {
      expect(SwotQuadrant.canPromoteToRisk(SwotQuadrant.weaknesses),
          isTrue);
      expect(SwotQuadrant.canPromoteToRisk(SwotQuadrant.threats), isTrue);
      expect(SwotQuadrant.canPromoteToRisk(SwotQuadrant.strengths),
          isFalse);
      expect(SwotQuadrant.canPromoteToRisk(SwotQuadrant.opportunities),
          isFalse);
    });
  });

  group('SwotContent JSON', () {
    test('round-trips a full payload', () {
      const original = SwotContent(
        strengths: [
          SwotItem(id: 's1', text: 'Experienced team', sortOrder: 0),
        ],
        weaknesses: [
          SwotItem(id: 'w1', text: 'New stack', sortOrder: 0),
        ],
        opportunities: [
          SwotItem(id: 'o1', text: 'Funding window', sortOrder: 0),
        ],
        threats: [
          SwotItem(id: 't1', text: 'Vendor risk', sortOrder: 0),
        ],
      );
      final back = SwotContent.decode(original.encode());
      expect(back.strengths.single.text, 'Experienced team');
      expect(back.weaknesses.single.text, 'New stack');
      expect(back.opportunities.single.text, 'Funding window');
      expect(back.threats.single.text, 'Vendor risk');
    });

    test('decode tolerates null / empty / wrong-shape / malformed', () {
      expect(SwotContent.decode(null).strengths, isEmpty);
      expect(SwotContent.decode('').threats, isEmpty);
      expect(SwotContent.decode('not-json').opportunities, isEmpty);
      expect(SwotContent.decode('[1,2,3]').weaknesses, isEmpty);
    });

    test('items in each bucket sort by sort_order on decode', () {
      const c = SwotContent(strengths: [
        SwotItem(id: 'a', text: 'a', sortOrder: 2),
        SwotItem(id: 'b', text: 'b', sortOrder: 0),
        SwotItem(id: 'c', text: 'c', sortOrder: 1),
      ]);
      final back = SwotContent.decode(c.encode());
      expect(back.strengths.map((i) => i.id), ['b', 'c', 'a']);
    });

    test('promoted ids round-trip and are omitted when null', () {
      const c = SwotContent(threats: [
        SwotItem(
            id: 't1',
            text: 'risk-y thing',
            promotedToType: 'risk',
            promotedToId: 'r-uuid-1'),
        SwotItem(id: 't2', text: 'not yet'),
      ]);
      final raw = c.encode();
      final back = SwotContent.decode(raw);
      expect(back.threats[0].promotedToType, 'risk');
      expect(back.threats[0].promotedToId, 'r-uuid-1');
      expect(back.threats[1].promotedToType, isNull);
      expect(back.threats[1].promotedToId, isNull);
      // Serialised form omits the promoted keys on t2.
      final t2Frag = raw.split('"id":"t2"').last;
      expect(t2Frag.contains('promoted_to_type'), isFalse);
    });
  });

  group('itemsFor / withQuadrant helpers', () {
    test('itemsFor returns the right bucket', () {
      const c = SwotContent(strengths: [
        SwotItem(id: 's1', text: 's'),
      ], threats: [
        SwotItem(id: 't1', text: 't'),
      ]);
      expect(c.itemsFor(SwotQuadrant.strengths), hasLength(1));
      expect(c.itemsFor(SwotQuadrant.threats), hasLength(1));
      expect(c.itemsFor(SwotQuadrant.opportunities), isEmpty);
      expect(c.itemsFor('not_real'), isEmpty);
    });

    test('withQuadrant replaces only the named bucket', () {
      const c = SwotContent(
        strengths: [SwotItem(id: 's1', text: 's')],
        threats: [SwotItem(id: 't1', text: 't')],
      );
      final next = c.withQuadrant(SwotQuadrant.strengths,
          [const SwotItem(id: 's2', text: 'replaced')]);
      expect(next.strengths.single.id, 's2');
      expect(next.threats.single.id, 't1'); // untouched
    });
  });

  group('SwotItem.copyWith', () {
    test('promoted-to-type / id sentinel semantics', () {
      const a = SwotItem(
          id: 'x',
          text: 't',
          promotedToType: 'risk',
          promotedToId: 'r1');
      // No promoted args → preserved
      final b = a.copyWith(text: 'updated');
      expect(b.promotedToType, 'risk');
      expect(b.promotedToId, 'r1');
      // Explicit null → cleared
      final c = a.copyWith(promotedToType: null, promotedToId: null);
      expect(c.promotedToType, isNull);
      expect(c.promotedToId, isNull);
    });
  });
}
