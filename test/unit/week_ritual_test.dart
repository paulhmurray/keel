import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/helm/week_ritual.dart';

/// Allocation arithmetic, day capacity, mission drafting, morning
/// prefill placement and the two nudges — all in 30-minute slots.
WeekPlanObjective _obj(String id, String label,
        {String alloc = '{}', int? target, bool done = false,
        String? projectId, String? actionId}) =>
    WeekPlanObjective(
      id: id, weekPlanId: 'w', sortOrder: 0, label: label,
      projectId: projectId, linkedActionId: actionId, targetBlocks: target,
      done: done, dayAllocationsJson: alloc,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

DayPlanBlock _block(int start, int end,
        {String kind = 'focus', int revision = 0, String? objectiveId,
        bool done = false}) =>
    DayPlanBlock(
      id: '$start-$end', dayPlanId: 'd', revision: revision,
      startMinute: start, endMinute: end, kind: kind, label: 'x',
      objectiveId: objectiveId, done: done,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

WeekPlan _plan({DateTime? charted, DateTime? reviewed}) => WeekPlan(
      id: 'w', weekStartDate: '2026-10-05', dayMissionsJson: '{}',
      chartedAt: charted, reviewedAt: reviewed,
      createdAt: DateTime(2026), updatedAt: DateTime(2026),
    );

void main() {
  group('allocations', () {
    test('parse drops zeros, bad days and junk; encode round-trips', () {
      expect(parseDayAllocations('{"0":2,"2":4,"7":1,"3":0,"x":2,"4":"3"}'),
          {0: 2, 2: 4, 4: 3});
      expect(parseDayAllocations(null), isEmpty);
      expect(parseDayAllocations('nope'), isEmpty);
      expect(encodeDayAllocations({1: 3, 0: 0, 9: 2}), '{"1":3}');
      expect(allocatedSlots({0: 2, 2: 4}), 6);
      expect(dayLoad([{0: 2}, {0: 1, 1: 3}], 0), 3);
    });
  });

  group('capacity', () {
    test('meetings on the effective schedule reduce the day, floored at zero',
        () {
      final blocks = [
        _block(540, 600, kind: 'meeting'),
        _block(600, 645, kind: 'meeting'), // 45 min rounds up to 2 slots
        _block(700, 760, kind: 'meeting', revision: 0), // superseded below
        _block(700, 760, kind: 'focus', revision: 1),
      ];
      expect(meetingSlots(blocks, [700]), 4);
      expect(dayCapacity(focusSlotsPerDay: 8, meetingSlots: 4), 4);
      expect(dayCapacity(focusSlotsPerDay: 2, meetingSlots: 4), 0);
      expect(overcommitted(load: 5, capacity: 4), isTrue);
      expect(overcommitted(load: 4, capacity: 4), isFalse);
    });
  });

  group('missions', () {
    test('drafts from the day\'s rocks, biggest first, null when none', () {
      final rocks = [
        (label: 'Status pack', allocations: {0: 1, 1: 2}),
        (label: 'Build adapter', allocations: {0: 3}),
        (label: 'Elsewhere', allocations: {3: 2}),
      ];
      expect(draftDayMission(rocks, 0), 'Build adapter · Status pack');
      expect(draftDayMission(rocks, 1), 'Status pack');
      expect(draftDayMission(rocks, 2), isNull);
    });
  });

  group('review rows', () {
    test('done slots and met state come from the week\'s blocks', () {
      final o = _obj('o1', 'Adapter', target: 3);
      final blocks = [
        _block(540, 600, objectiveId: 'o1', done: true), // 2 slots
        _block(600, 630, objectiveId: 'o1', done: true), // 1 slot
        _block(630, 660, objectiveId: 'o1', done: false),
      ];
      final rows = reviewRows([o], blocks, {'d': const []});
      expect(rows.single.doneSlots, 3);
      expect(rows.single.met, isTrue);
    });
  });

  group('prefill', () {
    test('places each allocated rock into free gaps, biggest first', () {
      final objs = [
        _obj('a', 'Status pack', alloc: '{"0":1}', projectId: 'p1', actionId: 'ac1'),
        _obj('b', 'Build adapter', alloc: '{"0":3}'),
        _obj('c', 'Not today', alloc: '{"1":2}'),
        _obj('d', 'Done already', alloc: '{"0":2}', done: true),
      ];
      final out = prefillBlocks(
        objectives: objs, weekday: 0, dayStart: 540, dayEnd: 1020,
        existing: [(startMinute: 600, endMinute: 660)], // 10:00–11:00 meeting
      );
      expect(out.map((b) => b.label), ['Build adapter', 'Status pack']);
      // 90 min won't fit before the meeting (540–600 is 60), so it lands after.
      expect((out[0].startMinute, out[0].endMinute), (660, 750));
      expect((out[1].startMinute, out[1].endMinute), (750, 780));
      expect(out[1].objectiveId, 'a');
      expect(out[1].projectId, 'p1');
      expect(out[1].linkedActionId, 'ac1');
    });

    test('a rock that cannot fit is appended rather than dropped', () {
      final out = prefillBlocks(
        objectives: [_obj('a', 'Big', alloc: '{"0":8}')],
        weekday: 0, dayStart: 540, dayEnd: 660,
        existing: [(startMinute: 540, endMinute: 600)],
      );
      expect(out.single.startMinute, 600);
      expect(out.single.endMinute, 840);
    });

    test('nothing allocated to the day means nothing placed', () {
      expect(
          prefillBlocks(
              objectives: [_obj('a', 'x', alloc: '{"1":2}')],
              weekday: 0, dayStart: 540, dayEnd: 1020),
          isEmpty);
    });
  });

  group('nudges', () {
    test('charting is needed without a plan, or with an uncharted empty one',
        () {
      expect(weekNeedsCharting(null, const []), isTrue);
      expect(weekNeedsCharting(_plan(), const []), isTrue);
      expect(weekNeedsCharting(_plan(), [_obj('a', 'x')]), isFalse,
          reason: 'rocks added by hand count as a plan');
      expect(weekNeedsCharting(_plan(charted: DateTime(2026)), const []), isFalse);
    });

    test('review is needed from Friday, with rocks, until it is done', () {
      final rocks = [_obj('a', 'x')];
      expect(weekNeedsReview(_plan(), rocks, DateTime(2026, 10, 8)), isFalse,
          reason: 'Thursday');
      expect(weekNeedsReview(_plan(), rocks, DateTime(2026, 10, 9)), isTrue,
          reason: 'Friday');
      expect(weekNeedsReview(_plan(), const [], DateTime(2026, 10, 9)), isFalse);
      expect(weekNeedsReview(_plan(reviewed: DateTime(2026)), rocks, DateTime(2026, 10, 10)),
          isFalse);
      expect(weekNeedsReview(null, rocks, DateTime(2026, 10, 9)), isFalse);
    });
  });
}
