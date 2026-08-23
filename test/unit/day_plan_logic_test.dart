import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/helm/day_plan_logic.dart';

DayPlanBlock _block({
  String id = 'b',
  int revision = 0,
  required int start,
  required int end,
  String label = 'work',
  String kind = 'focus',
  bool done = false,
}) {
  final now = DateTime(2026, 8, 20);
  return DayPlanBlock(
    id: id,
    dayPlanId: 'plan',
    revision: revision,
    startMinute: start,
    endMinute: end,
    kind: kind,
    label: label,
    projectId: null,
    linkedActionId: null,
    done: done,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('parseRevisionStarts', () {
    test('empty and malformed json parse to no revisions', () {
      expect(parseRevisionStarts('[]'), isEmpty);
      expect(parseRevisionStarts('not json'), isEmpty);
    });

    test('decodes revision start minutes in order', () {
      expect(parseRevisionStarts('[540, 840]'), [540, 840]);
    });
  });

  group('governingRevisionAt', () {
    test('revision 0 governs the whole day when never revised', () {
      expect(governingRevisionAt(360, []), 0);
      expect(governingRevisionAt(1260, []), 0);
    });

    test('each revision governs from its start until the next', () {
      final starts = [540, 840]; // rev 1 from 09:00, rev 2 from 14:00
      expect(governingRevisionAt(360, starts), 0);
      expect(governingRevisionAt(539, starts), 0);
      expect(governingRevisionAt(540, starts), 1);
      expect(governingRevisionAt(839, starts), 1);
      expect(governingRevisionAt(840, starts), 2);
      expect(governingRevisionAt(1200, starts), 2);
    });
  });

  group('isBlockSuperseded / effectiveSchedule', () {
    test('old-column blocks past the revision point are superseded', () {
      final starts = [540];
      final morning = _block(id: 'm', revision: 0, start: 420, end: 480);
      final oldAfternoon =
          _block(id: 'o', revision: 0, start: 600, end: 660);
      final newAfternoon =
          _block(id: 'n', revision: 1, start: 600, end: 660);

      expect(isBlockSuperseded(morning, starts), isFalse);
      expect(isBlockSuperseded(oldAfternoon, starts), isTrue);
      expect(isBlockSuperseded(newAfternoon, starts), isFalse);

      final schedule = effectiveSchedule(
          [oldAfternoon, newAfternoon, morning], starts);
      expect(schedule.map((b) => b.id), ['m', 'n']);
    });

    test('a block in progress at the revision point stays active', () {
      // Started 08:30, revision at 09:00 — governed by its own column.
      final starts = [540];
      final straddling =
          _block(id: 's', revision: 0, start: 510, end: 570);
      expect(isBlockSuperseded(straddling, starts), isFalse);
    });
  });

  group('blockAt / blocksAfter', () {
    final starts = [540];
    final blocks = [
      _block(id: 'a', revision: 0, start: 420, end: 480),
      _block(id: 'stale', revision: 0, start: 600, end: 660),
      _block(id: 'b', revision: 1, start: 600, end: 690),
      _block(id: 'c', revision: 1, start: 720, end: 750),
    ];

    test('blockAt returns the effective block covering the minute', () {
      expect(blockAt(blocks, starts, 430)?.id, 'a');
      expect(blockAt(blocks, starts, 620)?.id, 'b');
      expect(blockAt(blocks, starts, 700), isNull);
    });

    test('blocksAfter lists upcoming effective blocks only', () {
      expect(blocksAfter(blocks, starts, 500).map((b) => b.id), ['b', 'c']);
      expect(blocksAfter(blocks, starts, 610).map((b) => b.id), ['c']);
    });
  });

  group('imminentHomeBlock', () {
    final pickup = _block(
        id: 'pickup', start: 930, end: 960, kind: 'home', label: 'Kids');
    final work = _block(id: 'w', start: 840, end: 930);

    test('surfaces the next home block only within the window', () {
      // 14:31 — pickup at 15:30 is 59 minutes out: shown.
      expect(imminentHomeBlock([work, pickup], [], 871)?.id, 'pickup');
      // 14:29 — 61 minutes out: not yet.
      expect(imminentHomeBlock([work, pickup], [], 869), isNull);
    });

    test('an in-progress home block still shows (GO NOW state)', () {
      expect(imminentHomeBlock([pickup], [], 945)?.id, 'pickup');
    });

    test('done home blocks are skipped', () {
      final donePickup = _block(
          id: 'p2', start: 930, end: 960, kind: 'home', done: true);
      expect(imminentHomeBlock([donePickup], [], 920), isNull);
    });

    test('non-home blocks never trigger it', () {
      expect(imminentHomeBlock([work], [], 830), isNull);
    });

    test('a superseded home block does not fire — the revision moved it',
        () {
      // Original pickup at 15:30 in rev 0, moved to 16:00 in rev 1
      // (revision started 14:00).
      final moved = _block(
          id: 'moved',
          revision: 1,
          start: 960,
          end: 990,
          kind: 'home',
          label: 'Kids');
      final starts = [840];
      final result = imminentHomeBlock([pickup, moved], starts, 931);
      expect(result?.id, 'moved');
    });
  });

  test('formatMinute renders HH:MM', () {
    expect(formatMinute(360), '06:00');
    expect(formatMinute(1005), '16:45');
  });
}
