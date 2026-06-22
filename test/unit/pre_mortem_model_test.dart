import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/templates/instances/pre_mortem/pre_mortem_model.dart';

void main() {
  group('PreMortemContent JSON', () {
    test('encode → decode round-trips a full payload', () {
      const original = PreMortemContent(
        goal: 'TAC failed by Sep 2026',
        causes: [
          PreMortemCause(
            id: 'c1',
            description: 'M-POWER slipped 3 weeks',
            likelihood: 'high',
            impact: 'high',
            mitigations: [
              PreMortemMitigation(
                id: 'm1',
                description: 'Weekly escalation',
                owner: 'Paul',
              ),
            ],
          ),
        ],
      );
      final raw = original.encode();
      final back = PreMortemContent.decode(raw);
      expect(back.goal, original.goal);
      expect(back.causes, hasLength(1));
      expect(back.causes.first.description, 'M-POWER slipped 3 weeks');
      expect(back.causes.first.likelihood, 'high');
      expect(back.causes.first.impact, 'high');
      expect(back.causes.first.mitigations, hasLength(1));
      expect(back.causes.first.mitigations.first.owner, 'Paul');
    });

    test('decode is tolerant of null / empty / malformed inputs', () {
      expect(PreMortemContent.decode(null).goal, '');
      expect(PreMortemContent.decode('').goal, '');
      expect(PreMortemContent.decode('not-json').causes, isEmpty);
      // JSON that's the wrong shape.
      expect(PreMortemContent.decode('[1,2,3]').causes, isEmpty);
    });

    test('missing fields default to safe values', () {
      final c = PreMortemContent.decode('{}');
      expect(c.goal, '');
      expect(c.causes, isEmpty);

      final c2 = PreMortemContent.decode(
          '{"goal":"g","causes":[{"id":"x"}]}');
      expect(c2.goal, 'g');
      expect(c2.causes, hasLength(1));
      expect(c2.causes.first.id, 'x');
      expect(c2.causes.first.likelihood, 'medium');
      expect(c2.causes.first.impact, 'medium');
      expect(c2.causes.first.mitigations, isEmpty);
    });

    test('unknown level strings are normalised to medium', () {
      final c = PreMortemContent.decode(
          '{"causes":[{"id":"x","likelihood":"extreme","impact":"???"}]}');
      expect(c.causes.first.likelihood, 'medium');
      expect(c.causes.first.impact, 'medium');
    });

    test('level strings are lowercased on decode', () {
      final c = PreMortemContent.decode(
          '{"causes":[{"id":"x","likelihood":"HIGH","impact":"Low"}]}');
      expect(c.causes.first.likelihood, 'high');
      expect(c.causes.first.impact, 'low');
    });

    test('promoted ids round-trip and are omitted when null', () {
      const c = PreMortemContent(causes: [
        PreMortemCause(id: 'c1', promotedToRiskId: 'r1', mitigations: [
          PreMortemMitigation(id: 'm1', promotedToActionId: 'a1'),
        ]),
        PreMortemCause(id: 'c2', mitigations: [
          PreMortemMitigation(id: 'm2'),
        ]),
      ]);
      final raw = c.encode();
      final back = PreMortemContent.decode(raw);
      expect(back.causes[0].promotedToRiskId, 'r1');
      expect(back.causes[0].mitigations[0].promotedToActionId, 'a1');
      expect(back.causes[1].promotedToRiskId, isNull);
      expect(back.causes[1].mitigations[0].promotedToActionId, isNull);

      // The serialised form omits null promoted ids — keeps the DB
      // payload small and the JSON readable.
      expect(raw.contains('promoted_to_risk_id'), isTrue);
      // c2 has no promoted_to_risk_id key in its object.
      final c2Frag = raw.split('"id":"c2"').last;
      expect(c2Frag.contains('promoted_to_risk_id'), isFalse);
    });
  });

  group('copyWith semantics', () {
    test('cause.copyWith with no promoted arg leaves the id alone', () {
      const c = PreMortemCause(id: 'c1', promotedToRiskId: 'r1');
      final next = c.copyWith(description: 'updated');
      expect(next.promotedToRiskId, 'r1');
    });

    test('cause.copyWith(promotedToRiskId: null) clears it', () {
      const c = PreMortemCause(id: 'c1', promotedToRiskId: 'r1');
      final next = c.copyWith(promotedToRiskId: null);
      expect(next.promotedToRiskId, isNull);
    });

    test('mitigation.copyWith(owner: null) clears the owner', () {
      const m = PreMortemMitigation(id: 'm1', owner: 'Paul');
      final next = m.copyWith(owner: null);
      expect(next.owner, isNull);
    });
  });
}
