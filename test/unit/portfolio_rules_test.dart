import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/portfolio/portfolio_rollup.dart';
import 'package:keel/core/portfolio/portfolio_rules.dart';
import 'package:keel/core/portfolio/programme_pulse.dart';

/// Health by rules: each dimension's colour falls out of the pulse under a
/// declared threshold, and the cross-programme roll-ups never sum what
/// they shouldn't.
void main() {
  final now = DateTime(2026, 10, 30);

  ProgrammePulse pulse({
    String id = 'prog',
    String name = 'Prog',
    int overdue = 0,
    int open = 2,
    PulseFinance? finance,
    int highOpen = 0,
    int escalated = 0,
    int openRisks = 1,
    int pastNeedBy = 0,
    int openDecisions = 1,
    String? logLast = '2026-10-28',
    List<PulseTopRisk> topRisks = const [],
    List<PulseLoadedPerson> loaded = const [],
    int completeness = 50,
  }) =>
      ProgrammePulse.fromJson({
        'v': 1,
        'programme_id': id,
        'programme_name': name,
        'captured_at': now.toIso8601String(),
        'week_of': '2026-10-26',
        'health': {
          'computed_rag': 'amber',
          'overdue_milestones': overdue,
          'open_milestones': open,
        },
        'finance': finance?.toJson(),
        'raid': {
          'open_risks': openRisks,
          'high_open': highOpen,
          'escalated_open': escalated,
          'top_risks': topRisks.map((r) => r.toJson()).toList(),
        },
        'decisions': {
          'open': openDecisions,
          'past_need_by': pastNeedBy,
          'log_last_updated': logLast,
        },
        'flow': {'top_loaded': loaded.map((p) => p.toJson()).toList()},
        'completeness': {'has_status_report': completeness > 0},
      });

  PulseFinance fin({int variance = 0, int breaching = 0, String currency = 'GBP',
          int budget = 1000, int withBudget = 1}) =>
      PulseFinance(
        currency: currency,
        budgetMinor: budget,
        forecastMinor: budget + budget * variance ~/ 10000,
        actualsMinor: 0,
        varianceBp: variance,
        breachingProjects: breaching,
        projectsWithBudget: withBudget,
      );

  group('schedule', () {
    test('boundaries', () {
      String r(int n, {int open = 2}) =>
          PortfolioRules.judge(pulse(overdue: n, open: open), HealthDimension.schedule).rag;
      expect(r(0, open: 0), 'not_started');
      expect(r(0), 'green');
      expect(r(PortfolioRules.scheduleAmberOverdue), 'amber');
      expect(r(PortfolioRules.scheduleRedOverdue - 1), 'amber');
      expect(r(PortfolioRules.scheduleRedOverdue), 'red');
    });
  });

  group('finance', () {
    String r(PulseFinance? f) =>
        PortfolioRules.judge(pulse(finance: f), HealthDimension.finance).rag;
    test('no budget → no data; breach → red regardless of total', () {
      expect(r(null), 'not_started');
      expect(r(fin(withBudget: 0)), 'not_started');
      expect(r(fin(variance: 0, breaching: 1)), 'red');
    });
    test('band', () {
      expect(r(fin(variance: PortfolioRules.financeAmberBp)), 'green');
      expect(r(fin(variance: PortfolioRules.financeAmberBp + 1)), 'amber');
      expect(r(fin(variance: -(PortfolioRules.financeAmberBp + 1))), 'amber');
    });
    test('budget without a forecast is amber, and the reason says so', () {
      final f = PulseFinance(
          currency: 'GBP', budgetMinor: 100, forecastMinor: 100, actualsMinor: 0,
          varianceBp: null, breachingProjects: 0, projectsWithBudget: 1);
      final v = PortfolioRules.judge(pulse(finance: f), HealthDimension.finance);
      expect(v.rag, 'amber');
      expect(v.reason, contains('no submitted forecast'));
    });
  });

  group('raid', () {
    String r({int high = 0, int esc = 0, int open = 1}) =>
        PortfolioRules.judge(pulse(highOpen: high, escalated: esc, openRisks: open),
            HealthDimension.raid).rag;
    test('boundaries', () {
      expect(r(open: 0), 'not_started');
      expect(r(), 'green');
      expect(r(high: PortfolioRules.raidAmberHigh), 'amber');
      expect(r(esc: 1), 'amber');
      expect(r(esc: PortfolioRules.raidRedEscalated), 'red');
      expect(r(high: PortfolioRules.raidRedHigh), 'red');
    });
  });

  group('decisions', () {
    String r({int past = 0, String? log = '2026-10-28', int open = 1}) =>
        PortfolioRules.judge(pulse(pastNeedBy: past, logLast: log, openDecisions: open),
            HealthDimension.decisions, now: now).rag;
    test('boundaries and staleness', () {
      expect(r(open: 0, log: null), 'not_started');
      expect(r(), 'green');
      expect(r(past: PortfolioRules.decisionsAmberPastNeedBy), 'amber');
      expect(r(past: PortfolioRules.decisionsRedPastNeedBy), 'red');
      expect(r(log: '2026-10-09'), 'green', reason: 'exactly 21 days is not stale');
      expect(r(log: '2026-10-08'), 'amber', reason: '22 days is');
    });
  });

  test('overall is worst-wins and ignores no-data dimensions', () {
    expect(PortfolioRules.overall(pulse(open: 0, openRisks: 0, openDecisions: 0, logLast: null), now: now),
        'not_started');
    expect(PortfolioRules.overall(pulse(), now: now), 'green');
    expect(PortfolioRules.overall(pulse(overdue: 1), now: now), 'amber');
    expect(PortfolioRules.overall(pulse(overdue: 1, pastNeedBy: 3), now: now), 'red');
  });

  group('roll-up', () {
    test('finance sums the majority currency and names the excluded', () {
      final t = rollupPortfolioFinance([
        pulse(id: 'a', name: 'A', finance: fin(budget: 1000, variance: 1000)),
        pulse(id: 'b', name: 'B', finance: fin(budget: 3000, variance: 0, breaching: 1)),
        pulse(id: 'c', name: 'C', finance: fin(budget: 500, currency: 'AUD')),
        pulse(id: 'd', name: 'D'),
      ])!;
      expect(t.currency, 'GBP');
      expect(t.programmesIncluded, 2);
      expect(t.excludedProgrammes, ['C']);
      expect(t.budgetMinor, 4000);
      expect(t.forecastMinor, 4100);
      expect(t.varianceBp, 250);
      expect(t.breachingProjects, 1);
      expect(rollupPortfolioFinance([pulse()]), isNull);
    });

    test('basisPoints rounds half away from zero', () {
      expect(basisPoints(1, 3), 3333);
      expect(basisPoints(-1, 3), -3333);
      expect(basisPoints(5, 10000 * 2), 3); // 2.5 → 3
      expect(basisPoints(-5, 10000 * 2), -3);
    });

    test('top risks merge across programmes, score then escalated', () {
      PulseTopRisk r(String t, int score, {bool esc = false}) => PulseTopRisk(
          title: t, likelihood: 'l', impact: 'i', score: score, escalated: esc);
      final top = portfolioTopRisks([
        pulse(id: 'a', name: 'A', topRisks: [r('a1', 16), r('a2', 9)]),
        pulse(id: 'b', name: 'B', topRisks: [r('b1', 16, esc: true), r('b2', 20)]),
      ], limit: 3);
      expect(top.map((x) => x.risk.title), ['b2', 'b1', 'a1']);
      expect(top.first.programmeName, 'B');
    });

    test('load merges people by name across programmes', () {
      final load = portfolioLoad([
        pulse(id: 'a', loaded: [const PulseLoadedPerson(name: 'Marcus Webb', projects: 3)]),
        pulse(id: 'b', loaded: [
          const PulseLoadedPerson(name: 'marcus webb', projects: 2),
          const PulseLoadedPerson(name: 'Ada', projects: 1),
        ]),
      ]);
      expect(load.first.name, 'Marcus Webb');
      expect(load.first.projects, 5);
      expect(load.first.programmes, 2);
      expect(load[1].name, 'Ada');
    });

    test('averageCompleteness', () {
      expect(averageCompleteness([]), 0);
      // The helper only sets one of six flags, so "100" scores 17; the mean
      // of 0 and 17 is 8.5, which rounds half away from zero.
      expect(averageCompleteness([pulse(completeness: 0), pulse(completeness: 100)]), 9);
    });
  });
}
