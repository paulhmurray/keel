import 'package:flutter_test/flutter_test.dart';
import 'package:keel/features/canvas/templates/instances/raci_matrix/raci_model.dart';

void main() {
  group('RaciRole.next click-cycle', () {
    test('blank → R → A → C → I → blank', () {
      expect(RaciRole.next(null), 'R');
      expect(RaciRole.next('R'), 'A');
      expect(RaciRole.next('A'), 'C');
      expect(RaciRole.next('C'), 'I');
      expect(RaciRole.next('I'), null);
    });

    test('unknown values reset to R', () {
      expect(RaciRole.next('weird'), 'R');
    });
  });

  group('RaciContent JSON', () {
    test('round-trips activities + people + assignments', () {
      const original = RaciContent(
        activities: [
          RaciActivity(id: 'a1', name: 'Architecture sign-off'),
          RaciActivity(id: 'a2', name: 'Procurement', sortOrder: 1),
        ],
        people: [
          RaciPerson(id: 'p1', name: 'Paul', personId: 'person-paul'),
          RaciPerson(id: 'p2', name: 'Sarah', sortOrder: 1),
        ],
        assignments: [
          RaciAssignment(activityId: 'a1', personId: 'p1', role: 'A'),
          RaciAssignment(activityId: 'a2', personId: 'p1', role: 'R'),
        ],
      );
      final back = RaciContent.decode(original.encode());
      expect(back.activities, hasLength(2));
      expect(back.activities[0].name, 'Architecture sign-off');
      expect(back.people[0].personId, 'person-paul');
      expect(back.people[1].personId, isNull);
      expect(back.assignments, hasLength(2));
      expect(back.assignments[0].role, 'A');
    });

    test('decode tolerates null / empty / malformed / wrong-shape', () {
      expect(RaciContent.decode(null).activities, isEmpty);
      expect(RaciContent.decode('').people, isEmpty);
      expect(RaciContent.decode('not-json').assignments, isEmpty);
      expect(RaciContent.decode('[]').activities, isEmpty);
    });

    test('activities and people are sorted by sortOrder on decode', () {
      const c = RaciContent(
        activities: [
          RaciActivity(id: 'a', name: 'a', sortOrder: 2),
          RaciActivity(id: 'b', name: 'b', sortOrder: 0),
          RaciActivity(id: 'c', name: 'c', sortOrder: 1),
        ],
        people: [
          RaciPerson(id: 'p1', name: 'a', sortOrder: 5),
          RaciPerson(id: 'p2', name: 'b', sortOrder: 0),
        ],
      );
      final back = RaciContent.decode(c.encode());
      expect(back.activities.map((x) => x.id), ['b', 'c', 'a']);
      expect(back.people.map((x) => x.id), ['p2', 'p1']);
    });

    test('person_id omitted from serialisation when null (free-text)',
        () {
      const c = RaciContent(people: [
        RaciPerson(id: 'p1', name: 'Linked', personId: 'real-1'),
        RaciPerson(id: 'p2', name: 'Free-text'),
      ]);
      final raw = c.encode();
      final back = RaciContent.decode(raw);
      expect(back.people[0].personId, 'real-1');
      expect(back.people[1].personId, isNull);
      final p2Frag = raw.split('"id":"p2"').last;
      expect(p2Frag.contains('person_id'), isFalse);
    });
  });

  group('roleFor + activitiesByRole', () {
    test('roleFor returns the assigned role or null when blank', () {
      const c = RaciContent(assignments: [
        RaciAssignment(activityId: 'a1', personId: 'p1', role: 'R'),
      ]);
      expect(c.roleFor('a1', 'p1'), 'R');
      expect(c.roleFor('a1', 'p2'), isNull);
      expect(c.roleFor('a2', 'p1'), isNull);
    });

    test('activitiesByRole groups by R/A/C/I for a person', () {
      const c = RaciContent(activities: [
        RaciActivity(id: 'a1', name: 'Arch'),
        RaciActivity(id: 'a2', name: 'Proc'),
        RaciActivity(id: 'a3', name: 'Legal'),
      ], assignments: [
        RaciAssignment(activityId: 'a1', personId: 'p1', role: 'A'),
        RaciAssignment(activityId: 'a2', personId: 'p1', role: 'R'),
        RaciAssignment(activityId: 'a3', personId: 'p1', role: 'C'),
        // Different person — should be ignored.
        RaciAssignment(activityId: 'a1', personId: 'p2', role: 'I'),
      ]);
      final byRole = c.activitiesByRole('p1');
      expect(byRole['A'], ['Arch']);
      expect(byRole['R'], ['Proc']);
      expect(byRole['C'], ['Legal']);
      expect(byRole['I'], isEmpty);
    });
  });

  group('copyWith semantics', () {
    test('RaciPerson.copyWith(personId: null) clears the link', () {
      const p = RaciPerson(id: 'x', name: 'n', personId: 'real-1');
      expect(p.copyWith(personId: null).personId, isNull);
      expect(p.copyWith(name: 'updated').personId, 'real-1');
    });

    test('RaciAssignment.copyWith(role: null) clears the role', () {
      const a =
          RaciAssignment(activityId: 'a', personId: 'p', role: 'R');
      expect(a.copyWith(role: null).role, isNull);
      expect(a.copyWith().role, 'R'); // no-arg preserves
    });
  });
}
