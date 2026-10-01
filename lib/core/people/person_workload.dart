/// Everything in a project that is owned by, assigned to, or otherwise
/// pinned on one person.
///
/// Ownership in Keel is split: milestones, workstream activities and
/// plan activities carry a `Persons` FK, while the RAID registers,
/// actions, decisions and workstreams store the owner as free text
/// (filled from the People picker, so it normally matches a Person's
/// name exactly). This module reconciles both: FK match on id, plus a
/// trimmed, case-folded name match on the text fields. Grouping is pure
/// Dart over already-fetched rows so it is unit-tested without a
/// database; [PersonWorkload.load] is the thin DB glue.
library;

import 'dart:convert';

import '../database/database.dart';
import '../raid/raid_conversion_service.dart' show RaidKind;
import '../raid/raid_lifecycle.dart';

/// How the person is attached to an item.
enum WorkloadRole { owner, assignee, decisionMaker, lead, contributor }

extension WorkloadRoleExt on WorkloadRole {
  String get label => switch (this) {
        WorkloadRole.owner => 'Owner',
        WorkloadRole.assignee => 'Assignee',
        WorkloadRole.decisionMaker => 'Decision maker',
        WorkloadRole.lead => 'Lead',
        WorkloadRole.contributor => 'Contributor',
      };
}

/// The register / list an item came from. Order here is the display
/// order on screen and in the PDF.
enum WorkloadKind {
  risk,
  issue,
  assumption,
  dependency,
  action,
  decision,
  milestone,
  planActivity,
  workstream,
  workstreamActivity,
  contribution,
}

extension WorkloadKindExt on WorkloadKind {
  /// Column heading for [WorkloadItem.qualifier] in this section.
  String get qualifierLabel => switch (this) {
        WorkloadKind.risk => 'Rating',
        WorkloadKind.issue || WorkloadKind.action => 'Priority',
        WorkloadKind.dependency => 'Type',
        WorkloadKind.contribution => 'Owner',
        _ => 'Flag',
      };

  String get label => switch (this) {
        WorkloadKind.risk => 'Risks',
        WorkloadKind.issue => 'Issues',
        WorkloadKind.assumption => 'Assumptions',
        WorkloadKind.dependency => 'Dependencies',
        WorkloadKind.action => 'Actions',
        WorkloadKind.decision => 'Decisions',
        WorkloadKind.milestone => 'Milestones',
        WorkloadKind.planActivity => 'Plan activities',
        WorkloadKind.workstream => 'Workstreams',
        WorkloadKind.workstreamActivity => 'Workstream activities',
        WorkloadKind.contribution => 'Contributing to',
      };
}

/// One row of a person's workload, flattened to what a brief needs.
class WorkloadItem {
  final WorkloadKind kind;
  final String id;
  final String? ref;
  final String title;
  final String status;
  final WorkloadRole role;

  /// ISO yyyy-mm-dd, when the source row has a due/target date.
  final String? dueDate;

  /// Terminal status for its register — shown under "Completed".
  final bool isClosed;

  /// Second line: mitigation, impact, notes — whatever the register
  /// treats as the "so what". Free text, may be null.
  final String? detail;

  /// Short qualifier: "Likely / Major", "high priority", "inbound".
  final String? qualifier;

  const WorkloadItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.status,
    required this.role,
    this.ref,
    this.dueDate,
    this.isClosed = false,
    this.detail,
    this.qualifier,
  });

  bool isOverdue(String todayIso) =>
      !isClosed && dueDate != null && dueDate!.compareTo(todayIso) < 0;
}

/// Three-way split the People dialog already uses for actions, applied
/// uniformly to every register.
class WorkloadBuckets {
  final List<WorkloadItem> overdue;
  final List<WorkloadItem> open;
  final List<WorkloadItem> closed;
  const WorkloadBuckets(
      {required this.overdue, required this.open, required this.closed});

  bool get isEmpty => overdue.isEmpty && open.isEmpty && closed.isEmpty;
  int get activeCount => overdue.length + open.length;
}

class PersonWorkload {
  final Person person;
  final Map<WorkloadKind, List<WorkloadItem>> sections;

  const PersonWorkload({required this.person, required this.sections});

  List<WorkloadItem> operator [](WorkloadKind kind) =>
      sections[kind] ?? const [];

  Iterable<WorkloadItem> get all => sections.values.expand((l) => l);
  bool get isEmpty => all.isEmpty;
  int get openCount => all.where((i) => !i.isClosed).length;
  int overdueCount(String todayIso) =>
      all.where((i) => i.isOverdue(todayIso)).length;

  /// Kinds with at least one item, in display order.
  List<WorkloadKind> get populatedKinds =>
      WorkloadKind.values.where((k) => this[k].isNotEmpty).toList();

  WorkloadBuckets buckets(WorkloadKind kind, String todayIso) {
    final items = this[kind];
    return WorkloadBuckets(
      overdue: items.where((i) => i.isOverdue(todayIso)).toList(),
      open: items
          .where((i) => !i.isClosed && !i.isOverdue(todayIso))
          .toList(),
      closed: items.where((i) => i.isClosed).toList(),
    );
  }

  // ─── Matching ────────────────────────────────────────────────────────

  /// Normalises an owner string for comparison: trimmed, case-folded,
  /// internal whitespace collapsed. "  Sam  Patel " == "sam patel".
  static String normaliseName(String? s) =>
      (s ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool nameMatches(Person person, String? candidate) {
    final n = normaliseName(person.name);
    return n.isNotEmpty && normaliseName(candidate) == n;
  }

  static bool idMatches(Person person, String? candidateId) =>
      candidateId != null && candidateId == person.id;

  /// Person ids in a plan activity's `contributorIds` JSON list.
  static List<String> contributorIdsOf(TimelineActivity a) {
    final raw = a.contributorIds;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      // Malformed — treat as none rather than fail the whole brief.
    }
    return const [];
  }

  // ─── Build from rows ─────────────────────────────────────────────────

  static PersonWorkload build({
    required Person person,
    List<Risk> risks = const [],
    List<Issue> issues = const [],
    List<Assumption> assumptions = const [],
    List<ProgramDependency> dependencies = const [],
    List<ProjectAction> actions = const [],
    List<Decision> decisions = const [],
    List<Milestone> milestones = const [],
    List<TimelineActivity> planActivities = const [],
    List<Workstream> workstreams = const [],
    List<WorkstreamActivity> workstreamActivities = const [],
  }) {
    final sections = <WorkloadKind, List<WorkloadItem>>{};
    void add(WorkloadItem item) =>
        (sections[item.kind] ??= <WorkloadItem>[]).add(item);

    for (final r in risks) {
      final WorkloadRole role;
      if (nameMatches(person, r.owner)) {
        role = WorkloadRole.owner;
      } else if (nameMatches(person, r.assignee)) {
        role = WorkloadRole.assignee;
      } else {
        continue;
      }
      add(WorkloadItem(
        kind: WorkloadKind.risk,
        id: r.id,
        ref: r.ref,
        title: _titleOr(r.title, r.description),
        status: r.status,
        role: role,
        dueDate: r.dueDate,
        isClosed: isTerminalStatus(RaidKind.risk, r.status),
        detail: _labelled([('Latest', r.statusNote), ('Mitigation', r.mitigation)]),
        qualifier: '${_cap(r.likelihood)} / ${_cap(r.impact)}',
      ));
    }

    for (final i in issues) {
      if (!nameMatches(person, i.owner)) continue;
      add(WorkloadItem(
        kind: WorkloadKind.issue,
        id: i.id,
        ref: i.ref,
        title: _titleOr(i.title, i.description),
        status: i.status,
        role: WorkloadRole.owner,
        dueDate: i.dueDate,
        isClosed: isTerminalStatus(RaidKind.issue, i.status),
        detail: _labelled([('Impact', i.impactStatement), ('Resolution', i.resolution)]),
        qualifier: '${_cap(i.priority)} priority',
      ));
    }

    for (final a in assumptions) {
      if (!nameMatches(person, a.owner)) continue;
      add(WorkloadItem(
        kind: WorkloadKind.assumption,
        id: a.id,
        ref: a.ref,
        title: a.description,
        status: a.status,
        role: WorkloadRole.owner,
        isClosed: isTerminalStatus(RaidKind.assumption, a.status),
      ));
    }

    for (final d in dependencies) {
      if (!nameMatches(person, d.owner)) continue;
      add(WorkloadItem(
        kind: WorkloadKind.dependency,
        id: d.id,
        ref: d.ref,
        title: d.description,
        status: d.status,
        role: WorkloadRole.owner,
        dueDate: d.dueDate,
        isClosed: isTerminalStatus(RaidKind.dependency, d.status),
        detail: _labelled([('Why', d.rationale), ('Impact', d.impactStatement)]),
        qualifier: [
          _cap(d.dependencyType),
          if ((d.counterparty ?? '').trim().isNotEmpty)
            'with ${d.counterparty!.trim()}',
        ].join(' '),
      ));
    }

    for (final a in actions) {
      if (!nameMatches(person, a.owner)) continue;
      add(WorkloadItem(
        kind: WorkloadKind.action,
        id: a.id,
        ref: a.ref,
        title: a.description,
        status: a.status,
        role: WorkloadRole.owner,
        dueDate: a.dueDate,
        isClosed: a.status == 'closed',
        detail: _labelled([('Outcome', a.outcome)]),
        qualifier: '${_cap(a.priority)} priority',
      ));
    }

    for (final d in decisions) {
      if (!nameMatches(person, d.decisionMaker)) continue;
      add(WorkloadItem(
        kind: WorkloadKind.decision,
        id: d.id,
        ref: d.ref,
        title: d.description,
        status: d.status,
        role: WorkloadRole.decisionMaker,
        dueDate: d.dueDate,
        isClosed: isTerminalStatus(RaidKind.decision, d.status),
        detail: _labelled([('Outcome', d.outcome), ('Impact', d.impactStatement)]),
      ));
    }

    for (final m in milestones) {
      if (!idMatches(person, m.ownerId)) continue;
      add(WorkloadItem(
        kind: WorkloadKind.milestone,
        id: m.id,
        title: m.name,
        status: m.status,
        role: WorkloadRole.owner,
        dueDate: m.date,
        isClosed: _kDoneStatuses.contains(m.status.toLowerCase()),
        detail: _firstNonEmpty([m.notes]),
        qualifier: m.isHardDeadline ? 'Hard deadline' : null,
      ));
    }

    for (final a in planActivities) {
      if (idMatches(person, a.ownerId) || nameMatches(person, a.owner)) {
        add(WorkloadItem(
          kind: WorkloadKind.planActivity,
          id: a.id,
          title: a.name,
          status: a.status,
          role: WorkloadRole.owner,
          dueDate: a.endDate,
          isClosed: _kDoneStatuses.contains(a.status.toLowerCase()),
          detail: _firstNonEmpty([a.notes]),
          qualifier: a.isCritical ? 'Critical path' : null,
        ));
      } else if (contributorIdsOf(a).contains(person.id)) {
        add(WorkloadItem(
          kind: WorkloadKind.contribution,
          id: a.id,
          title: a.name,
          status: a.status,
          role: WorkloadRole.contributor,
          dueDate: a.endDate,
          isClosed: _kDoneStatuses.contains(a.status.toLowerCase()),
          qualifier:
              (a.owner ?? '').trim().isNotEmpty ? a.owner!.trim() : null,
        ));
      }
    }

    for (final w in workstreams) {
      if (!nameMatches(person, w.lead)) continue;
      add(WorkloadItem(
        kind: WorkloadKind.workstream,
        id: w.id,
        title: w.name,
        status: w.status,
        role: WorkloadRole.lead,
        dueDate: w.endDate,
        isClosed: _kDoneStatuses.contains(w.status.toLowerCase()),
        detail: _firstNonEmpty([w.notes]),
      ));
    }

    for (final a in workstreamActivities) {
      if (!idMatches(person, a.ownerId)) continue;
      add(WorkloadItem(
        kind: WorkloadKind.workstreamActivity,
        id: a.id,
        title: a.name,
        status: a.status,
        role: WorkloadRole.owner,
        dueDate: a.endDate,
        isClosed: _kDoneStatuses.contains(a.status.toLowerCase()),
        detail: _firstNonEmpty([a.notes]),
      ));
    }

    // Within each section: overdue/open first by due date, closed last.
    for (final list in sections.values) {
      list.sort((x, y) {
        if (x.isClosed != y.isClosed) return x.isClosed ? 1 : -1;
        final xd = x.dueDate ?? '9999';
        final yd = y.dueDate ?? '9999';
        return xd.compareTo(yd);
      });
    }

    return PersonWorkload(person: person, sections: sections);
  }

  /// Fetches every register for the person's project and groups it.
  static Future<PersonWorkload> load(AppDatabase db, Person person) async {
    final pid = person.projectId;
    final results = await Future.wait<Object>([
      db.raidDao.getRisksForProject(pid),
      db.raidDao.getIssuesForProject(pid),
      db.raidDao.getAssumptionsForProject(pid),
      db.raidDao.getDependenciesForProject(pid),
      db.actionsDao.getActionsForProject(pid),
      db.decisionsDao.getDecisionsForProject(pid),
      db.milestonesDao.getForProject(pid),
      db.programmeGanttDao.getActivitiesForProject(pid),
      db.workstreamsDao.getForProject(pid),
      db.workstreamActivitiesDao.getForProject(pid),
    ]);
    return build(
      person: person,
      risks: results[0] as List<Risk>,
      issues: results[1] as List<Issue>,
      assumptions: results[2] as List<Assumption>,
      dependencies: results[3] as List<ProgramDependency>,
      actions: results[4] as List<ProjectAction>,
      decisions: results[5] as List<Decision>,
      milestones: results[6] as List<Milestone>,
      planActivities: results[7] as List<TimelineActivity>,
      workstreams: results[8] as List<Workstream>,
      workstreamActivities: results[9] as List<WorkstreamActivity>,
    );
  }
}

/// Statuses that mean "done" for plan, milestone and workstream rows,
/// which have no lifecycle module of their own.
const Set<String> _kDoneStatuses = {
  'complete',
  'completed',
  'done',
  'achieved',
};

String _titleOr(String? title, String description) =>
    (title ?? '').trim().isNotEmpty ? title!.trim() : description;

/// First non-empty candidate, prefixed with its label so the reader
/// knows what the second line is ("Mitigation: weekly checkpoint").
String? _labelled(List<(String, String?)> candidates) {
  for (final (label, value) in candidates) {
    if (value != null && value.trim().isNotEmpty) {
      return '$label: ${value.trim()}';
    }
  }
  return null;
}

String? _firstNonEmpty(List<String?> candidates) {
  for (final c in candidates) {
    if (c != null && c.trim().isNotEmpty) return c.trim();
  }
  return null;
}

String _cap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}'.replaceAll('_', ' ');
