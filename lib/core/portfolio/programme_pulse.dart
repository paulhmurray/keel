/// The programme pulse: one computed, self-describing payload a programme
/// pushes up to its portfolio each week.
///
/// This payload IS the portfolio's minimum data standard. Every number on
/// the portfolio overview comes from here, so every programme reports the
/// same things the same way — by construction, not by policy. Health falls
/// out of the data (computed RAG beside the self-reported one), decisions
/// are measured as a system (latency, age past need-by, log staleness),
/// and flow is modelled (active projects, starts, person load).
///
/// Pure: drift rows in, [ProgrammePulse] out. No database, no `dart:io`,
/// so it runs identically in the desktop app, the unit tests and the web
/// viewer. The builder that gathers the rows lives in
/// `programme_pulse_builder.dart`.
library;

import '../database/database.dart';
import '../finance/programme_rollup.dart';
import '../raid/raid_conversion_service.dart' show RaidKind;
import '../raid/raid_lifecycle.dart';
import '../raid/risk_rating.dart';
import '../status/risk_ranking.dart';
import '../status/status_calculator.dart';

/// Payload schema version. Bump when a reader could misinterpret older
/// payloads; readers skip fields they don't know.
const int kPulseSchemaVersion = 1;

/// Milestone-like activity types that count as dated commitments.
const Set<String> kMilestoneTypes = {'milestone', 'gate', 'hard_deadline'};

/// Cascade item id for a programme's pulse in a given week. One item per
/// programme per ISO week keeps the channel bounded: the week's pulse is
/// upserted in place, and history accrues one row a week.
String pulseItemId(String programmeId, DateTime when) =>
    'pulse:$programmeId:${weekMondayIso(when)}';

/// ISO date (yyyy-mm-dd) of the Monday of [when]'s week.
String weekMondayIso(DateTime when) {
  final d = DateTime(when.year, when.month, when.day);
  final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
  return isoDate(monday);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// ── Inputs ──────────────────────────────────────────────────────────────────

/// Everything the pulse is computed from. All lists are the programme's
/// rows INCLUDING cascaded copies (sourceProjectId set) — the pulse speaks
/// for the whole programme, not just its native rows.
class ProgrammePulseInputs {
  final Project programme;
  final List<TimelineWorkPackage> workPackages;
  final List<TimelineActivity> activities;
  final List<StatusReport> reports;
  final List<Risk> risks;
  final List<Issue> issues;
  final List<ProgramDependency> dependencies;
  final List<Decision> decisions;
  final List<ProjectAction> actions;
  final List<TeamRole> teamRoles;
  final List<Person> persons;
  /// The programme's DOWNWARD links (partnerKind project), active only.
  final List<ProgrammeLink> projectLinks;
  /// Local rows for linked projects where present (same-machine). Remote
  /// projects have no row here; counts fall back to the link list.
  final List<Project> linkedProjects;
  /// Cross-project finance roll-up, when the programme has any.
  final ProgrammeFinance? finance;

  const ProgrammePulseInputs({
    required this.programme,
    this.workPackages = const [],
    this.activities = const [],
    this.reports = const [],
    this.risks = const [],
    this.issues = const [],
    this.dependencies = const [],
    this.decisions = const [],
    this.actions = const [],
    this.teamRoles = const [],
    this.persons = const [],
    this.projectLinks = const [],
    this.linkedProjects = const [],
    this.finance,
  });
}

// ── Output model ────────────────────────────────────────────────────────────

class PulseMilestone {
  final String name;
  final String date; // ISO
  final String? sourceProjectId;
  const PulseMilestone({required this.name, required this.date, this.sourceProjectId});

  Map<String, dynamic> toJson() => {
        'name': name,
        'date': date,
        if (sourceProjectId != null) 'project': sourceProjectId,
      };
  static PulseMilestone? fromJson(Map<String, dynamic>? m) => m == null
      ? null
      : PulseMilestone(
          name: m['name'] as String? ?? '',
          date: m['date'] as String? ?? '',
          sourceProjectId: m['project'] as String?,
        );
}

class PulseHealth {
  final String? reportedRag; // green | amber | red, from the latest own report
  final String? reportedAt; // ISO date
  final String computedRag; // Rag.value — worst-wins over every WP
  final int overdueMilestones;
  final int openMilestones;
  final PulseMilestone? nextMilestone;
  final Map<String, int> workstreams; // rag value → count

  const PulseHealth({
    required this.reportedRag,
    required this.reportedAt,
    required this.computedRag,
    required this.overdueMilestones,
    required this.openMilestones,
    required this.nextMilestone,
    required this.workstreams,
  });

  /// Reported better than computed: the "watermelon" signal.
  bool get watermelon {
    final r = reportedRag;
    if (r == null) return false;
    return _ragSeverity(r) < _ragSeverity(computedRag);
  }

  Map<String, dynamic> toJson() => {
        'reported_rag': reportedRag,
        'reported_at': reportedAt,
        'computed_rag': computedRag,
        'overdue_milestones': overdueMilestones,
        'open_milestones': openMilestones,
        'next_milestone': nextMilestone?.toJson(),
        'workstreams': workstreams,
      };
  factory PulseHealth.fromJson(Map<String, dynamic> m) => PulseHealth(
        reportedRag: m['reported_rag'] as String?,
        reportedAt: m['reported_at'] as String?,
        computedRag: m['computed_rag'] as String? ?? 'not_started',
        overdueMilestones: _int(m['overdue_milestones']),
        openMilestones: _int(m['open_milestones']),
        nextMilestone: PulseMilestone.fromJson(
            (m['next_milestone'] as Map?)?.cast<String, dynamic>()),
        workstreams: ((m['workstreams'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, _int(v))),
      );
}

class PulseFinance {
  final String? currency;
  final int budgetMinor;
  final int forecastMinor;
  final int actualsMinor;
  final int? varianceBp;
  final int breachingProjects;
  final int projectsWithBudget;

  const PulseFinance({
    required this.currency,
    required this.budgetMinor,
    required this.forecastMinor,
    required this.actualsMinor,
    required this.varianceBp,
    required this.breachingProjects,
    required this.projectsWithBudget,
  });

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'budget_minor': budgetMinor,
        'forecast_minor': forecastMinor,
        'actuals_minor': actualsMinor,
        'variance_bp': varianceBp,
        'breaching_projects': breachingProjects,
        'projects_with_budget': projectsWithBudget,
      };
  factory PulseFinance.fromJson(Map<String, dynamic> m) => PulseFinance(
        currency: m['currency'] as String?,
        budgetMinor: _int(m['budget_minor']),
        forecastMinor: _int(m['forecast_minor']),
        actualsMinor: _int(m['actuals_minor']),
        varianceBp: m['variance_bp'] == null ? null : _int(m['variance_bp']),
        breachingProjects: _int(m['breaching_projects']),
        projectsWithBudget: _int(m['projects_with_budget']),
      );
}

class PulseTopRisk {
  final String title;
  final String likelihood;
  final String impact;
  final int score;
  final bool escalated;
  final String? sourceProjectId;
  const PulseTopRisk({
    required this.title,
    required this.likelihood,
    required this.impact,
    required this.score,
    required this.escalated,
    this.sourceProjectId,
  });
  Map<String, dynamic> toJson() => {
        'title': title,
        'likelihood': likelihood,
        'impact': impact,
        'score': score,
        'escalated': escalated,
        if (sourceProjectId != null) 'project': sourceProjectId,
      };
  factory PulseTopRisk.fromJson(Map<String, dynamic> m) => PulseTopRisk(
        title: m['title'] as String? ?? '',
        likelihood: m['likelihood'] as String? ?? '',
        impact: m['impact'] as String? ?? '',
        score: _int(m['score']),
        escalated: m['escalated'] as bool? ?? false,
        sourceProjectId: m['project'] as String?,
      );
}

class PulseRaid {
  final int openRisks;
  final int openIssues;
  final int escalatedOpen;
  final int highOpen;
  final int overdueReview;
  final int openDependencies;
  final List<PulseTopRisk> topRisks;

  const PulseRaid({
    required this.openRisks,
    required this.openIssues,
    required this.escalatedOpen,
    required this.highOpen,
    required this.overdueReview,
    required this.openDependencies,
    required this.topRisks,
  });

  Map<String, dynamic> toJson() => {
        'open_risks': openRisks,
        'open_issues': openIssues,
        'escalated_open': escalatedOpen,
        'high_open': highOpen,
        'overdue_review': overdueReview,
        'open_dependencies': openDependencies,
        'top_risks': topRisks.map((r) => r.toJson()).toList(),
      };
  factory PulseRaid.fromJson(Map<String, dynamic> m) => PulseRaid(
        openRisks: _int(m['open_risks']),
        openIssues: _int(m['open_issues']),
        escalatedOpen: _int(m['escalated_open']),
        highOpen: _int(m['high_open']),
        overdueReview: _int(m['overdue_review']),
        openDependencies: _int(m['open_dependencies']),
        topRisks: [
          for (final r in (m['top_risks'] as List? ?? const []))
            PulseTopRisk.fromJson((r as Map).cast<String, dynamic>()),
        ],
      );
}

class PulseDecisions {
  final int open;
  final int pastNeedBy;
  final int oldestOpenDays;
  /// Median raised→made latency over decisions made in the last 90 days.
  final int? medianLatencyDays;
  final int decidedLast30;
  final String? logLastUpdated; // ISO date

  const PulseDecisions({
    required this.open,
    required this.pastNeedBy,
    required this.oldestOpenDays,
    required this.medianLatencyDays,
    required this.decidedLast30,
    required this.logLastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'open': open,
        'past_need_by': pastNeedBy,
        'oldest_open_days': oldestOpenDays,
        'median_latency_days': medianLatencyDays,
        'decided_last_30': decidedLast30,
        'log_last_updated': logLastUpdated,
      };
  factory PulseDecisions.fromJson(Map<String, dynamic> m) => PulseDecisions(
        open: _int(m['open']),
        pastNeedBy: _int(m['past_need_by']),
        oldestOpenDays: _int(m['oldest_open_days']),
        medianLatencyDays: m['median_latency_days'] == null
            ? null
            : _int(m['median_latency_days']),
        decidedLast30: _int(m['decided_last_30']),
        logLastUpdated: m['log_last_updated'] as String?,
      );
}

class PulseActions {
  final int open;
  final int overdue;
  const PulseActions({required this.open, required this.overdue});
  Map<String, dynamic> toJson() => {'open': open, 'overdue': overdue};
  factory PulseActions.fromJson(Map<String, dynamic> m) =>
      PulseActions(open: _int(m['open']), overdue: _int(m['overdue']));
}

class PulseLoadedPerson {
  final String name;
  final int projects;
  const PulseLoadedPerson({required this.name, required this.projects});
  Map<String, dynamic> toJson() => {'name': name, 'projects': projects};
  factory PulseLoadedPerson.fromJson(Map<String, dynamic> m) =>
      PulseLoadedPerson(
          name: m['name'] as String? ?? '', projects: _int(m['projects']));
}

class PulseFlow {
  final int projectsLinked;
  final int? projectsActive; // null when no local project rows (remote)
  final int? startsThisQuarter;
  final int? finishesThisQuarter; // v1.5: needs a project close date
  final int completedActivitiesLast90;
  final int peopleOn3PlusProjects;
  final int maxProjectsPerPerson;
  final List<PulseLoadedPerson> topLoaded;

  const PulseFlow({
    required this.projectsLinked,
    required this.projectsActive,
    required this.startsThisQuarter,
    required this.finishesThisQuarter,
    required this.completedActivitiesLast90,
    required this.peopleOn3PlusProjects,
    required this.maxProjectsPerPerson,
    required this.topLoaded,
  });

  Map<String, dynamic> toJson() => {
        'projects_linked': projectsLinked,
        'projects_active': projectsActive,
        'starts_this_quarter': startsThisQuarter,
        'finishes_this_quarter': finishesThisQuarter,
        'completed_activities_last_90': completedActivitiesLast90,
        'people_on_3plus_projects': peopleOn3PlusProjects,
        'max_projects_per_person': maxProjectsPerPerson,
        'top_loaded': topLoaded.map((p) => p.toJson()).toList(),
      };
  factory PulseFlow.fromJson(Map<String, dynamic> m) => PulseFlow(
        projectsLinked: _int(m['projects_linked']),
        projectsActive:
            m['projects_active'] == null ? null : _int(m['projects_active']),
        startsThisQuarter: m['starts_this_quarter'] == null
            ? null
            : _int(m['starts_this_quarter']),
        finishesThisQuarter: m['finishes_this_quarter'] == null
            ? null
            : _int(m['finishes_this_quarter']),
        completedActivitiesLast90: _int(m['completed_activities_last_90']),
        peopleOn3PlusProjects: _int(m['people_on_3plus_projects']),
        maxProjectsPerPerson: _int(m['max_projects_per_person']),
        topLoaded: [
          for (final p in (m['top_loaded'] as List? ?? const []))
            PulseLoadedPerson.fromJson((p as Map).cast<String, dynamic>()),
        ],
      );
}

/// Which inputs the programme actually populates. The portfolio shows
/// this as a maturity ladder: a programme that reports health but has
/// no budget, no dated milestones and no need-by dates on decisions is
/// telling the PMO exactly where its reporting is immature.
class PulseCompleteness {
  final bool hasStatusReport;
  final bool hasBudget;
  final bool hasForecast;
  final bool hasMilestones;
  final bool hasDecisionNeedBy;
  final bool hasTeamRoles;

  const PulseCompleteness({
    required this.hasStatusReport,
    required this.hasBudget,
    required this.hasForecast,
    required this.hasMilestones,
    required this.hasDecisionNeedBy,
    required this.hasTeamRoles,
  });

  List<bool> get _flags => [
        hasStatusReport,
        hasBudget,
        hasForecast,
        hasMilestones,
        hasDecisionNeedBy,
        hasTeamRoles,
      ];

  /// 0–100, equal weight per input.
  int get score =>
      (_flags.where((f) => f).length * 100 / _flags.length).round();

  Map<String, dynamic> toJson() => {
        'score': score,
        'has_status_report': hasStatusReport,
        'has_budget': hasBudget,
        'has_forecast': hasForecast,
        'has_milestones': hasMilestones,
        'has_decision_need_by': hasDecisionNeedBy,
        'has_team_roles': hasTeamRoles,
      };
  factory PulseCompleteness.fromJson(Map<String, dynamic> m) =>
      PulseCompleteness(
        hasStatusReport: m['has_status_report'] as bool? ?? false,
        hasBudget: m['has_budget'] as bool? ?? false,
        hasForecast: m['has_forecast'] as bool? ?? false,
        hasMilestones: m['has_milestones'] as bool? ?? false,
        hasDecisionNeedBy: m['has_decision_need_by'] as bool? ?? false,
        hasTeamRoles: m['has_team_roles'] as bool? ?? false,
      );
}

class ProgrammePulse {
  final int version;
  final String programmeId;
  final String programmeName;
  final DateTime capturedAt;
  final String weekOf; // ISO Monday
  final PulseHealth health;
  final PulseFinance? finance;
  final PulseRaid raid;
  final PulseDecisions decisions;
  final PulseActions actions;
  final PulseFlow flow;
  final PulseCompleteness completeness;

  const ProgrammePulse({
    required this.version,
    required this.programmeId,
    required this.programmeName,
    required this.capturedAt,
    required this.weekOf,
    required this.health,
    required this.finance,
    required this.raid,
    required this.decisions,
    required this.actions,
    required this.flow,
    required this.completeness,
  });

  Map<String, dynamic> toJson() => {
        'v': version,
        'programme_id': programmeId,
        'programme_name': programmeName,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'week_of': weekOf,
        'health': health.toJson(),
        'finance': finance?.toJson(),
        'raid': raid.toJson(),
        'decisions': decisions.toJson(),
        'actions': actions.toJson(),
        'flow': flow.toJson(),
        'completeness': completeness.toJson(),
      };

  /// Lenient reader: a payload from a newer sender still decodes what
  /// this build knows about.
  factory ProgrammePulse.fromJson(Map<String, dynamic> m) {
    Map<String, dynamic> sub(String k) =>
        ((m[k] as Map?) ?? const {}).cast<String, dynamic>();
    final captured = m['captured_at'] as String?;
    return ProgrammePulse(
      version: _int(m['v']),
      programmeId: m['programme_id'] as String? ?? '',
      programmeName: m['programme_name'] as String? ?? '',
      capturedAt: captured == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.parse(captured),
      weekOf: m['week_of'] as String? ?? '',
      health: PulseHealth.fromJson(sub('health')),
      finance: m['finance'] == null ? null : PulseFinance.fromJson(sub('finance')),
      raid: PulseRaid.fromJson(sub('raid')),
      decisions: PulseDecisions.fromJson(sub('decisions')),
      actions: PulseActions.fromJson(sub('actions')),
      flow: PulseFlow.fromJson(sub('flow')),
      completeness: PulseCompleteness.fromJson(sub('completeness')),
    );
  }
}

// ── Computation ─────────────────────────────────────────────────────────────

ProgrammePulse computeProgrammePulse(ProgrammePulseInputs i, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final todayIso = isoDate(today);

  // ── Health ──
  final ownReports = i.reports.where((r) => r.sourceProjectId == null).toList();
  StatusReport? latestReport;
  for (final r in ownReports) {
    final d = r.reportDate ?? r.createdAt;
    final best = latestReport == null
        ? null
        : (latestReport.reportDate ?? latestReport.createdAt);
    if (best == null || d.isAfter(best)) latestReport = r;
  }
  final computedRag = i.workPackages.isEmpty
      ? Rag.notStarted
      : StatusCalculator.computeProgrammeRag(i.workPackages);
  final workstreams = <String, int>{};
  for (final wp in i.workPackages) {
    final v = ragFromString(wp.ragStatus).value;
    workstreams[v] = (workstreams[v] ?? 0) + 1;
  }
  var overdueMilestones = 0;
  var openMilestones = 0;
  PulseMilestone? next;
  for (final a in i.activities) {
    if (!kMilestoneTypes.contains(a.activityType)) continue;
    if (a.status == 'complete') continue;
    openMilestones++;
    final d = a.startDate ?? a.endDate;
    if (d == null || d.isEmpty) continue;
    if (d.compareTo(todayIso) < 0) {
      overdueMilestones++;
    } else if (next == null || d.compareTo(next.date) < 0) {
      next = PulseMilestone(
          name: a.name, date: d, sourceProjectId: a.sourceProjectId);
    }
  }
  final health = PulseHealth(
    reportedRag: latestReport == null
        ? null
        : ragFromString(latestReport.overallRag).value,
    reportedAt: latestReport == null
        ? null
        : isoDate(latestReport.reportDate ?? latestReport.createdAt),
    computedRag: computedRag.value,
    overdueMilestones: overdueMilestones,
    openMilestones: openMilestones,
    nextMilestone: next,
    workstreams: workstreams,
  );

  // ── Finance ──
  final f = i.finance;
  final finance = (f == null || f.projects.isEmpty)
      ? null
      : PulseFinance(
          currency: f.currency,
          budgetMinor: f.budgetMinor,
          forecastMinor: f.forecastMinor,
          actualsMinor: f.actualsMinor,
          varianceBp: f.varianceBp,
          breachingProjects: f.projects.where((p) => p.breach).length,
          projectsWithBudget: f.projects.where((p) => p.budget != null).length,
        );

  // ── RAID ──
  final liveRisks =
      i.risks.where((r) => isActiveStatus(RaidKind.risk, r.status)).toList();
  final liveIssues =
      i.issues.where((x) => isActiveStatus(RaidKind.issue, x.status)).toList();
  final liveDeps = i.dependencies
      .where((d) => isActiveStatus(RaidKind.dependency, d.status))
      .toList();
  final raid = PulseRaid(
    openRisks: liveRisks.length,
    openIssues: liveIssues.length,
    escalatedOpen: liveRisks.where((r) => r.escalatedAt != null).length +
        liveIssues.where((x) => x.escalatedAt != null).length,
    highOpen: liveRisks
        .where((r) => riskBand(r.likelihood, r.impact) == 'high')
        .length,
    overdueReview:
        liveRisks.where((r) => reviewOverdue(r.nextReviewAt, today)).length,
    openDependencies: liveDeps.length,
    topRisks: [
      for (final r in topRisks(i.risks, limit: 5, today: today))
        PulseTopRisk(
          title: (r.title == null || r.title!.isEmpty) ? r.description : r.title!,
          likelihood: r.likelihood,
          impact: r.impact,
          score: riskScore(r.likelihood, r.impact),
          escalated: r.escalatedAt != null,
          sourceProjectId: r.sourceProjectId,
        ),
    ],
  );

  // ── Decisions ──
  final openDecisions = i.decisions
      .where((d) => isActiveStatus(RaidKind.decision, d.status))
      .toList();
  var oldest = 0;
  var pastNeedBy = 0;
  for (final d in openDecisions) {
    final age = daysBetween(d.createdAt, today);
    if (age > oldest) oldest = age;
    final due = d.dueDate;
    if (due != null && due.isNotEmpty && due.compareTo(todayIso) < 0) {
      pastNeedBy++;
    }
  }
  final latencies = <int>[];
  var decidedLast30 = 0;
  for (final d in i.decisions) {
    final raw = d.decidedAt;
    if (raw == null || raw.isEmpty) continue;
    final decided = DateTime.tryParse(raw);
    if (decided == null) continue;
    final since = daysBetween(decided, today);
    if (since < 0) continue;
    if (since <= 30) decidedLast30++;
    if (since <= 90) {
      final l = daysBetween(d.createdAt, decided);
      latencies.add(l < 0 ? 0 : l);
    }
  }
  DateTime? logLast;
  for (final d in i.decisions) {
    if (logLast == null || d.updatedAt.isAfter(logLast)) logLast = d.updatedAt;
  }
  final decisions = PulseDecisions(
    open: openDecisions.length,
    pastNeedBy: pastNeedBy,
    oldestOpenDays: oldest,
    medianLatencyDays: _median(latencies),
    decidedLast30: decidedLast30,
    logLastUpdated: logLast == null ? null : isoDate(logLast),
  );

  // ── Actions ──
  final openActions = i.actions.where((a) => a.status != 'closed').toList();
  final actions = PulseActions(
    open: openActions.length,
    overdue: openActions.where((a) {
      final due = a.dueDate;
      return due != null && due.isNotEmpty && due.compareTo(todayIso) < 0;
    }).length,
  );

  // ── Flow ──
  final quarterStart = DateTime(today.year, ((today.month - 1) ~/ 3) * 3 + 1, 1);
  final quarterStartIso = isoDate(quarterStart);
  final hasLocalProjects = i.linkedProjects.isNotEmpty;
  final completedCutoff = today.subtract(const Duration(days: 90));
  // Person load: distinct sources (project ids, or the programme itself for
  // native roles) per person name. Cascaded persons are copies, so group by
  // normalised name rather than id.
  final nameById = {
    for (final p in i.persons) p.id: p.name.trim().toLowerCase(),
  };
  // First-seen spelling wins for display (native rows come first from the
  // DAO, so the programme's own capitalisation is preferred).
  final displayName = <String, String>{};
  for (final p in i.persons) {
    displayName.putIfAbsent(p.name.trim().toLowerCase(), () => p.name.trim());
  }
  final sourcesByName = <String, Set<String>>{};
  for (final tr in i.teamRoles) {
    final pid = tr.personId;
    if (pid == null) continue;
    final name = nameById[pid];
    if (name == null || name.isEmpty) continue;
    sourcesByName
        .putIfAbsent(name, () => <String>{})
        .add(tr.sourceProjectId ?? i.programme.id);
  }
  final loaded = sourcesByName.entries
      .map((e) => PulseLoadedPerson(
          name: displayName[e.key] ?? e.key, projects: e.value.length))
      .toList()
    ..sort((a, b) {
      final c = b.projects.compareTo(a.projects);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  final flow = PulseFlow(
    projectsLinked: i.projectLinks.where((l) => l.status == 'active').length,
    projectsActive: hasLocalProjects
        ? i.linkedProjects.where((p) => p.status == 'active').length
        : null,
    startsThisQuarter: hasLocalProjects
        ? i.linkedProjects.where((p) {
            final s = p.startDate;
            return s != null &&
                s.isNotEmpty &&
                s.compareTo(quarterStartIso) >= 0 &&
                s.compareTo(todayIso) <= 0;
          }).length
        : null,
    finishesThisQuarter: null,
    completedActivitiesLast90: i.activities
        .where((a) =>
            a.status == 'complete' && a.updatedAt.isAfter(completedCutoff))
        .length,
    peopleOn3PlusProjects: loaded.where((p) => p.projects >= 3).length,
    maxProjectsPerPerson: loaded.isEmpty ? 0 : loaded.first.projects,
    topLoaded: loaded.take(5).toList(),
  );

  // ── Completeness ──
  final completeness = PulseCompleteness(
    hasStatusReport: latestReport != null,
    hasBudget: f != null && f.projects.any((p) => p.budget != null),
    hasForecast: f != null && f.projects.any((p) => p.latestSnapshot != null),
    hasMilestones: i.activities.any((a) =>
        kMilestoneTypes.contains(a.activityType) &&
        ((a.startDate ?? a.endDate) ?? '').isNotEmpty),
    hasDecisionNeedBy: i.decisions.isNotEmpty &&
        i.decisions.any((d) => (d.dueDate ?? '').isNotEmpty),
    hasTeamRoles: i.teamRoles.any((t) => t.personId != null),
  );

  return ProgrammePulse(
    version: kPulseSchemaVersion,
    programmeId: i.programme.id,
    programmeName: i.programme.name,
    capturedAt: today,
    weekOf: weekMondayIso(today),
    health: health,
    finance: finance,
    raid: raid,
    decisions: decisions,
    actions: actions,
    flow: flow,
    completeness: completeness,
  );
}

// ── Helpers ─────────────────────────────────────────────────────────────────

int _int(Object? v) => v is int ? v : (v is num ? v.round() : 0);

/// Whole calendar days from [a] to [b], immune to DST (a 23-hour day is
/// still one day). Negative when [b] is before [a].
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

int? _median(List<int> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : ((s[mid - 1] + s[mid]) / 2).round();
}

/// 0 = green … 3 = red; not_started sits with green so "no data" never
/// reads as a watermelon on its own.
int _ragSeverity(String rag) => switch (rag) {
      'red' => 3,
      'amber' => 2,
      _ => 0,
    };
