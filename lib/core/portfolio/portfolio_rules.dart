/// Health by rules, not opinion.
///
/// Each dimension of a programme's health is a colour that falls out of its
/// pulse under a declared threshold. The thresholds are named constants so
/// the overview can print them beside the heatmap: a PMO must be able to
/// see WHY a cell is red, or the roll-up is just another opinion.
///
/// Pure: pulse in, colour + reason out. No database, no `dart:io`.
library;

import 'programme_pulse.dart';

enum HealthDimension { schedule, finance, raid, decisions }

extension HealthDimensionLabel on HealthDimension {
  String get label => switch (this) {
        HealthDimension.schedule => 'Schedule',
        HealthDimension.finance => 'Finance',
        HealthDimension.raid => 'RAID',
        HealthDimension.decisions => 'Decisions',
      };
}

/// One dimension's verdict: a RAG value plus the sentence that justifies it.
class RuleVerdict {
  final String rag; // green | amber | red | not_started
  final String reason;
  const RuleVerdict(this.rag, this.reason);
}

class PortfolioRules {
  PortfolioRules._();

  // Schedule — overdue dated milestones (gates / hard deadlines included).
  static const scheduleAmberOverdue = 1;
  static const scheduleRedOverdue = 3;

  // Finance — forecast vs approved budget. A project breaching its OWN
  // tolerance is red regardless of the programme total; otherwise the
  // programme-level variance is judged against this band.
  static const financeAmberBp = 250; // ±2.5 %

  // RAID — high-band open risks and escalations.
  static const raidAmberHigh = 1;
  static const raidRedHigh = 3;
  static const raidRedEscalated = 2;

  // Decisions — past need-by and a quiet log.
  static const decisionsAmberPastNeedBy = 1;
  static const decisionsRedPastNeedBy = 2;
  static const decisionsStaleDays = 21;

  static RuleVerdict judge(ProgrammePulse p, HealthDimension d, {DateTime? now}) =>
      switch (d) {
        HealthDimension.schedule => _schedule(p),
        HealthDimension.finance => _finance(p),
        HealthDimension.raid => _raid(p),
        HealthDimension.decisions => _decisions(p, now ?? DateTime.now()),
      };

  /// Worst-wins across the four rule dimensions. `not_started` dimensions
  /// (no data) don't count against the programme.
  static String overall(ProgrammePulse p, {DateTime? now}) {
    var worst = 0;
    for (final d in HealthDimension.values) {
      final s = ragSeverity(judge(p, d, now: now).rag);
      if (s > worst) worst = s;
    }
    return _fromSeverity(worst);
  }

  static RuleVerdict _schedule(ProgrammePulse p) {
    final h = p.health;
    if (h.openMilestones == 0 && h.overdueMilestones == 0) {
      return const RuleVerdict('not_started', 'No dated milestones');
    }
    final n = h.overdueMilestones;
    if (n >= scheduleRedOverdue) {
      return RuleVerdict('red', '$n milestones overdue (red at $scheduleRedOverdue)');
    }
    if (n >= scheduleAmberOverdue) {
      return RuleVerdict('amber', '$n overdue (amber at $scheduleAmberOverdue, red at $scheduleRedOverdue)');
    }
    return RuleVerdict('green', 'No overdue milestones · ${h.openMilestones} open');
  }

  static RuleVerdict _finance(ProgrammePulse p) {
    final f = p.finance;
    if (f == null || f.projectsWithBudget == 0) {
      return const RuleVerdict('not_started', 'No approved budget cascaded');
    }
    if (f.breachingProjects > 0) {
      return RuleVerdict('red',
          '${f.breachingProjects} project${f.breachingProjects == 1 ? '' : 's'} outside its own tolerance');
    }
    final v = f.varianceBp;
    if (v == null) {
      return const RuleVerdict('amber', 'Budget approved but no submitted forecast');
    }
    if (v.abs() > financeAmberBp) {
      return RuleVerdict('amber', 'Forecast ${_pct(v)} vs budget (amber beyond ±${_pct(financeAmberBp)})');
    }
    return RuleVerdict('green', 'Forecast ${_pct(v)} vs budget, within band');
  }

  static RuleVerdict _raid(ProgrammePulse p) {
    final r = p.raid;
    if (r.openRisks == 0 && r.openIssues == 0) {
      return const RuleVerdict('not_started', 'No open risks or issues');
    }
    if (r.highOpen >= raidRedHigh) {
      return RuleVerdict('red', '${r.highOpen} high-band risks open (red at $raidRedHigh)');
    }
    if (r.escalatedOpen >= raidRedEscalated) {
      return RuleVerdict('red', '${r.escalatedOpen} escalations open (red at $raidRedEscalated)');
    }
    if (r.highOpen >= raidAmberHigh || r.escalatedOpen > 0) {
      return RuleVerdict('amber',
          '${r.highOpen} high · ${r.escalatedOpen} escalated (red at $raidRedHigh high or $raidRedEscalated escalated)');
    }
    return RuleVerdict('green', '${r.openRisks} open risks, none high or escalated');
  }

  static RuleVerdict _decisions(ProgrammePulse p, DateTime now) {
    final d = p.decisions;
    if (d.open == 0 && d.logLastUpdated == null) {
      return const RuleVerdict('not_started', 'No decisions logged');
    }
    if (d.pastNeedBy >= decisionsRedPastNeedBy) {
      return RuleVerdict('red', '${d.pastNeedBy} decisions past need-by (red at $decisionsRedPastNeedBy)');
    }
    final staleDays = _staleDays(d.logLastUpdated, now);
    if (d.pastNeedBy >= decisionsAmberPastNeedBy) {
      return RuleVerdict('amber', '${d.pastNeedBy} past need-by (red at $decisionsRedPastNeedBy)');
    }
    if (staleDays != null && staleDays > decisionsStaleDays) {
      return RuleVerdict('amber', 'Decision log quiet for $staleDays days (amber after $decisionsStaleDays)');
    }
    return RuleVerdict('green', '${d.open} open, none past need-by');
  }

  static int? _staleDays(String? iso, DateTime now) {
    if (iso == null) return null;
    final d = DateTime.tryParse(iso);
    if (d == null) return null;
    return daysBetween(d, now);
  }

  static String _pct(int bp) {
    final sign = bp > 0 ? '+' : bp < 0 ? '-' : '';
    final tenths = (bp.abs() * 2 + 10) ~/ 20;
    return '$sign${tenths ~/ 10}.${tenths % 10}%';
  }

  static String _fromSeverity(int s) => switch (s) {
        3 => 'red',
        2 => 'amber',
        1 => 'green',
        _ => 'not_started',
      };
}

/// 0 = no data, 1 = green, 2 = amber, 3 = red. Shared by the heatmap sort
/// and the trend sparkline (which plots severity over weeks).
int ragSeverity(String rag) => switch (rag) {
      'red' => 3,
      'amber' => 2,
      'green' => 1,
      _ => 0,
    };
