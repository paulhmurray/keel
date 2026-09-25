import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/raid_conversion_service.dart';
import 'package:keel/core/raid/raid_lifecycle.dart';

void main() {
  final now = DateTime(2026, 9, 22);

  group('isTerminalStatus', () {
    test('per-register terminal sets', () {
      expect(isTerminalStatus(RaidKind.risk, 'closed'), isTrue);
      expect(isTerminalStatus(RaidKind.risk, 'accepted'), isTrue);
      expect(isTerminalStatus(RaidKind.risk, 'in progress'), isFalse);
      expect(isTerminalStatus(RaidKind.assumption, 'validated'), isTrue);
      expect(isTerminalStatus(RaidKind.assumption, 'invalidated'), isTrue);
      expect(isTerminalStatus(RaidKind.assumption, 'open'), isFalse);
      expect(isTerminalStatus(RaidKind.issue, 'closed'), isTrue);
      expect(isTerminalStatus(RaidKind.dependency, 'closed'), isTrue);
      expect(isTerminalStatus(RaidKind.decision, 'decided'), isTrue);
      expect(isTerminalStatus(RaidKind.decision, 'approved'), isTrue);
      expect(isTerminalStatus(RaidKind.decision, 'rejected'), isTrue);
      expect(isTerminalStatus(RaidKind.decision, 'deferred'), isFalse);
      expect(isTerminalStatus(RaidKind.decision, 'pending'), isFalse);
    });

    test('"resolved" is a nudge to close, not an end state', () {
      expect(isTerminalStatus(RaidKind.issue, 'resolved'), isFalse);
      expect(isTerminalStatus(RaidKind.dependency, 'resolved'), isFalse);
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

    test('closed within two weeks stays visible', () {
      expect(
          isAgedOut(
              kind: RaidKind.risk,
              status: 'closed',
              closedAt: '2026-09-10',
              updatedAt: DateTime(2026, 9, 10),
              now: now),
          isFalse);
    });

    test('closed more than two weeks ago ages out', () {
      expect(
          isAgedOut(
              kind: RaidKind.risk,
              status: 'closed',
              closedAt: '2026-09-01',
              updatedAt: DateTime(2026, 9, 21), // touched since — irrelevant
              now: now),
          isTrue);
    });

    test('pre-v61 rows fall back to last update', () {
      expect(
          isAgedOut(
              kind: RaidKind.issue,
              status: 'closed',
              closedAt: null,
              updatedAt: DateTime(2026, 8, 1),
              now: now),
          isTrue);
      expect(
          isAgedOut(
              kind: RaidKind.issue,
              status: 'closed',
              closedAt: null,
              updatedAt: DateTime(2026, 9, 15),
              now: now),
          isFalse);
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
              newStatus: 'accepted',
              existing: '2026-09-01',
              today: now),
          '2026-09-01');
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

    test('hides only aged-out closed items by default', () {
      final part = partitionAgedOut(items,
          kind: RaidKind.dependency,
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
      expect(s.open.map((r) => r.id), ['r1']);
      expect(s.closed.map((r) => r.id), ['r2', 'r3']);
    });

    test('closed rows carry closed-on, note fallback, newest first', () {
      final rows = closedRaidRows(
        risks: [
          risk('r1', 'open'),
          risk('r2', 'closed', closedAt: '2026-08-01', note: 'Mitigated'),
          risk('r3', 'accepted'), // no closedAt → updatedAt 2026-06-01
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
      expect(rows.map((r) => r.ref), ['I1', 'R2', 'R3']);
      expect(rows[0].description, 'Env down');
      expect(rows[0].note, 'Rebuilt');
      expect(rows[1].closedOn, '2026-08-01');
      expect(rows[1].note, 'Mitigated');
      expect(rows[2].closedOn, '2026-06-01');
      expect(rows[2].status, 'accepted');
    });
  });
}
