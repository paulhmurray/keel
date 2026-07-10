import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Item kinds for cascade payloads. Server is agnostic — these are
/// just stable strings the sender and receiver agree on.
class CascadeKinds {
  CascadeKinds._();
  static const workPackage = 'work_package';
  // RAID escalation kinds (Phase C.2). One per RAID table.
  static const risk = 'risk';
  static const assumption = 'assumption';
  static const issue = 'issue';
  static const dependency = 'dependency';
  // Status report (Phase C.3). Auto-cascade on save.
  static const statusReport = 'status_report';
  // Charter (Phase C.4). One per project; auto-cascade on save.
  static const charter = 'charter';
  // Person (Phase C.5). Auto-cascade on save; tombstone on delete.
  static const person = 'person';
  // Actions + Decisions (Phase C.6). Same explicit-escalation pattern
  // as RAID: PM toggles a flag per item; auto-pushes thereafter.
  static const action = 'action';
  static const decision = 'decision';
  // People-overview coverage matrices — auto-cascade so a programme can
  // render each project's full People overview (roles + coverage).
  static const stakeholderRole = 'stakeholder_role';
  static const teamRole = 'team_role';
}

/// Abstract gateway the CascadeService talks to. Mirrors the
/// [RemoteLinksGateway] pattern — kept here so the service can be
/// tested with a stub instead of an http client.
abstract class CascadeGateway {
  /// Push one item to the link channel.
  Future<void> push({
    required String code,
    required String sourceEntityId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  });

  /// Pull the channel since [since] (or everything if null). Returns
  /// the items + a fresh cursor for the next call.
  Future<CascadePullSnapshot> pull({
    required String code,
    String? since,
  });

  /// Soft-delete an item on the channel.
  Future<void> delete({
    required String code,
    required String itemKind,
    required String itemId,
  });
}

/// Receive-side snapshot from [CascadeGateway.pull]. Decoupled from
/// the SyncClient's CascadeItem so the database layer doesn't depend
/// on the http client.
class CascadePullSnapshot {
  final List<CascadeRecord> items;
  final String cursor;

  const CascadePullSnapshot({required this.items, required this.cursor});
}

class CascadeRecord {
  final String sourceEntityId;
  final String itemKind;
  final String itemId;
  final Map<String, dynamic> payload;
  final bool deleted;

  const CascadeRecord({
    required this.sourceEntityId,
    required this.itemKind,
    required this.itemId,
    required this.payload,
    required this.deleted,
  });
}

/// Coordinates cascade pushes from a project's outgoing data to the
/// programme channel, and pulls from the programme's incoming
/// channels into local rows. Phase C.1 supports work packages only;
/// future slices add escalated RAID items, status reports, charter,
/// and people-overview kinds.
class CascadeService {
  final AppDatabase db;
  final CascadeGateway? gateway;

  CascadeService(this.db, {required this.gateway});

  bool get isReady => gateway != null;

  // ── Outgoing (project → programme) ──────────────────────────────────────

  /// Pushes one work package to every active link that this project
  /// is part of. Called whenever a WP is created or edited on a
  /// project-kind row. Silently no-ops when:
  ///   - the row is itself a cascaded WP (no double-forwarding),
  ///   - the gateway isn't available (offline / not logged in),
  ///   - there are no active links on the project.
  ///
  /// Failures are swallowed: cascade is best-effort, the canonical
  /// data lives on the source machine. A later push or pull picks
  /// up missed deltas.
  Future<void> pushWorkPackage(TimelineWorkPackage wp) async {
    if (gateway == null) return;
    if (wp.sourceProjectId != null) return; // never re-cascade
    final links = await _activeLinksForEntity(wp.projectId);
    if (links.isEmpty) return;
    final payload = _workPackagePayload(wp)
      ..addAll(await _workPackageSpanPayload(wp));
    for (final link in links) {
      try {
        await gateway!.push(
          code: link.code,
          sourceEntityId: wp.projectId,
          itemKind: CascadeKinds.workPackage,
          itemId: wp.id,
          payload: payload,
        );
      } catch (_) {
        // Best-effort — next save / refresh will retry.
      }
    }
  }

  /// Pushes every WP on the project. Used right after a link
  /// activates so the programme manager sees the existing portfolio
  /// without waiting for edits.
  Future<void> pushAllWorkPackages(String projectId) async {
    if (gateway == null) return;
    final wps = await db.programmeGanttDao.getWorkPackages(projectId);
    for (final wp in wps) {
      await pushWorkPackage(wp);
    }
  }

  /// Tombstones a deleted WP across every active link. Called from
  /// the same UI flow that runs `programmeGanttDao.deleteWorkPackage`.
  Future<void> deleteWorkPackage({
    required String projectId,
    required String workPackageId,
  }) async {
    if (gateway == null) return;
    final links = await _activeLinksForEntity(projectId);
    for (final link in links) {
      try {
        await gateway!.delete(
          code: link.code,
          itemKind: CascadeKinds.workPackage,
          itemId: workPackageId,
        );
      } catch (_) {
        // Same swallow-and-retry posture as push.
      }
    }
  }

  // ── Incoming (programme ← projects) ─────────────────────────────────────

  // ── RAID escalation (Phase C.2) ─────────────────────────────────────────
  //
  // Same shape as the WP cascade but item-specific: payloads carry the
  // canonical RAID fields (no rationales / source notes — just enough
  // for the programme manager to triage). Push happens on escalate AND
  // on every subsequent save while the row is escalated. Unescalating
  // a row tombstones it on the channel.

  Future<void> pushRisk(Risk risk) async {
    if (!_canPush(risk.escalatedAt, risk.sourceProjectId)) return;
    await _pushToAllLinks(
      projectId: risk.projectId,
      itemKind: CascadeKinds.risk,
      itemId: risk.id,
      payload: _riskPayload(risk),
    );
  }

  Future<void> pushAssumption(Assumption a) async {
    if (!_canPush(a.escalatedAt, a.sourceProjectId)) return;
    await _pushToAllLinks(
      projectId: a.projectId,
      itemKind: CascadeKinds.assumption,
      itemId: a.id,
      payload: _assumptionPayload(a),
    );
  }

  Future<void> pushIssue(Issue i) async {
    if (!_canPush(i.escalatedAt, i.sourceProjectId)) return;
    await _pushToAllLinks(
      projectId: i.projectId,
      itemKind: CascadeKinds.issue,
      itemId: i.id,
      payload: _issuePayload(i),
    );
  }

  Future<void> pushDependency(ProgramDependency d) async {
    if (!_canPush(d.escalatedAt, d.sourceProjectId)) return;
    await _pushToAllLinks(
      projectId: d.projectId,
      itemKind: CascadeKinds.dependency,
      itemId: d.id,
      payload: _dependencyPayload(d),
    );
  }

  /// Tombstones an item that the PM has unescalated. Called BEFORE
  /// the DAO clears escalatedAt — we still want the (kind, id) to be
  /// dropped on the programme side even though the local row's
  /// escalation flag is going away.
  Future<void> tombstoneRaidItem({
    required String projectId,
    required String itemKind,
    required String itemId,
  }) async {
    if (gateway == null) return;
    final links = await _activeLinksForEntity(projectId);
    for (final link in links) {
      try {
        await gateway!.delete(
          code: link.code,
          itemKind: itemKind,
          itemId: itemId,
        );
      } catch (_) {
        // Best-effort.
      }
    }
  }

  // ── Status reports (Phase C.3) ──────────────────────────────────────────
  //
  // Status reports cascade automatically on save. The act of saving a
  // status report is the publish moment — there's no separate "share
  // with programme" toggle. Cascaded rows on the programme side carry
  // the source attribution and are read-only.

  Future<void> pushStatusReport(StatusReport report) async {
    if (report.sourceProjectId != null) return; // never re-cascade
    await _pushToAllLinks(
      projectId: report.projectId,
      itemKind: CascadeKinds.statusReport,
      itemId: report.id,
      payload: _statusReportPayload(report),
    );
  }

  /// Tombstone the cascaded copies of a status report on every active
  /// link. Mirrors [deleteWorkPackage].
  Future<void> deleteStatusReport({
    required String projectId,
    required String reportId,
  }) async {
    if (gateway == null) return;
    final links = await _activeLinksForEntity(projectId);
    for (final link in links) {
      try {
        await gateway!.delete(
          code: link.code,
          itemKind: CascadeKinds.statusReport,
          itemId: reportId,
        );
      } catch (_) {
        // Best-effort.
      }
    }
  }

  /// Pushes every status report on the project. Called at link
  /// activation time so the programme manager sees the historical
  /// report timeline without waiting for the next save.
  Future<void> pushAllStatusReports(String projectId) async {
    if (gateway == null) return;
    final reports =
        await db.reportsDao.getReportsForProject(projectId);
    for (final r in reports) {
      await pushStatusReport(r);
    }
  }

  // ── Charter (Phase C.4) ────────────────────────────────────────────────
  //
  // Charters are single-row-per-project. Auto-cascade on save. The
  // payload carries every editable field; a cached source project
  // name rides along so the programme-side card can label attribution
  // without a cross-machine join.

  Future<void> pushCharter(
    ProjectCharter charter, {
    required String sourceProjectName,
  }) async {
    if (charter.sourceProjectId != null) return; // never re-cascade
    await _pushToAllLinks(
      projectId: charter.projectId,
      itemKind: CascadeKinds.charter,
      itemId: charter.id,
      payload: _charterPayload(charter, sourceProjectName),
    );
  }

  Future<void> deleteCharter({
    required String projectId,
    required String charterId,
  }) async {
    if (gateway == null) return;
    final links = await _activeLinksForEntity(projectId);
    for (final link in links) {
      try {
        await gateway!.delete(
          code: link.code,
          itemKind: CascadeKinds.charter,
          itemId: charterId,
        );
      } catch (_) {
        // Best-effort.
      }
    }
  }

  /// Pushes the project's charter (if any). Used at link activation
  /// so the programme manager immediately sees the charter without
  /// waiting for the next save.
  Future<void> pushCurrentCharter({
    required String projectId,
    required String projectName,
  }) async {
    if (gateway == null) return;
    final charter = await db.projectCharterDao.getForProject(projectId);
    if (charter == null) return;
    await pushCharter(charter, sourceProjectName: projectName);
  }

  // ── People (Phase C.5) ─────────────────────────────────────────────────
  //
  // People auto-cascade on save. Programme-side rows sit alongside
  // any native programme people and carry the source project name
  // for attribution. Pickers on the programme can suggest cascaded
  // people as risk owners etc. without the programme manager having
  // to recreate the person locally.

  Future<void> pushPerson(
    Person person, {
    required String sourceProjectName,
  }) async {
    if (person.sourceProjectId != null) return; // never re-cascade
    // Embed the person's stakeholder + colleague profiles so the
    // programme can render a real influence/interest map, stance
    // colours, and team grouping across all projects. Profiles are 1:1
    // with a person, so they ride along rather than being their own kind.
    final stakeholder =
        await db.peopleDao.getStakeholderByPersonId(person.id);
    final colleague = await db.peopleDao.getColleagueByPersonId(person.id);
    await _pushToAllLinks(
      projectId: person.projectId,
      itemKind: CascadeKinds.person,
      itemId: person.id,
      payload: _personPayload(person, sourceProjectName,
          stakeholder: stakeholder, colleague: colleague),
    );
  }

  Future<void> deletePerson({
    required String projectId,
    required String personId,
  }) async {
    if (gateway == null) return;
    final links = await _activeLinksForEntity(projectId);
    for (final link in links) {
      try {
        await gateway!.delete(
          code: link.code,
          itemKind: CascadeKinds.person,
          itemId: personId,
        );
      } catch (_) {
        // Best-effort.
      }
    }
  }

  /// Replays every native person on the project. Used at link
  /// activation so the programme manager immediately sees the team
  /// without waiting for individual save events.
  Future<void> pushAllPeople({
    required String projectId,
    required String projectName,
  }) async {
    if (gateway == null) return;
    final people = await db.peopleDao.getPersonsForProject(projectId);
    for (final p in people) {
      if (p.sourceProjectId != null) continue; // skip cascaded
      await pushPerson(p, sourceProjectName: projectName);
    }
  }

  // ── People-overview coverage matrices ──────────────────────────────────
  //
  // Stakeholder-role + team-role slots (the project's People "Overview"
  // tab) auto-cascade so the programme can render each project's full
  // overview. A role's assigned personId is remapped to the cascaded
  // person's synthetic id on apply so assignments resolve on the
  // programme side.

  Future<void> pushStakeholderRole(StakeholderRole role) async {
    if (role.sourceProjectId != null) return; // never re-cascade
    await _pushToAllLinks(
      projectId: role.projectId,
      itemKind: CascadeKinds.stakeholderRole,
      itemId: role.id,
      payload: _stakeholderRolePayload(role),
    );
  }

  Future<void> pushTeamRole(TeamRole role) async {
    if (role.sourceProjectId != null) return; // never re-cascade
    await _pushToAllLinks(
      projectId: role.projectId,
      itemKind: CascadeKinds.teamRole,
      itemId: role.id,
      payload: _teamRolePayload(role),
    );
  }

  Future<void> pushAllRoles(String projectId) async {
    if (gateway == null) return;
    final sRoles = await db.stakeholderRoleDao.getForProject(projectId);
    for (final r in sRoles) {
      if (r.sourceProjectId != null) continue;
      await pushStakeholderRole(r);
    }
    final tRoles = await db.teamRoleDao.getForProject(projectId);
    for (final r in tRoles) {
      if (r.sourceProjectId != null) continue;
      await pushTeamRole(r);
    }
  }

  Future<void> deleteStakeholderRole({
    required String projectId,
    required String roleId,
  }) =>
      _tombstone(projectId, CascadeKinds.stakeholderRole, roleId);

  Future<void> deleteTeamRole({
    required String projectId,
    required String roleId,
  }) =>
      _tombstone(projectId, CascadeKinds.teamRole, roleId);

  Future<void> _tombstone(
      String projectId, String itemKind, String itemId) async {
    if (gateway == null) return;
    final links = await _activeLinksForEntity(projectId);
    for (final link in links) {
      try {
        await gateway!
            .delete(code: link.code, itemKind: itemKind, itemId: itemId);
      } catch (_) {
        // Best-effort.
      }
    }
  }

  // ── Actions + Decisions escalation (Phase C.6) ─────────────────────────
  //
  // Same explicit-escalation pattern as RAID: PM marks individual
  // items with escalatedAt, the service pushes them on save and
  // tombstones on unescalate-or-delete. Programme-side rows render
  // read-only.

  Future<void> pushAction(ProjectAction a) async {
    if (!_canPush(a.escalatedAt, a.sourceProjectId)) return;
    await _pushToAllLinks(
      projectId: a.projectId,
      itemKind: CascadeKinds.action,
      itemId: a.id,
      payload: _actionPayload(a),
    );
  }

  Future<void> pushDecision(Decision d) async {
    if (!_canPush(d.escalatedAt, d.sourceProjectId)) return;
    await _pushToAllLinks(
      projectId: d.projectId,
      itemKind: CascadeKinds.decision,
      itemId: d.id,
      payload: _decisionPayload(d),
    );
  }

  /// Replays every escalated Action + Decision so a freshly-linked
  /// programme sees the existing escalated portfolio. Symmetrical
  /// with [pushAllEscalatedRaid].
  Future<void> pushAllEscalatedDelivery(String projectId) async {
    if (gateway == null) return;
    final actions =
        await db.actionsDao.getEscalatedActionsForProject(projectId);
    for (final a in actions) {
      await pushAction(a);
    }
    final decisions = await db.decisionsDao
        .getEscalatedDecisionsForProject(projectId);
    for (final d in decisions) {
      await pushDecision(d);
    }
  }

  /// Replays every currently-escalated RAID item on the project so a
  /// newly-activated link sees the existing escalated portfolio. Used
  /// the same way as [pushAllWorkPackages].
  Future<void> pushAllEscalatedRaid(String projectId) async {
    if (gateway == null) return;
    final risks = await db.raidDao.getEscalatedRisksForProject(projectId);
    for (final r in risks) {
      await pushRisk(r);
    }
    final assumptions =
        await db.raidDao.getEscalatedAssumptionsForProject(projectId);
    for (final a in assumptions) {
      await pushAssumption(a);
    }
    final issues =
        await db.raidDao.getEscalatedIssuesForProject(projectId);
    for (final i in issues) {
      await pushIssue(i);
    }
    final deps =
        await db.raidDao.getEscalatedDependenciesForProject(projectId);
    for (final d in deps) {
      await pushDependency(d);
    }
  }

  // ── Incoming (programme ← projects) ─────────────────────────────────────

  /// Pulls every active link for [programmeId] and reconciles
  /// incoming items into the local DB. Dispatches on `itemKind` so
  /// new kinds plug in without touching the outer loop.
  ///
  /// Returns the number of cascaded items applied — useful for the UI
  /// to surface a "n items synced" toast.
  Future<int> pullForProgramme(String programmeId) async {
    if (gateway == null) return 0;
    final links = await _activeLinksForEntity(programmeId);
    var applied = 0;
    for (final link in links) {
      try {
        // Phase C.1 doesn't persist the cursor yet — we re-fetch the
        // whole channel each call. Cheap for typical programme sizes
        // and avoids cursor-corruption corner cases. A future slice
        // adds per-link cursors when payload volumes grow.
        final snap = await gateway!.pull(code: link.code);
        for (final rec in snap.items) {
          switch (rec.itemKind) {
            case CascadeKinds.workPackage:
              await _applyWorkPackage(programmeId, rec);
              applied++;
            case CascadeKinds.risk:
              await _applyRisk(programmeId, rec);
              applied++;
            case CascadeKinds.assumption:
              await _applyAssumption(programmeId, rec);
              applied++;
            case CascadeKinds.issue:
              await _applyIssue(programmeId, rec);
              applied++;
            case CascadeKinds.dependency:
              await _applyDependency(programmeId, rec);
              applied++;
            case CascadeKinds.statusReport:
              await _applyStatusReport(programmeId, rec);
              applied++;
            case CascadeKinds.charter:
              await _applyCharter(programmeId, rec);
              applied++;
            case CascadeKinds.person:
              await _applyPerson(programmeId, rec);
              applied++;
            case CascadeKinds.action:
              await _applyAction(programmeId, rec);
              applied++;
            case CascadeKinds.decision:
              await _applyDecision(programmeId, rec);
              applied++;
            case CascadeKinds.stakeholderRole:
              await _applyStakeholderRole(programmeId, rec);
              applied++;
            case CascadeKinds.teamRole:
              await _applyTeamRole(programmeId, rec);
              applied++;
            default:
              // Unknown kinds — silently skip so a server that's
              // ahead of the client doesn't crash anything.
              break;
          }
        }
      } catch (_) {
        // Continue with the next link.
      }
    }
    return applied;
  }

  // ── Internals ───────────────────────────────────────────────────────────

  Future<List<ProgrammeLink>> _activeLinksForEntity(String id) async {
    final all = await db.programmeLinksDao.getLinksForEntity(id);
    return all.where((l) => l.status == 'active').toList();
  }

  Map<String, dynamic> _workPackagePayload(TimelineWorkPackage wp) {
    return {
      'name': wp.name,
      if (wp.shortCode != null) 'short_code': wp.shortCode,
      if (wp.description != null) 'description': wp.description,
      'colour_theme': wp.colourTheme,
      'sort_order': wp.sortOrder,
      'rag_status': wp.ragStatus,
    };
  }

  /// Computes the WP's overall span from its activities so the programme
  /// can draw a swimlane bar. Only HEADERS cascade — the activities
  /// themselves stay private — so this derived span is the programme's
  /// only signal of when the WP runs.
  ///
  /// Carries the span TWO ways:
  ///   - `start_month` / `end_month`: the raw month indices. Always sent
  ///     when the WP has dated activities. The programme uses these to
  ///     place the bar when no calendar anchor exists (relative axis).
  ///   - `start_date` / `end_date`: absolute dates, sent ONLY when the
  ///     source project has a month-0 anchor. Preferred on render because
  ///     they survive differing anchors between project and programme.
  ///
  /// Returns an empty map only when the WP has no dated activities — the
  /// programme then shows the header with no bar.
  Future<Map<String, dynamic>> _workPackageSpanPayload(
      TimelineWorkPackage wp) async {
    final acts = await db.programmeGanttDao.getActivitiesForWP(wp.id);
    int? minStart;
    int? maxEnd;
    for (final a in acts) {
      final s = a.startMonth;
      if (s == null) continue;
      final end = a.endMonth ?? s;
      minStart = (minStart == null || s < minStart) ? s : minStart;
      maxEnd = (maxEnd == null || end > maxEnd) ? end : maxEnd;
    }
    if (minStart == null || maxEnd == null) return const {};
    final payload = <String, dynamic>{
      'start_month': minStart,
      'end_month': maxEnd,
    };
    // Add absolute dates when the project anchors its timeline.
    final header = await db.programmeGanttDao.getHeader(wp.projectId);
    final anchorIso = header?.month0Date;
    if (anchorIso != null) {
      try {
        final anchor = DateTime.parse(anchorIso);
        payload['start_date'] =
            DateTime(anchor.year, anchor.month + minStart, 1)
                .toIso8601String();
        payload['end_date'] =
            DateTime(anchor.year, anchor.month + maxEnd, 1).toIso8601String();
      } catch (_) {
        // Bad anchor — fall back to month indices only.
      }
    }
    return payload;
  }

  /// True when the PM has flagged this row for cascade AND it's not
  /// itself a cascaded row arriving from upstream (prevents re-cascade
  /// loops on a programme that's also linked elsewhere).
  bool _canPush(DateTime? escalatedAt, String? sourceProjectId) {
    return escalatedAt != null && sourceProjectId == null;
  }

  /// Pushes [payload] for ([itemKind], [itemId]) to every active link
  /// the source project is part of. Failures are swallowed per the
  /// best-effort posture documented on the WP path.
  Future<void> _pushToAllLinks({
    required String projectId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  }) async {
    if (gateway == null) return;
    final links = await _activeLinksForEntity(projectId);
    for (final link in links) {
      try {
        await gateway!.push(
          code: link.code,
          sourceEntityId: projectId,
          itemKind: itemKind,
          itemId: itemId,
          payload: payload,
        );
      } catch (_) {
        // Best-effort — next save / refresh will retry.
      }
    }
  }

  Map<String, dynamic> _riskPayload(Risk r) => {
        if (r.ref != null) 'ref': r.ref,
        'description': r.description,
        'likelihood': r.likelihood,
        'impact': r.impact,
        'status': r.status,
        if (r.owner != null) 'owner': r.owner,
        if (r.mitigation != null) 'mitigation': r.mitigation,
      };

  Map<String, dynamic> _assumptionPayload(Assumption a) => {
        if (a.ref != null) 'ref': a.ref,
        'description': a.description,
        'status': a.status,
        if (a.owner != null) 'owner': a.owner,
      };

  Map<String, dynamic> _issuePayload(Issue i) => {
        if (i.ref != null) 'ref': i.ref,
        'description': i.description,
        'priority': i.priority,
        'status': i.status,
        if (i.owner != null) 'owner': i.owner,
        if (i.dueDate != null) 'due_date': i.dueDate,
        if (i.resolution != null) 'resolution': i.resolution,
      };

  Map<String, dynamic> _dependencyPayload(ProgramDependency d) => {
        if (d.ref != null) 'ref': d.ref,
        'description': d.description,
        'dependency_type': d.dependencyType,
        'status': d.status,
        if (d.owner != null) 'owner': d.owner,
        if (d.dueDate != null) 'due_date': d.dueDate,
      };

  Map<String, dynamic> _actionPayload(ProjectAction a) => {
        if (a.ref != null) 'ref': a.ref,
        'description': a.description,
        if (a.owner != null) 'owner': a.owner,
        if (a.dueDate != null) 'due_date': a.dueDate,
        'status': a.status,
        'priority': a.priority,
        if (a.outcome != null) 'outcome': a.outcome,
      };

  Map<String, dynamic> _decisionPayload(Decision d) => {
        if (d.ref != null) 'ref': d.ref,
        'description': d.description,
        'status': d.status,
        if (d.decisionMaker != null) 'decision_maker': d.decisionMaker,
        if (d.dueDate != null) 'due_date': d.dueDate,
        if (d.rationale != null) 'rationale': d.rationale,
        if (d.outcome != null) 'outcome': d.outcome,
      };

  Map<String, dynamic> _personPayload(
    Person p,
    String sourceProjectName, {
    StakeholderProfile? stakeholder,
    ColleagueProfile? colleague,
  }) =>
      {
        'source_project_name': sourceProjectName,
        'name': p.name,
        if (p.email != null) 'email': p.email,
        if (p.role != null) 'role': p.role,
        if (p.organisation != null) 'organisation': p.organisation,
        if (p.phone != null) 'phone': p.phone,
        if (p.teamsHandle != null) 'teams_handle': p.teamsHandle,
        'person_type': p.personType,
        'is_stakeholder': p.isStakeholder,
        // Embedded stakeholder profile (influence/interest/stance) — lets
        // the programme plot the portfolio-wide stakeholder map.
        if (stakeholder != null)
          'stakeholder_profile': {
            if (stakeholder.influence != null)
              'influence': stakeholder.influence,
            if (stakeholder.interest != null)
              'interest': stakeholder.interest,
            if (stakeholder.stance != null) 'stance': stakeholder.stance,
            if (stakeholder.engagementStrategy != null)
              'engagement_strategy': stakeholder.engagementStrategy,
          },
        // Embedded colleague profile (team) — lets the programme group by
        // team within a project.
        if (colleague != null)
          'colleague_profile': {
            if (colleague.team != null) 'team': colleague.team,
            'direct_report': colleague.directReport,
          },
      };

  Map<String, dynamic> _stakeholderRolePayload(StakeholderRole r) => {
        'role_name': r.roleName,
        'role_type': r.roleType,
        if (r.personId != null) 'person_id': r.personId,
        'is_scaffold': r.isScaffold,
        'is_applicable': r.isApplicable,
        'sort_order': r.sortOrder,
        if (r.notes != null) 'notes': r.notes,
        if (r.functionalArea != null) 'functional_area': r.functionalArea,
        if (r.integrationRelevance != null)
          'integration_relevance': r.integrationRelevance,
        if (r.priority != null) 'priority': r.priority,
        if (r.engagementStatus != null)
          'engagement_status': r.engagementStatus,
        'gap_flag': r.gapFlag,
        if (r.gapDescription != null) 'gap_description': r.gapDescription,
      };

  Map<String, dynamic> _teamRolePayload(TeamRole r) => {
        'role_name': r.roleName,
        'team_group': r.teamGroup,
        if (r.personId != null) 'person_id': r.personId,
        'is_scaffold': r.isScaffold,
        'is_applicable': r.isApplicable,
        'sort_order': r.sortOrder,
        if (r.notes != null) 'notes': r.notes,
      };

  Map<String, dynamic> _charterPayload(
          ProjectCharter c, String sourceProjectName) =>
      {
        'source_project_name': sourceProjectName,
        if (c.vision != null) 'vision': c.vision,
        if (c.objectives != null) 'objectives': c.objectives,
        if (c.scopeIn != null) 'scope_in': c.scopeIn,
        if (c.scopeOut != null) 'scope_out': c.scopeOut,
        if (c.deliveryApproach != null)
          'delivery_approach': c.deliveryApproach,
        if (c.successCriteria != null)
          'success_criteria': c.successCriteria,
        if (c.keyConstraints != null) 'key_constraints': c.keyConstraints,
        if (c.assumptions != null) 'assumptions': c.assumptions,
      };

  Map<String, dynamic> _statusReportPayload(StatusReport r) => {
        'title': r.title,
        if (r.period != null) 'period': r.period,
        'overall_rag': r.overallRag,
        if (r.summary != null) 'summary': r.summary,
        if (r.accomplishments != null) 'accomplishments': r.accomplishments,
        if (r.nextSteps != null) 'next_steps': r.nextSteps,
        if (r.risksHighlighted != null)
          'risks_highlighted': r.risksHighlighted,
        if (r.content != null) 'content': r.content,
        if (r.reportDate != null)
          'report_date': r.reportDate!.toIso8601String(),
      };

  Future<void> _applyWorkPackage(
      String programmeId, CascadeRecord rec) async {
    // The cascade row uses a synthetic id of "<sourceProjectId>:<itemId>"
    // so two projects with colliding WP ids can both cascade up safely.
    final localId = 'cascade:${rec.sourceEntityId}:${rec.itemId}';
    if (rec.deleted) {
      await (db.delete(db.timelineWorkPackages)
            ..where((t) => t.id.equals(localId)))
          .go();
      return;
    }
    final payload = rec.payload;
    await db.programmeGanttDao.upsertWorkPackage(
      TimelineWorkPackagesCompanion.insert(
        id: localId,
        projectId: programmeId,
        name: (payload['name'] as String?) ?? '(unnamed)',
        shortCode: Value(payload['short_code'] as String?),
        description: Value(payload['description'] as String?),
        colourTheme:
            Value(payload['colour_theme'] as String? ?? 'wp1'),
        sortOrder: Value(payload['sort_order'] as int? ?? 0),
        ragStatus:
            Value(payload['rag_status'] as String? ?? 'not_started'),
        sourceProjectId: Value(rec.sourceEntityId),
        cascadeStartDate: Value(payload['start_date'] as String?),
        cascadeEndDate: Value(payload['end_date'] as String?),
        cascadeStartMonth: Value(payload['start_month'] as int?),
        cascadeEndMonth: Value(payload['end_month'] as int?),
      ),
    );
  }

  /// Synthetic id for cascaded RAID rows. Matches the WP pattern so
  /// two projects with colliding refs (R1, R2…) don't collide on the
  /// programme side.
  String _raidId(String kind, CascadeRecord rec) =>
      'cascade:$kind:${rec.sourceEntityId}:${rec.itemId}';

  Future<void> _applyRisk(String programmeId, CascadeRecord rec) async {
    final id = _raidId(CascadeKinds.risk, rec);
    if (rec.deleted) {
      await (db.delete(db.risks)..where((t) => t.id.equals(id))).go();
      return;
    }
    final p = rec.payload;
    await db.raidDao.upsertRisk(RisksCompanion.insert(
      id: id,
      projectId: programmeId,
      ref: Value(p['ref'] as String?),
      description: p['description'] as String? ?? '',
      likelihood: Value(p['likelihood'] as String? ?? 'medium'),
      impact: Value(p['impact'] as String? ?? 'medium'),
      status: Value(p['status'] as String? ?? 'open'),
      owner: Value(p['owner'] as String?),
      mitigation: Value(p['mitigation'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(DateTime.now()),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _applyAssumption(
      String programmeId, CascadeRecord rec) async {
    final id = _raidId(CascadeKinds.assumption, rec);
    if (rec.deleted) {
      await (db.delete(db.assumptions)..where((t) => t.id.equals(id))).go();
      return;
    }
    final p = rec.payload;
    await db.raidDao.upsertAssumption(AssumptionsCompanion.insert(
      id: id,
      projectId: programmeId,
      ref: Value(p['ref'] as String?),
      description: p['description'] as String? ?? '',
      status: Value(p['status'] as String? ?? 'open'),
      owner: Value(p['owner'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(DateTime.now()),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _applyIssue(String programmeId, CascadeRecord rec) async {
    final id = _raidId(CascadeKinds.issue, rec);
    if (rec.deleted) {
      await (db.delete(db.issues)..where((t) => t.id.equals(id))).go();
      return;
    }
    final p = rec.payload;
    await db.raidDao.upsertIssue(IssuesCompanion.insert(
      id: id,
      projectId: programmeId,
      ref: Value(p['ref'] as String?),
      description: p['description'] as String? ?? '',
      priority: Value(p['priority'] as String? ?? 'medium'),
      status: Value(p['status'] as String? ?? 'open'),
      owner: Value(p['owner'] as String?),
      dueDate: Value(p['due_date'] as String?),
      resolution: Value(p['resolution'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(DateTime.now()),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _applyDependency(
      String programmeId, CascadeRecord rec) async {
    final id = _raidId(CascadeKinds.dependency, rec);
    if (rec.deleted) {
      await (db.delete(db.programDependencies)
            ..where((t) => t.id.equals(id)))
          .go();
      return;
    }
    final p = rec.payload;
    await db.raidDao
        .upsertDependency(ProgramDependenciesCompanion.insert(
      id: id,
      projectId: programmeId,
      ref: Value(p['ref'] as String?),
      description: p['description'] as String? ?? '',
      dependencyType: Value(p['dependency_type'] as String? ?? 'inbound'),
      status: Value(p['status'] as String? ?? 'open'),
      owner: Value(p['owner'] as String?),
      dueDate: Value(p['due_date'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(DateTime.now()),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _applyAction(
      String programmeId, CascadeRecord rec) async {
    final id =
        'cascade:${CascadeKinds.action}:${rec.sourceEntityId}:${rec.itemId}';
    if (rec.deleted) {
      await (db.delete(db.projectActions)
            ..where((t) => t.id.equals(id)))
          .go();
      return;
    }
    final p = rec.payload;
    await db.actionsDao.upsertAction(ProjectActionsCompanion.insert(
      id: id,
      projectId: programmeId,
      ref: Value(p['ref'] as String?),
      description: p['description'] as String? ?? '',
      owner: Value(p['owner'] as String?),
      dueDate: Value(p['due_date'] as String?),
      status: Value(p['status'] as String? ?? 'open'),
      priority: Value(p['priority'] as String? ?? 'medium'),
      source: const Value('cascade'),
      outcome: Value(p['outcome'] as String?),
      escalatedAt: Value(DateTime.now()),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _applyDecision(
      String programmeId, CascadeRecord rec) async {
    final id =
        'cascade:${CascadeKinds.decision}:${rec.sourceEntityId}:${rec.itemId}';
    if (rec.deleted) {
      await (db.delete(db.decisions)..where((t) => t.id.equals(id)))
          .go();
      return;
    }
    final p = rec.payload;
    await db.decisionsDao.upsertDecision(DecisionsCompanion.insert(
      id: id,
      projectId: programmeId,
      ref: Value(p['ref'] as String?),
      description: p['description'] as String? ?? '',
      status: Value(p['status'] as String? ?? 'pending'),
      decisionMaker: Value(p['decision_maker'] as String?),
      dueDate: Value(p['due_date'] as String?),
      rationale: Value(p['rationale'] as String?),
      outcome: Value(p['outcome'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(DateTime.now()),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _applyPerson(
      String programmeId, CascadeRecord rec) async {
    final id =
        'cascade:${CascadeKinds.person}:${rec.sourceEntityId}:${rec.itemId}';
    // Deterministic profile ids derived from the person id so re-pulls
    // upsert rather than duplicate.
    final stakeholderId = '$id:stakeholder';
    final colleagueId = '$id:colleague';
    if (rec.deleted) {
      await (db.delete(db.stakeholderProfiles)
            ..where((t) => t.personId.equals(id)))
          .go();
      await (db.delete(db.colleagueProfiles)
            ..where((t) => t.personId.equals(id)))
          .go();
      await (db.delete(db.persons)..where((t) => t.id.equals(id))).go();
      return;
    }
    final p = rec.payload;
    await db.peopleDao.upsertPerson(PersonsCompanion.insert(
      id: id,
      projectId: programmeId,
      name: p['name'] as String? ?? '(unnamed)',
      email: Value(p['email'] as String?),
      role: Value(p['role'] as String?),
      organisation: Value(p['organisation'] as String?),
      phone: Value(p['phone'] as String?),
      teamsHandle: Value(p['teams_handle'] as String?),
      personType: Value(p['person_type'] as String? ?? 'colleague'),
      isStakeholder: Value(p['is_stakeholder'] as bool? ?? false),
      sourceProjectId: Value(rec.sourceEntityId),
      sourceProjectName: Value(p['source_project_name'] as String?),
      updatedAt: Value(DateTime.now()),
    ));

    // Embedded profiles. Upsert when present; clear a stale one that was
    // removed on the source (so the programme reflects a deleted profile).
    final sp = p['stakeholder_profile'] as Map?;
    if (sp != null) {
      await db.peopleDao.upsertStakeholder(StakeholderProfilesCompanion.insert(
        id: stakeholderId,
        projectId: programmeId,
        personId: id,
        influence: Value(sp['influence'] as String?),
        interest: Value(sp['interest'] as String?),
        stance: Value(sp['stance'] as String?),
        engagementStrategy: Value(sp['engagement_strategy'] as String?),
        sourceProjectId: Value(rec.sourceEntityId),
        updatedAt: Value(DateTime.now()),
      ));
    } else {
      await (db.delete(db.stakeholderProfiles)
            ..where((t) => t.personId.equals(id)))
          .go();
    }

    final cp = p['colleague_profile'] as Map?;
    if (cp != null) {
      await db.peopleDao.upsertColleague(ColleagueProfilesCompanion.insert(
        id: colleagueId,
        projectId: programmeId,
        personId: id,
        team: Value(cp['team'] as String?),
        directReport: Value(cp['direct_report'] as bool? ?? false),
        sourceProjectId: Value(rec.sourceEntityId),
        updatedAt: Value(DateTime.now()),
      ));
    } else {
      await (db.delete(db.colleagueProfiles)
            ..where((t) => t.personId.equals(id)))
          .go();
    }
  }

  /// Remaps a role's source-side personId to the cascaded person's
  /// synthetic id so assignments resolve against programme-side people.
  String? _remapPersonId(CascadeRecord rec, String? sourcePersonId) {
    if (sourcePersonId == null) return null;
    return 'cascade:${CascadeKinds.person}:${rec.sourceEntityId}:$sourcePersonId';
  }

  Future<void> _applyStakeholderRole(
      String programmeId, CascadeRecord rec) async {
    final id =
        'cascade:${CascadeKinds.stakeholderRole}:${rec.sourceEntityId}:${rec.itemId}';
    if (rec.deleted) {
      await (db.delete(db.stakeholderRoles)..where((t) => t.id.equals(id)))
          .go();
      return;
    }
    final p = rec.payload;
    await db.stakeholderRoleDao.upsert(StakeholderRolesCompanion.insert(
      id: id,
      projectId: programmeId,
      roleName: p['role_name'] as String? ?? '(role)',
      roleType: p['role_type'] as String? ?? 'active',
      personId: Value(_remapPersonId(rec, p['person_id'] as String?)),
      isScaffold: Value(p['is_scaffold'] as bool? ?? true),
      isApplicable: Value(p['is_applicable'] as bool? ?? true),
      sortOrder: Value(p['sort_order'] as int? ?? 0),
      notes: Value(p['notes'] as String?),
      functionalArea: Value(p['functional_area'] as String?),
      integrationRelevance: Value(p['integration_relevance'] as String?),
      priority: Value(p['priority'] as String?),
      engagementStatus: Value(p['engagement_status'] as String?),
      gapFlag: Value(p['gap_flag'] as bool? ?? false),
      gapDescription: Value(p['gap_description'] as String?),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _applyTeamRole(
      String programmeId, CascadeRecord rec) async {
    final id =
        'cascade:${CascadeKinds.teamRole}:${rec.sourceEntityId}:${rec.itemId}';
    if (rec.deleted) {
      await (db.delete(db.teamRoles)..where((t) => t.id.equals(id))).go();
      return;
    }
    final p = rec.payload;
    await db.teamRoleDao.upsert(TeamRolesCompanion.insert(
      id: id,
      projectId: programmeId,
      roleName: p['role_name'] as String? ?? '(role)',
      teamGroup: p['team_group'] as String? ?? 'specialist',
      personId: Value(_remapPersonId(rec, p['person_id'] as String?)),
      isScaffold: Value(p['is_scaffold'] as bool? ?? true),
      isApplicable: Value(p['is_applicable'] as bool? ?? true),
      sortOrder: Value(p['sort_order'] as int? ?? 0),
      notes: Value(p['notes'] as String?),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _applyCharter(
      String programmeId, CascadeRecord rec) async {
    final id =
        'cascade:${CascadeKinds.charter}:${rec.sourceEntityId}:${rec.itemId}';
    if (rec.deleted) {
      await (db.delete(db.projectCharters)
            ..where((t) => t.id.equals(id)))
          .go();
      return;
    }
    final p = rec.payload;
    await db.projectCharterDao.upsert(ProjectChartersCompanion.insert(
      id: id,
      projectId: programmeId,
      vision: Value(p['vision'] as String?),
      objectives: Value(p['objectives'] as String?),
      scopeIn: Value(p['scope_in'] as String?),
      scopeOut: Value(p['scope_out'] as String?),
      deliveryApproach: Value(p['delivery_approach'] as String?),
      successCriteria: Value(p['success_criteria'] as String?),
      keyConstraints: Value(p['key_constraints'] as String?),
      assumptions: Value(p['assumptions'] as String?),
      sourceProjectId: Value(rec.sourceEntityId),
      sourceProjectName: Value(p['source_project_name'] as String?),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _applyStatusReport(
      String programmeId, CascadeRecord rec) async {
    final id =
        'cascade:${CascadeKinds.statusReport}:${rec.sourceEntityId}:${rec.itemId}';
    if (rec.deleted) {
      await (db.delete(db.statusReports)..where((t) => t.id.equals(id)))
          .go();
      return;
    }
    final p = rec.payload;
    final reportDateRaw = p['report_date'] as String?;
    await db.reportsDao.upsertReport(StatusReportsCompanion.insert(
      id: id,
      projectId: programmeId,
      title: p['title'] as String? ?? '(untitled)',
      period: Value(p['period'] as String?),
      overallRag: Value(p['overall_rag'] as String? ?? 'green'),
      summary: Value(p['summary'] as String?),
      accomplishments: Value(p['accomplishments'] as String?),
      nextSteps: Value(p['next_steps'] as String?),
      risksHighlighted: Value(p['risks_highlighted'] as String?),
      content: Value(p['content'] as String?),
      reportDate:
          Value(reportDateRaw == null ? null : DateTime.parse(reportDateRaw)),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }
}
