import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/templates/instances/stakeholder_map/stakeholder_map_model.dart';

void main() {
  group('StakeholderMapContent JSON', () {
    test('round-trips dots with positions and notes', () {
      const original = StakeholderMapContent(stakeholders: [
        StakeholderDot(
          id: 'd1',
          personId: 'p1',
          positionX: 0.85,
          positionY: 0.2,
          notes: 'Highest priority',
        ),
        StakeholderDot(id: 'd2', personId: 'p2'),
      ]);
      final back =
          StakeholderMapContent.decode(original.encode());
      expect(back.stakeholders, hasLength(2));
      expect(back.stakeholders[0].personId, 'p1');
      expect(back.stakeholders[0].positionX, closeTo(0.85, 1e-9));
      expect(back.stakeholders[0].positionY, closeTo(0.2, 1e-9));
      expect(back.stakeholders[0].notes, 'Highest priority');
      // Defaults round-trip too.
      expect(back.stakeholders[1].positionX, 0.5);
      expect(back.stakeholders[1].positionY, 0.5);
      expect(back.stakeholders[1].notes, isNull);
    });

    test('decode tolerates null / empty / malformed / wrong-shape', () {
      expect(StakeholderMapContent.decode(null).stakeholders, isEmpty);
      expect(StakeholderMapContent.decode('').stakeholders, isEmpty);
      expect(StakeholderMapContent.decode('garbage').stakeholders, isEmpty);
      expect(StakeholderMapContent.decode('[1,2]').stakeholders, isEmpty);
    });

    test('positions out of [0,1] are clamped on decode', () {
      final c = StakeholderMapContent.decode(
          '{"stakeholders":[{"id":"d","person_id":"p","position_x":2.5,"position_y":-0.4}]}');
      expect(c.stakeholders.single.positionX, 1.0);
      expect(c.stakeholders.single.positionY, 0.0);
    });

    test('missing position fields default to 0.5 (centre)', () {
      final c = StakeholderMapContent.decode(
          '{"stakeholders":[{"id":"d","person_id":"p"}]}');
      expect(c.stakeholders.single.positionX, 0.5);
      expect(c.stakeholders.single.positionY, 0.5);
    });

    test('notes omitted from serialised form when null or empty', () {
      const c = StakeholderMapContent(stakeholders: [
        StakeholderDot(id: 'd1', personId: 'p1', notes: 'has notes'),
        StakeholderDot(id: 'd2', personId: 'p2'),
        StakeholderDot(id: 'd3', personId: 'p3', notes: ''),
      ]);
      final raw = c.encode();
      final back = StakeholderMapContent.decode(raw);
      expect(back.stakeholders[0].notes, 'has notes');
      expect(back.stakeholders[1].notes, isNull);
      expect(back.stakeholders[2].notes, isNull);

      // The serialised form should not include "notes" keys for d2/d3.
      for (final id in ['d2', 'd3']) {
        final frag = raw.split('"id":"$id"').last;
        expect(frag.contains('"notes"'), isFalse,
            reason: '$id should not have notes serialised');
      }
    });
  });

  group('containsPerson', () {
    test('returns true only when a dot for that person exists', () {
      const c = StakeholderMapContent(stakeholders: [
        StakeholderDot(id: 'd1', personId: 'p1'),
      ]);
      expect(c.containsPerson('p1'), isTrue);
      expect(c.containsPerson('p2'), isFalse);
    });
  });

  group('StakeholderDot.copyWith', () {
    test('clamps positions to [0,1]', () {
      const a = StakeholderDot(id: 'd', personId: 'p');
      expect(a.copyWith(positionX: 2.0).positionX, 1.0);
      expect(a.copyWith(positionX: -0.3).positionX, 0.0);
      expect(a.copyWith(positionY: 1.5).positionY, 1.0);
      expect(a.copyWith(positionY: -2).positionY, 0.0);
    });

    test('notes sentinel: no-arg preserves, explicit null clears', () {
      const a =
          StakeholderDot(id: 'd', personId: 'p', notes: 'kept');
      expect(a.copyWith(positionX: 0.1).notes, 'kept');
      expect(a.copyWith(notes: null).notes, isNull);
    });
  });

  group('StakeholderQuadrant.at', () {
    // Reminder: y=0 is HIGH influence (top), y=1 is LOW influence.
    test('top-left = Keep Satisfied (high influence, low interest)', () {
      expect(StakeholderQuadrant.at(0.1, 0.1),
          StakeholderQuadrant.keepSatisfied);
    });

    test('top-right = Manage Closely (high influence, high interest)',
        () {
      expect(StakeholderQuadrant.at(0.9, 0.1),
          StakeholderQuadrant.manageClosely);
    });

    test('bottom-left = Monitor (low influence, low interest)', () {
      expect(StakeholderQuadrant.at(0.1, 0.9),
          StakeholderQuadrant.monitor);
    });

    test('bottom-right = Keep Informed (low influence, high interest)',
        () {
      expect(StakeholderQuadrant.at(0.9, 0.9),
          StakeholderQuadrant.keepInformed);
    });
  });
}
