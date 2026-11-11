import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/raid_conversion_service.dart';
import 'package:keel/core/raid/raid_lifecycle.dart';

void main() {
  final now = DateTime(2026, 9, 22);

  group('isTerminalStatus', () {
    test('closed is the one end state in every RAID register', () {
      expect(isTerminalStatus(RaidKind.risk, 'closed'), isTrue);
      expect(isTerminalStatus(RaidKind.risk, 'accepted'), isFalse);
      expect(isTerminalStatus(RaidKind.risk, 'in progress'), isFalse);
      expect(isTerminalStatus(RaidKind.assumption, 'closed'), isTrue);
      expect(isTerminalStatus(RaidKind.assumption, 'validated'), isFalse);
      expect(isTerminalStatus(RaidKind.assumption, 'invalidated'), isFalse);
      expect(isTerminalStatus(RaidKind.assumption, 'open'), isFalse);
      expect(isTerminalStatus(RaidKind.issue, 'closed'), isTrue);
      expect(isTerminalStatus(RaidKind.dependency, 'closed'), isTrue);
      expect(isTerminalStatus(RaidKind.decision, 'decided'), isTrue);
      expect(isTerminalStatus(RaidKind.decision, 'approved'), isTrue);
      expect(isTerminalStatus(RaidKind.decision, 'rejected'), isTrue);
      expect(isTerminalStatus(RaidKind.decision, 'deferred'), isFalse);
      expect(isTerminalStatus(RaidKind.decision, 'pending'), isFalse);
    });

    test('settled states are on the books, not finished', () {
      expect(isTerminalStatus(RaidKind.issue, 'resolved'), isFalse);
      expect(isTerminalStatus(RaidKind.dependency, 'resolved'), isFalse);
      expect(isSettledStatus(RaidKind.risk, 'accepted'), isTrue);
      expect(isSettledStatus(RaidKind.risk, 'Accepted'), isTrue);
      expect(isSettledStatus(RaidKind.assumption, 'validated'), isTrue);
      expect(isSettledStatus(RaidKind.assumption, 'invalidated'), isTrue);
      expect(isSettledStatus(RaidKind.issue, 'resolved'), isTrue);
      expect(isSettledStatus(RaidKind.dependency, 'resolved'), isTrue);
      expect(isSettledStatus(RaidKind.risk, 'closed'), isFalse);
      expect(isSettledStatus(RaidKind.decision, 'deferred'), isFalse);
    });

    test('active means neither closed nor settled', () {
      expect(isActiveStatus(RaidKind.risk, 'open'), isTrue);
      expect(isActiveStatus(RaidKind.risk, 'in progress'), isTrue);
      expect(isActiveStatus(RaidKind.risk, 'accepted'), isFalse);
      expect(isActiveStatus(RaidKind.risk, 'closed'), isFalse);
      expect(isActiveStatus(RaidKind.issue, 'resolved'), isFalse);
    });

    test('case-insensitive', () {
      expect(isTerminalStatus(RaidKind.risk, 'Closed'), isTrue);
    });
  });

  group('closureClockStart', () {
    test('uses closed-on when present, else last update', () {
      expect(
          closureClockStart(
              closedAt: '2026-09-01', updatedAt: DateTime(2026, 9, 20)),
          DateTime(2026, 9, 1));
      expect(
          closureClockStart(closedAt: null, updatedAt: DateTime(2026, 9, 20)),
          DateTime(2026, 9, 20));
      expect(
          closureClockStart(
              closedAt: 'garbage', updatedAt: DateTime(2026, 9, 20)),
          DateTime(2026, 9, 20));
    });
  });

  group('isAgedOut', () {
    test('open items never age out however old', () {
      expect(
          isAgedOut(
              kind: RaidKind.risk,
              status: 'open',
              closedAt: null,
              updatedAt: DateTime(2025, 1, 1),
              now: now),
          isFalse);
    });

    test('a closed RAID item hides at once, however fresh', () {
      expect(
          isAgedOut(
              kind: RaidKind.risk,
              status: 'closed',
              closedAt: '2026-09-22',
              updatedAt: now,
              now: now),
          isTrue);
      expect(
          isAgedOut(
              kind: RaidKind.issue,
              status: 'closed',
              closedAt: null,
              updatedAt: now,
              now: now),
          isTrue);
    });

    test('settled items never hide', () {
      for (final (kind, status) in [
        (RaidKind.risk, 'accepted'),
        (RaidKind.assumption, 'validated'),
        (RaidKind.issue, 'resolved'),
        (RaidKind.dependency, 'resolved'),
      ]) {
        expect(
            isAgedOut(
                kind: kind,
                status: status,
                closedAt: null,
                updatedAt: DateTime(2025, 1, 1),
                now: now),
            isFalse,
            reason: '$status ${kind.name}');
      }
    });

    test('a made decision keeps its two-week grace', () {
      expect(hideAfterDaysFor(RaidKind.decision), 14);
      expect(hideAfterDaysFor(RaidKind.risk), 0);
      expect(
          isAgedOut(
              kind: RaidKind.decision,
              status: 'approved',
              closedAt: '2026-09-10',
              updatedAt: DateTime(2026, 9, 10),
              now: now),
          isFalse);
      expect(
          isAgedOut(
              kind: RaidKind.decision,
              status: 'approved',
              closedAt: '2026-09-01',
              updatedAt: DateTime(2026, 9, 21), // touched since — irrelevant
              now: now),
          isTrue);
      // Pre-v61 rows fall back to last update.
      expect(
          isAgedOut(
              kind: RaidKind.decision,
              status: 'decided',
              closedAt: null,
              updatedAt: DateTime(2026, 8, 1),
              now: now),
          isTrue);
    });
  });

  group('settledNudge', () {
    test('quiet until three weeks settled', () {
      expect(
          settledNudge(
              kind: RaidKind.issue,
              status: 'resolved',
              updatedAt: DateTime(2026, 9, 10),
              now: now),
          isNull);
      expect(
          settledNudge(
              kind: RaidKind.issue,
              status: 'open',
              updatedAt: DateTime(2025, 1, 1),
              now: now),
          isNull,
          reason: 'open items are not settled');
      expect(
          settledNudge(
              kind: RaidKind.risk,
              status: 'closed',
              updatedAt: DateTime(2025, 1, 1),
              now: now),
          isNull,
          reason: 'closed items are finished');
    });

    test('names the state, the age and the ask per register', () {
      expect(
          settledNudge(
              kind: RaidKind.risk,
              status: 'accepted',
              updatedAt: DateTime(2026, 8, 18),
              now: now),
          'Accepted 5w ago — still carrying it? Close it or review it');
      expect(
          settledNudge(
              kind: RaidKind.issue,
              status: 'resolved',
              updatedAt: DateTime(2026, 9, 1),
              now: now),
          'Resolved 3w ago — confirm and close it, or reopen');
      expect(
          settledNudge(
              kind: RaidKind.assumption,
              status: 'invalidated',
              updatedAt: DateTime(2026, 7, 1),
              now: now),
          startsWith('Invalidated 11w ago — close it, or raise'));
    });
  });

  group('nextClosedAt', () {
    test('stamps today on first entry to a terminal state', () {
      expect(
          nextClosedAt(
              kind: RaidKind.risk,
              newStatus: 'closed',
              existing: null,
              today: now),
          '2026-09-22');
    });

    test('keeps the original date while it stays closed', () {
      expect(
          nextClosedAt(
              kind: RaidKind.risk,
              newStatus: 'closed',
              existing: '2026-09-01',
              today: now),
          '2026-09-01');
    });

    test('settling is not closing: accepted and validated are not stamped', () {
      expect(
          nextClosedAt(
              kind: RaidKind.risk,
              newStatus: 'accepted',
              existing: null,
              today: now),
          isNull);
      expect(
          nextClosedAt(
              kind: RaidKind.assumption,
              newStatus: 'validated',
              existing: null,
              today: now),
          isNull);
    });

    test('clears on reopen so the clock resets next time', () {
      expect(
          nextClosedAt(
              kind: RaidKind.risk,
              newStatus: 'open',
              existing: '2026-09-01',
              today: now),
          isNull);
    });

    test('resolved issue is not stamped', () {
      expect(
          nextClosedAt(
              kind: RaidKind.issue,
              newStatus: 'resolved',
              existing: null,
              today: now),
          isNull);
    });
  });

  group('partitionAgedOut', () {
    final items = [
      (id: 'open', status: 'open', closedAt: null, updatedAt: DateTime(2026, 1, 1)),
      (id: 'fresh', status: 'closed', closedAt: '2026-09-15', updatedAt: DateTime(2026, 9, 15)),
      (id: 'old', status: 'closed', closedAt: '2026-08-01', updatedAt: DateTime(2026, 8, 1)),
    ];

    test('hides every closed item by default, fresh or old', () {
      final part = partitionAgedOut(items,
          kind: RaidKind.dependency,
          status: (x) => x.status,
          closedAt: (x) => x.closedAt,
          updatedAt: (x) => x.updatedAt,
          showClosed: false,
          now: now);
      expect(part.visible.map((x) => x.id), ['open']);
      expect(part.hidden.map((x) => x.id), ['fresh', 'old']);
    });

    test('decisions keep fresh ones and hide old ones', () {
      final part = partitionAgedOut(items,
          kind: RaidKind.decision,
          status: (x) => x.status,
          closedAt: (x) => x.closedAt,
          updatedAt: (x) => x.updatedAt,
          showClosed: false,
          now: now);
      expect(part.visible.map((x) => x.id), ['open', 'fresh']);
      expect(part.hidden.map((x) => x.id), ['old']);
    });

    test('show closed brings everything back, in order', () {
      final part = partitionAgedOut(items,
          kind: RaidKind.dependency,
          status: (x) => x.status,
          closedAt: (x) => x.closedAt,
          updatedAt: (x) => x.updatedAt,
          showClosed: true,
          now: now);
      expect(part.visible.map((x) => x.id), ['open', 'fresh', 'old']);
      expect(part.hidden, isEmpty);
    });
  });

  group('splitClosed / closedRaidRows', () {
    Risk risk(String id, String status, {String? closedAt, String? note}) =>
        Risk(
          id: id,
          projectId: 'p',
          ref: id.toUpperCase(),
          description: 'Risk $id',
          likelihood: 'low',
          impact: 'low',
          status: status,
          closedAt: closedAt,
          closureNote: note,
          source: 'manual',
          steerco: false,
          strategy: 'treat',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 6, 1),
        );

    test('splitClosed separates by terminal status', () {
      final s = splitClosed<Risk>(
          [risk('r1', 'open'), risk('r2', 'closed'), risk('r3', 'accepted')],
          kind: RaidKind.risk,
          status: (r) => r.status);
      expect(s.open.map((r) => r.id), ['r1', 'r3'], reason: 'accepted is still open');
      expect(s.closed.map((r) => r.id), ['r2']);
    });

    test('closed rows carry closed-on, note fallback, newest first', () {
      final rows = closedRaidRows(
        risks: [
          risk('r1', 'open'),
          risk('r2', 'closed', closedAt: '2026-08-01', note: 'Mitigated'),
          risk('r3', 'accepted'), // settled, not closed: not exported here
          risk('r4', 'closed'), // no closedAt → updatedAt 2026-06-01
        ],
        assumptions: const [],
        issues: [
          Issue(
            id: 'i1',
            projectId: 'p',
            ref: 'I1',
            title: 'Env down',
            description: 'long form',
            escalationRequired: false,
            priority: 'high',
            status: 'closed',
            resolution: 'Rebuilt',
            closedAt: '2026-09-10',
            source: 'manual',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 9, 10),
          ),
        ],
        dependencies: const [],
      );
      expect(rows.map((r) => r.ref), ['I1', 'R2', 'R4']);
      expect(rows[0].description, 'Env down');
      expect(rows[0].note, 'Rebuilt');
      expect(rows[1].closedOn, '2026-08-01');
      expect(rows[1].note, 'Mitigated');
      expect(rows[2].closedOn, '2026-06-01');
      expect(rows[2].status, 'closed');
    });
  });
}
