import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/portfolio/programme_pulse.dart';

/// Pure pulse computation: the portfolio's minimum data standard, derived
/// from a programme's rows.
void main() {
  final now = DateTime(2026, 10, 30); // Friday
  final t0 = DateTime(2026, 1, 1);

  Project programme({String id = 'prog'}) => Project(
        id: id,
        name: 'Big Programme',
        status: 'active',
        kind: 'programme',
        createdAt: t0,
        updatedAt: t0,
      );

  TimelineWorkPackage wp(String id, String rag, {String? src}) =>
      TimelineWorkPackage(
        id: id,
        projectId: 'prog',
        name: id,
        colourTheme: 'wp1',
        sortOrder: 0,
        ragStatus: rag,
        sourceProjectId: src,
        createdAt: t0,
        updatedAt: t0,
      );

  TimelineActivity milestone(String id, String date,
          {String status = 'planned', String type = 'milestone'}) =>
      TimelineActivity(
        id: id,
        workPackageId: 'wp-1',
        projectId: 'prog',
        name: id,
        activityType: type,
        startDate: date,
        status: status,
        isCritical: false,
        isBaseline: false,
        sortOrder: 0,
        createdAt: t0,
        updatedAt: t0,
      );

  StatusReport report(String rag, DateTime date, {String? src}) =>
      StatusReport(
        id: 'rep-${date.day}-${src ?? 'own'}',
        projectId: 'prog',
        title: 'Weekly',
        overallRag: rag,
        reportDate: date,
        sourceProjectId: src,
        createdAt: date,
        updatedAt: date,
      );

  Decision decision(
    String id, {
    String status = 'pending',
    String? dueDate,
    String? decidedAt,
    DateTime? created,
    DateTime? updated,
  }) =>
      Decision(
        id: id,
        projectId: 'prog',
        description: id,
        status: status,
        dueDate: dueDate,
        decidedAt: decidedAt,
        source: 'manual',
        createdAt: created ?? t0,
        updatedAt: updated ?? created ?? t0,
      );

  Risk risk(String id,
          {String likelihood = 'likely',
          String impact = 'major',
          String status = 'open',
          DateTime? escalated}) =>
      Risk(
        id: id,
        projectId: 'prog',
        description: id,
        likelihood: likelihood,
        impact: impact,
        status: status,
        source: 'manual',
        steerco: false,
        strategy: 'treat',
        escalatedAt: escalated,
        createdAt: t0,
        updatedAt: t0,
      );

  Person person(String id, String name) => Person(
        id: id,
        projectId: 'prog',
        name: name,
        personType: 'colleague',
        isStakeholder: false,
        createdAt: t0,
        updatedAt: t0,
      );

  TeamRole role(String id, String personId, {String? src}) => TeamRole(
        id: id,
        projectId: 'prog',
        roleName: 'Lead',
        teamGroup: 'core',
        personId: personId,
        isScaffold: false,
        isApplicable: true,
        sortOrder: 0,
        sourceProjectId: src,
        createdAt: t0,
        updatedAt: t0,
      );

  group('ids and weeks', () {
    test('weekMondayIso finds the Monday of any weekday', () {
      expect(weekMondayIso(DateTime(2026, 10, 30)), '2026-10-26'); // Fri
      expect(weekMondayIso(DateTime(2026, 10, 26)), '2026-10-26'); // Mon
      expect(weekMondayIso(DateTime(2026, 11, 1)), '2026-10-26'); // Sun
    });

    test('pulseItemId is one per programme per week', () {
      expect(pulseItemId('prog', DateTime(2026, 10, 28)),
          pulseItemId('prog', DateTime(2026, 10, 30)));
      expect(pulseItemId('prog', DateTime(2026, 10, 30)),
          isNot(pulseItemId('prog', DateTime(2026, 11, 2))));
      expect(pulseItemId('prog', now), 'pulse:prog:2026-10-26');
    });
  });

  group('health by rules', () {
    test('computed RAG is worst-wins over every WP, including cascaded',
        () {
      final p = computeProgrammePulse(
        ProgrammePulseInputs(
          programme: programme(),
          workPackages: [wp('a', 'green'), wp('b', 'red', src: 'proj-1')],
        ),
        now: now,
      );
      expect(p.health.computedRag, 'red');
      expect(p.health.workstreams, {'green': 1, 'red': 1});
    });

    test('reported RAG comes from the latest OWN report; cascaded project '
        'reports are ignored', () {
      final p = computeProgrammePulse(
        ProgrammePulseInputs(
          programme: programme(),
          workPackages: [wp('a', 'red')],
          reports: [
            report('amber', DateTime(2026, 10, 10)),
            report('green', DateTime(2026, 10, 24)),
            report('red', DateTime(2026, 10, 28), src: 'proj-1'),
          ],
        ),
        now: now,
      );
      expect(p.health.reportedRag, 'green');
      expect(p.health.reportedAt, '2026-10-24');
      expect(p.health.watermelon, isTrue, reason: 'green reported, red data');
    });

    test('no report is not a watermelon', () {
      final p = computeProgrammePulse(
        ProgrammePulseInputs(
            programme: programme(), workPackages: [wp('a', 'red')]),
        now: now,
      );
      expect(p.health.reportedRag, isNull);
      expect(p.health.watermelon, isFalse);
    });

    test('milestones: overdue vs open, next = soonest future open', () {
      final p = computeProgrammePulse(
        ProgrammePulseInputs(
          programme: programme(),
          activities: [
            milestone('late', '2026-10-01'),
            milestone('done-late', '2026-09-01', status: 'complete'),
            milestone('soon', '2026-11-20'),
            milestone('sooner', '2026-11-05', type: 'gate'),
            milestone('task', '2026-11-01', type: 'task'),
          ],
        ),
        now: now,
      );
      expect(p.health.overdueMilestones, 1);
      expect(p.health.openMilestones, 3);
      expect(p.health.nextMilestone?.name, 'sooner');
    });
  });

  group('decision system', () {
    test('open, past need-by, oldest, latency, decided-last-30, log age',
        () {
      final p = computeProgrammePulse(
        ProgrammePulseInputs(
          programme: programme(),
          decisions: [
            decision('d-open-old', created: DateTime(2026, 8, 1)),
            decision('d-open-late',
                dueDate: '2026-10-20', created: DateTime(2026, 10, 1)),
            decision('d-open-ok',
                dueDate: '2026-11-20', created: DateTime(2026, 10, 1)),
            // Made: 10 days latency, within 30 days.
            decision('d-made-1',
                status: 'decided',
                created: DateTime(2026, 10, 10),
                decidedAt: '2026-10-20',
                updated: DateTime(2026, 10, 20)),
            // Made: 30 days latency, 60 days ago (in the 90-day window,
            // not the 30-day one).
            decision('d-made-2',
                status: 'approved',
                created: DateTime(2026, 8, 1),
                decidedAt: '2026-08-31',
                updated: DateTime(2026, 8, 31)),
            // Made 200 days ago: outside every window.
            decision('d-made-old',
                status: 'decided',
                created: DateTime(2026, 1, 1),
                decidedAt: '2026-04-13',
                updated: DateTime(2026, 4, 13)),
          ],
        ),
        now: now,
      );
      expect(p.decisions.open, 3);
      expect(p.decisions.pastNeedBy, 1);
      expect(p.decisions.oldestOpenDays, 90);
      expect(p.decisions.medianLatencyDays, 20); // median of {10, 30}
      expect(p.decisions.decidedLast30, 1);
      expect(p.decisions.logLastUpdated, '2026-10-20');
      expect(p.completeness.hasDecisionNeedBy, isTrue);
    });

    test('no decisions made in 90 days → null latency, not zero', () {
      final p = computeProgrammePulse(
        ProgrammePulseInputs(
            programme: programme(), decisions: [decision('d')]),
        now: now,
      );
      expect(p.decisions.medianLatencyDays, isNull);
    });
  });

  group('raid', () {
    test('counts live risks, high band, escalated; closed and accepted are '
        'out; top risks ranked by score', () {
      final p = computeProgrammePulse(
        ProgrammePulseInputs(
          programme: programme(),
          risks: [
            risk('r-low', likelihood: 'unlikely', impact: 'minor'),
            risk('r-high', escalated: now),
            risk('r-closed', status: 'closed'),
            risk('r-accepted', status: 'accepted'),
          ],
        ),
        now: now,
      );
      expect(p.raid.openRisks, 2);
      expect(p.raid.highOpen, 1);
      expect(p.raid.escalatedOpen, 1);
      expect(p.raid.topRisks.map((r) => r.title), ['r-high', 'r-low']);
      expect(p.raid.topRisks.first.escalated, isTrue);
    });
  });

  group('flow', () {
    test('person load groups cascaded copies by name across sources', () {
      final p = computeProgrammePulse(
        ProgrammePulseInputs(
          programme: programme(),
          persons: [
            person('p-native', 'Ada Lovelace'),
            person('cascade:person:proj-1:p1', 'Ada Lovelace'),
            person('cascade:person:proj-2:p1', 'ada lovelace'),
            person('cascade:person:proj-1:p2', 'Bob'),
          ],
          teamRoles: [
            role('t1', 'p-native'),
            role('t2', 'cascade:person:proj-1:p1', src: 'proj-1'),
            role('t3', 'cascade:person:proj-2:p1', src: 'proj-2'),
            role('t4', 'cascade:person:proj-1:p2', src: 'proj-1'),
            role('t5', 'cascade:person:proj-1:p2', src: 'proj-1'), // same
          ],
        ),
        now: now,
      );
      expect(p.flow.maxProjectsPerPerson, 3);
      expect(p.flow.peopleOn3PlusProjects, 1);
      expect(p.flow.topLoaded.first.name, 'Ada Lovelace');
      expect(p.flow.topLoaded.first.projects, 3);
      expect(p.flow.topLoaded[1].projects, 1);
      expect(p.completeness.hasTeamRoles, isTrue);
    });

    test('project counts are null without local project rows (remote '
        'links), present with them', () {
      final link = ProgrammeLink(
        id: 'l',
        ownerEntityId: 'prog',
        ownerKind: 'programme',
        partnerKind: 'project',
        code: 'KL-AAAA-AAAA-AAAA',
        status: 'active',
        generatedHere: true,
        shareLevel: 'escalated',
        createdAt: t0,
      );
      final remote = computeProgrammePulse(
        ProgrammePulseInputs(programme: programme(), projectLinks: [link]),
        now: now,
      );
      expect(remote.flow.projectsLinked, 1);
      expect(remote.flow.projectsActive, isNull);
      expect(remote.flow.startsThisQuarter, isNull);

      final local = computeProgrammePulse(
        ProgrammePulseInputs(
          programme: programme(),
          projectLinks: [link],
          linkedProjects: [
            Project(
                id: 'p1',
                name: 'P1',
                status: 'active',
                kind: 'project',
                startDate: '2026-10-05',
                createdAt: t0,
                updatedAt: t0),
            Project(
                id: 'p2',
                name: 'P2',
                status: 'closed',
                kind: 'project',
                startDate: '2026-02-01',
                createdAt: t0,
                updatedAt: t0),
          ],
        ),
        now: now,
      );
      expect(local.flow.projectsActive, 1);
      expect(local.flow.startsThisQuarter, 1);
      expect(local.flow.finishesThisQuarter, isNull, reason: 'v1.5');
    });
  });

  group('completeness and round-trip', () {
    test('score is the share of populated inputs', () {
      final bare = computeProgrammePulse(
          ProgrammePulseInputs(programme: programme()),
          now: now);
      expect(bare.completeness.score, 0);
      expect(bare.finance, isNull);

      final some = computeProgrammePulse(
        ProgrammePulseInputs(
          programme: programme(),
          reports: [report('green', DateTime(2026, 10, 24))],
          activities: [milestone('m', '2026-11-01')],
          decisions: [decision('d', dueDate: '2026-11-01')],
        ),
        now: now,
      );
      expect(some.completeness.score, 50); // 3 of 6
    });

    test('toJson → fromJson preserves every field the overview reads', () {
      final p = computeProgrammePulse(
        ProgrammePulseInputs(
          programme: programme(),
          workPackages: [wp('a', 'amber')],
          reports: [report('green', DateTime(2026, 10, 24))],
          activities: [milestone('m', '2026-11-01')],
          decisions: [decision('d', dueDate: '2026-10-01')],
          risks: [risk('r')],
        ),
        now: now,
      );
      final back = ProgrammePulse.fromJson(p.toJson());
      expect(back.version, kPulseSchemaVersion);
      expect(back.programmeId, 'prog');
      expect(back.weekOf, '2026-10-26');
      expect(back.capturedAt.toUtc(), now.toUtc());
      expect(back.health.computedRag, 'amber');
      expect(back.health.reportedRag, 'green');
      expect(back.health.watermelon, isTrue);
      expect(back.health.nextMilestone?.name, 'm');
      expect(back.decisions.pastNeedBy, 1);
      expect(back.raid.openRisks, 1);
      expect(back.raid.topRisks.single.title, 'r');
      expect(back.completeness.score, p.completeness.score);
      expect(back.finance, isNull);
    });

    test('fromJson tolerates an empty / newer payload', () {
      final p = ProgrammePulse.fromJson(const {'v': 99, 'future': 1});
      expect(p.version, 99);
      expect(p.health.computedRag, 'not_started');
      expect(p.raid.topRisks, isEmpty);
      expect(p.completeness.score, 0);
    });
  });
}
