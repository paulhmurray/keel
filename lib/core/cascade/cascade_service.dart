import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../finance/contingency_ledger.dart';
import '../raid/risk_rating.dart';
import 'cascade_plan_detail.dart';

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
  // Plan detail (full-share links only). Activities carry tasks via
  // parent_activity_id; plan dependencies are the Gantt arrows.
  static const activity = 'activity';
  static const planDependency = 'plan_dependency';
  // Finance (full-share links only). Budget + snapshot payloads embed
  // their lines so a header and its cells land atomically.
  static const costCategory = 'cost_category';
  static const budget = 'budget';
  static const forecastSnapshot = 'forecast_snapshot';
  static const actual = 'actual';
  // Programme → PROJECT (the one downward kind): what the programme has
  // allocated to this project, with the movement history behind it.
  static const allocation = 'allocation';
}

/// How much of a project a link carries. Stored on ProgrammeLinks.
class CascadeShareLevels {
  CascadeShareLevels._();
  /// Only explicitly escalated RAID / actions / decisions, plus the
  /// always-on kinds (WP headers, reports, charter, people, roles).
  static const escalated = 'escalated';
  /// Everything: the whole RAID and delivery registers, and the plan
  /// down to activities, tasks and arrows.
  static const full = 'full';

  static bool isFull(String? level) => level == full;
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
    final links = await _pushLinksForEntity(wp.projectId);
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
    final links = await _pushLinksForEntity(projectId);
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

  // Every register push is SELF-GATING per link: a full-share link gets
  // the row whatever its escalation state; an escalated-only link gets
  // it only while escalatedAt is set and is sent a tombstone otherwise.
  // Callers therefore push on every save (and after un-escalating)
  // without checking the flag themselves. Rows that are themselves
  // cascaded copies never re-cascade.

  Future<void> pushRisk(Risk risk) => _pushRegisterItem(
        projectId: risk.projectId,
        itemKind: CascadeKinds.risk,
        itemId: risk.id,
        escalatedAt: risk.escalatedAt,
        sourceProjectId: risk.sourceProjectId,
        payload: _riskPayload(risk),
      );

  Future<void> pushAssumption(Assumption a) => _pushRegisterItem(
        projectId: a.projectId,
        itemKind: CascadeKinds.assumption,
        itemId: a.id,
        escalatedAt: a.escalatedAt,
        sourceProjectId: a.sourceProjectId,
        payload: _assumptionPayload(a),
      );

  Future<void> pushIssue(Issue i) => _pushRegisterItem(
        projectId: i.projectId,
        itemKind: CascadeKinds.issue,
        itemId: i.id,
        escalatedAt: i.escalatedAt,
        sourceProjectId: i.sourceProjectId,
        payload: _issuePayload(i),
      );

  Future<void> pushDependency(ProgramDependency d) => _pushRegisterItem(
        projectId: d.projectId,
        itemKind: CascadeKinds.dependency,
        itemId: d.id,
        escalatedAt: d.escalatedAt,
        sourceProjectId: d.sourceProjectId,
        payload: _dependencyPayload(d),
      );

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
    final links = await _pushLinksForEntity(projectId);
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
    final links = await _pushLinksForEntity(projectId);
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
    final links = await _pushLinksForEntity(projectId);
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
    final links = await _pushLinksForEntity(projectId);
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
    final links = await _pushLinksForEntity(projectId);
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

  Future<void> pushAction(ProjectAction a) => _pushRegisterItem(
        projectId: a.projectId,
        itemKind: CascadeKinds.action,
        itemId: a.id,
        escalatedAt: a.escalatedAt,
        sourceProjectId: a.sourceProjectId,
        payload: _actionPayload(a),
      );

  Future<void> pushDecision(Decision d) => _pushRegisterItem(
        projectId: d.projectId,
        itemKind: CascadeKinds.decision,
        itemId: d.id,
        escalatedAt: d.escalatedAt,
        sourceProjectId: d.sourceProjectId,
        payload: _decisionPayload(d),
      );

  /// Replays every Action + Decision through the per-link gate so a
  /// freshly-linked programme sees what it is entitled to. Symmetrical
  /// with [pushAllRaid].
  Future<void> pushAllDelivery(String projectId) async {
    if (gateway == null) return;
    for (final a in await db.actionsDao.getActionsForProject(projectId)) {
      await pushAction(a);
    }
    for (final d
        in await db.decisionsDao.getDecisionsForProject(projectId)) {
      await pushDecision(d);
    }
  }

  /// Replays every RAID row through the per-link gate. Used the same
  /// way as [pushAllWorkPackages].
  Future<void> pushAllRaid(String projectId) async {
    if (gateway == null) return;
    for (final r in await db.raidDao.getRisksForProject(projectId)) {
      await pushRisk(r);
    }
    for (final a in await db.raidDao.getAssumptionsForProject(projectId)) {
      await pushAssumption(a);
    }
    for (final i in await db.raidDao.getIssuesForProject(projectId)) {
      await pushIssue(i);
    }
    for (final d
        in await db.raidDao.getDependenciesForProject(projectId)) {
      await pushDependency(d);
    }
  }

  /// Tombstones every item an escalated-only link is no longer entitled
  /// to. Called when the project PM turns a link DOWN from full detail:
  /// unescalated RAID / actions / decisions and all plan detail are
  /// withdrawn from every escalated-only link; full-share links are
  /// untouched. Escalated rows stay.
  Future<void> retractUnescalated(String projectId) async {
    if (gateway == null) return;
    final links = (await _pushLinksForEntity(projectId))
        .where((l) => !CascadeShareLevels.isFull(l.shareLevel))
        .toList();
    if (links.isEmpty) return;

    Future<void> drop(String kind, String id) async {
      for (final link in links) {
        try {
          await gateway!.delete(code: link.code, itemKind: kind, itemId: id);
        } catch (_) {}
      }
    }

    for (final r in await db.raidDao.getRisksForProject(projectId)) {
      if (r.escalatedAt == null) await drop(CascadeKinds.risk, r.id);
    }
    for (final a in await db.raidDao.getAssumptionsForProject(projectId)) {
      if (a.escalatedAt == null) await drop(CascadeKinds.assumption, a.id);
    }
    for (final i in await db.raidDao.getIssuesForProject(projectId)) {
      if (i.escalatedAt == null) await drop(CascadeKinds.issue, i.id);
    }
    for (final d
        in await db.raidDao.getDependenciesForProject(projectId)) {
      if (d.escalatedAt == null) await drop(CascadeKinds.dependency, d.id);
    }
    for (final a in await db.actionsDao.getActionsForProject(projectId)) {
      if (a.escalatedAt == null) await drop(CascadeKinds.action, a.id);
    }
    for (final d
        in await db.decisionsDao.getDecisionsForProject(projectId)) {
      if (d.escalatedAt == null) await drop(CascadeKinds.decision, d.id);
    }
    for (final a
        in await db.programmeGanttDao.getActivitiesForProject(projectId)) {
      await drop(CascadeKinds.activity, a.id);
    }
    for (final d in await db.programmeGanttDao.getDependencies(projectId)) {
      await drop(CascadeKinds.planDependency, d.id);
    }
    for (final c in await db.financeDao.getCategories(projectId)) {
      await drop(CascadeKinds.costCategory, c.id);
    }
    for (final b in await db.financeDao.getBudgets(projectId)) {
      await drop(CascadeKinds.budget, b.id);
    }
    for (final sn in await db.financeDao.getSnapshots(projectId)) {
      await drop(CascadeKinds.forecastSnapshot, sn.id);
    }
    for (final a in await db.financeDao.getActuals(projectId)) {
      await drop(CascadeKinds.actual, a.id);
    }
  }

  // ── Finance (full-share links only) ─────────────────────────────────────
  //
  // Projects own the detail; the programme holds read-only copies. Only
  // the APPROVED budget and SUBMITTED snapshots leave the project —
  // drafts and working forecasts are the PM's own. The audit log never
  // cascades.

  Future<void> pushCostCategory(CostCategory c) async {
    if (gateway == null || c.sourceProjectId != null) return;
    await _pushFinance(c.projectId, CascadeKinds.costCategory, c.id, {
      'name': c.name,
      'sort_order': c.sortOrder,
    });
  }

  Future<void> deleteCostCategory({
    required String projectId,
    required String categoryId,
  }) =>
      _tombstone(projectId, CascadeKinds.costCategory, categoryId);

  /// Pushes [budgetId] with its lines when it is the approved budget;
  /// anything else is a no-op (drafts stay home; the programme drops
  /// superseded copies itself when the new approved one arrives).
  Future<void> pushBudget(String budgetId) async {
    if (gateway == null) return;
    final b = await db.financeDao.getBudgetById(budgetId);
    if (b == null || b.sourceProjectId != null || b.status != 'approved') {
      return;
    }
    final lines = await db.financeDao.getLines(b.id);
    // The channel must hold ONE budget per project: tombstone the ones
    // this approval superseded so a later replay can't resurrect them.
    for (final other in await db.financeDao.getBudgets(b.projectId)) {
      if (other.id != b.id && other.status != 'draft') {
        await _tombstone(b.projectId, CascadeKinds.budget, other.id);
      }
    }
    await _pushFinance(b.projectId, CascadeKinds.budget, b.id, {
      'name': b.name,
      'status': b.status,
      if (b.approvedBy != null) 'approved_by': b.approvedBy,
      if (b.approvedAt != null) 'approved_at': b.approvedAt!.toIso8601String(),
      'currency': b.currency,
      if (b.fundingSource != null) 'funding_source': b.fundingSource,
      if (b.notes != null) 'notes': b.notes,
      'variance_tolerance_bp': b.varianceToleranceBp,
      'lines': [for (final l in lines) _moneyLine(l.id, l.costCategoryId,
          l.workstreamId, l.financialYear, l.amountMinor, l.notes)],
    });
  }

  Future<void> deleteBudget({
    required String projectId,
    required String budgetId,
  }) =>
      _tombstone(projectId, CascadeKinds.budget, budgetId);

  /// Pushes a SUBMITTED snapshot with its lines; working ones are a no-op.
  /// Reopening must tombstone explicitly ([deleteForecastSnapshot]).
  Future<void> pushForecastSnapshot(String snapshotId) async {
    if (gateway == null) return;
    final sn = await db.financeDao.getSnapshotById(snapshotId);
    if (sn == null || sn.sourceProjectId != null || sn.status != 'submitted') {
      return;
    }
    final lines = await db.financeDao.getForecastLines(sn.id);
    await _pushFinance(sn.projectId, CascadeKinds.forecastSnapshot, sn.id, {
      'period': sn.period,
      'status': sn.status,
      if (sn.submittedAt != null)
        'submitted_at': sn.submittedAt!.toIso8601String(),
      'lines': [for (final l in lines) _moneyLine(l.id, l.costCategoryId,
          l.workstreamId, l.financialYear, l.amountMinor, l.notes)],
    });
  }

  Future<void> deleteForecastSnapshot({
    required String projectId,
    required String snapshotId,
  }) =>
      _tombstone(projectId, CascadeKinds.forecastSnapshot, snapshotId);

  Future<void> pushActual(ActualLine a) async {
    if (gateway == null || a.sourceProjectId != null) return;
    await _pushFinance(a.projectId, CascadeKinds.actual, a.id, {
      'period': a.period,
      'cost_category_id': a.costCategoryId,
      if (a.workstreamId != null) 'workstream_id': a.workstreamId,
      'amount_minor': a.amountMinor,
      'source': a.source,
      if (a.sourceRef != null) 'source_ref': a.sourceRef,
      if (a.enteredBy != null) 'entered_by': a.enteredBy,
      if (a.notes != null) 'notes': a.notes,
    });
  }

  Future<void> deleteActual({
    required String projectId,
    required String actualId,
  }) =>
      _tombstone(projectId, CascadeKinds.actual, actualId);

  /// Replays everything finance a full-share link is entitled to:
  /// categories, the approved budget, submitted snapshots, actuals.
  Future<void> pushAllFinance(String projectId) async {
    if (gateway == null) return;
    if ((await _fullLinksForEntity(projectId)).isEmpty) return;
    for (final c in await db.financeDao.getCategories(projectId)) {
      await pushCostCategory(c);
    }
    final approved = await db.financeDao.getApprovedBudget(projectId);
    if (approved != null) await pushBudget(approved.id);
    for (final sn in await db.financeDao.getSnapshots(projectId)) {
      if (sn.status == 'submitted') await pushForecastSnapshot(sn.id);
    }
    for (final a in await db.financeDao.getActuals(projectId)) {
      await pushActual(a);
    }
  }

  // ── Allocation (programme → project) ─────────────────────────────────────
  //
  // The only kind that flows DOWN. Pushed over the programme's own link
  // row for that project (same-machine: partnerLocalId names it). Not
  // gated by share level — it is the programme's statement about the
  // project, not the project's data.

  Future<void> pushAllocation(String programmeId, String linkedProjectId) async {
    if (gateway == null) return;
    final links = (await _activeLinksForEntity(programmeId))
        .where((l) => l.ownerKind == 'programme' && l.partnerLocalId == linkedProjectId)
        .toList();
    if (links.isEmpty) return;
    final programme = await db.projectDao.getProjectById(programmeId);
    final ledger = computeLedger(
      approvals: await db.financeDao.getFunding(programmeId),
      movements: await db.financeDao.getMovements(programmeId),
    );
    final alloc = ledger.forProject(linkedProjectId);
    final decisions = {
      for (final d in await db.decisionsDao.getDecisionsForProject(programmeId))
        d.id: d
    };
    final payload = <String, dynamic>{
      'programme_name': programme?.name,
      'amount_minor': alloc?.allocatedMinor ?? 0,
      'currency': ledger.currency ?? 'AUD',
      'history': [
        for (final m in alloc?.history ?? const <ContingencyMovement>[])
          {
            'moved_on': m.movedOn,
            'kind': m.kind,
            'amount_minor': m.amountMinor,
            if (m.decisionId != null)
              'decision_ref': decisions[m.decisionId]?.ref ?? m.decisionId,
            'decision': ?decisions[m.decisionId]?.description,
            'reason': ?m.reason,
          },
      ],
    };
    for (final link in links) {
      try {
        await gateway!.push(
          code: link.code,
          sourceEntityId: programmeId,
          itemKind: CascadeKinds.allocation,
          itemId: linkedProjectId,
          payload: payload,
        );
      } catch (_) {}
    }
  }

  /// Every linked project's allocation — including projects with no
  /// movements yet, so a zero allocation still reads as "none" downstream.
  Future<void> pushAllAllocations(String programmeId) async {
    if (gateway == null) return;
    final links = (await _activeLinksForEntity(programmeId))
        .where((l) => l.ownerKind == 'programme' && l.partnerLocalId != null);
    for (final l in links) {
      await pushAllocation(programmeId, l.partnerLocalId!);
    }
  }

  /// Project side: read what linked programmes have said about this
  /// project. Only the downward kinds apply; the project's own records
  /// on the channel are skipped. Returns the number applied.
  Future<int> pullForProject(String projectId) async {
    if (gateway == null) return 0;
    var applied = 0;
    for (final link in await _pushLinksForEntity(projectId)) {
      try {
        final snap = await gateway!.pull(code: link.code);
        for (final rec in snap.items) {
          if (rec.sourceEntityId == projectId) continue;
          if (rec.itemKind != CascadeKinds.allocation) continue;
          if (rec.itemId != projectId) continue;
          await _applyAllocation(projectId, rec);
          applied++;
        }
      } catch (_) {}
    }
    return applied;
  }

  Future<void> _applyAllocation(String projectId, CascadeRecord rec) async {
    final id = 'cascade:${CascadeKinds.allocation}:${rec.sourceEntityId}:$projectId';
    if (rec.deleted) {
      await (db.delete(db.receivedAllocations)..where((t) => t.id.equals(id))).go();
      return;
    }
    final p = rec.payload;
    await db.financeDao.upsertReceivedAllocationRaw(ReceivedAllocationsCompanion(
      id: Value(id),
      projectId: Value(projectId),
      programmeId: Value(rec.sourceEntityId),
      programmeName: Value(p['programme_name'] as String?),
      amountMinor: Value(p['amount_minor'] as int? ?? 0),
      currency: Value(p['currency'] as String? ?? 'AUD'),
      historyJson: Value(p['history'] == null ? null : jsonEncode(p['history'])),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Map<String, dynamic> _moneyLine(String id, String categoryId,
          String? workstreamId, String financialYear, int amountMinor,
          String? notes) =>
      {
        'id': id,
        'cost_category_id': categoryId,
        'workstream_id': ?workstreamId,
        'financial_year': financialYear,
        'amount_minor': amountMinor,
        'notes': ?notes,
      };

  Future<void> _pushFinance(String projectId, String kind, String id,
      Map<String, dynamic> payload) async {
    final links = await _fullLinksForEntity(projectId);
    for (final link in links) {
      try {
        await gateway!.push(
          code: link.code,
          sourceEntityId: projectId,
          itemKind: kind,
          itemId: id,
          payload: payload,
        );
      } catch (_) {}
    }
  }

  // ── Plan detail (full-share links only) ─────────────────────────────────
  //
  // Activities, tasks and arrows cascade as a unit with their WP so a
  // programme on a full-share link holds the project's whole WBS. Months
  // travel raw AND as absolute dates (when the source has a calendar
  // anchor) so the programme can re-key them onto its own axis.

  Future<void> pushActivity(TimelineActivity a) async {
    if (gateway == null || a.sourceProjectId != null) return;
    final links = await _fullLinksForEntity(a.projectId);
    if (links.isEmpty) return;
    final payload = await _activityPayload(a);
    for (final link in links) {
      try {
        await gateway!.push(
          code: link.code,
          sourceEntityId: a.projectId,
          itemKind: CascadeKinds.activity,
          itemId: a.id,
          payload: payload,
        );
      } catch (_) {}
    }
  }

  Future<void> pushAllActivities(String projectId) async {
    if (gateway == null) return;
    if ((await _fullLinksForEntity(projectId)).isEmpty) return;
    for (final a
        in await db.programmeGanttDao.getActivitiesForProject(projectId)) {
      await pushActivity(a);
    }
  }

  Future<void> deleteActivity({
    required String projectId,
    required String activityId,
  }) =>
      _tombstone(projectId, CascadeKinds.activity, activityId);

  Future<void> pushPlanDependency(TimelineDependency d) async {
    if (gateway == null || d.sourceProjectId != null) return;
    final links = await _fullLinksForEntity(d.projectId);
    if (links.isEmpty) return;
    final payload = _planDependencyPayload(d);
    for (final link in links) {
      try {
        await gateway!.push(
          code: link.code,
          sourceEntityId: d.projectId,
          itemKind: CascadeKinds.planDependency,
          itemId: d.id,
          payload: payload,
        );
      } catch (_) {}
    }
  }

  Future<void> pushAllPlanDependencies(String projectId) async {
    if (gateway == null) return;
    if ((await _fullLinksForEntity(projectId)).isEmpty) return;
    for (final d in await db.programmeGanttDao.getDependencies(projectId)) {
      await pushPlanDependency(d);
    }
  }

  Future<void> deletePlanDependency({
    required String projectId,
    required String dependencyId,
  }) =>
      _tombstone(projectId, CascadeKinds.planDependency, dependencyId);

  /// Pushes a WP's activities and every arrow touching them. The Gantt
  /// calls this beside its WP re-push after any activity edit.
  Future<void> pushPlanDetailForWp(String projectId, String wpId) async {
    if (gateway == null) return;
    if ((await _fullLinksForEntity(projectId)).isEmpty) return;
    final acts = await db.programmeGanttDao.getActivitiesForWP(wpId);
    final ids = {for (final a in acts) a.id};
    for (final a in acts) {
      await pushActivity(a);
    }
    for (final d in await db.programmeGanttDao.getDependencies(projectId)) {
      if (ids.contains(d.fromActivityId) || ids.contains(d.toActivityId)) {
        await pushPlanDependency(d);
      }
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
    await _purgeSelfCopies(programmeId);
    final links = await _activeLinksForEntity(programmeId);
    var applied = 0;
    for (final link in links) {
      try {
        // Phase C.1 doesn't persist the cursor yet — we re-fetch the
        // whole channel each call. Cheap for typical programme sizes
        // and avoids cursor-corruption corner cases. A future slice
        // adds per-link cursors when payload volumes grow.
        final snap = await gateway!.pull(code: link.code);
        // Activities need their WP row, arrows need their activities, so
        // apply plan detail after everything else regardless of the
        // order the channel returns it in.
        final ordered = [...snap.items]..sort(
            (a, b) => _applyRank(a.itemKind).compareTo(_applyRank(b.itemKind)));
        for (final rec in ordered) {
          // A programme's own rows on the channel (from a build that let
          // programme-native saves push) are not cascade input.
          if (rec.sourceEntityId == programmeId) continue;
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
            case CascadeKinds.activity:
              await _applyActivity(programmeId, rec);
              applied++;
            case CascadeKinds.planDependency:
              await _applyPlanDependency(programmeId, rec);
              applied++;
            case CascadeKinds.costCategory:
              await _applyCostCategory(programmeId, rec);
              applied++;
            case CascadeKinds.budget:
              await _applyBudget(programmeId, rec);
              applied++;
            case CascadeKinds.forecastSnapshot:
              await _applyForecastSnapshot(programmeId, rec);
              applied++;
            case CascadeKinds.actual:
              await _applyActual(programmeId, rec);
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

  /// Removes rows the programme once cascaded onto itself (native data
  /// that round-tripped through its own link code). One cheap sweep per
  /// pull keeps the registers honest after upgrading.
  Future<void> _purgeSelfCopies(String programmeId) async {
    Future<void> sweep(TableInfo table, GeneratedColumn<String> projectId,
        GeneratedColumn<String> source) async {
      await (db.delete(table)
            ..where((_) =>
                projectId.equals(programmeId) & source.equals(programmeId)))
          .go();
    }

    await sweep(db.timelineDependencies, db.timelineDependencies.projectId,
        db.timelineDependencies.sourceProjectId);
    await sweep(db.timelineActivities, db.timelineActivities.projectId,
        db.timelineActivities.sourceProjectId);
    await sweep(db.timelineWorkPackages, db.timelineWorkPackages.projectId,
        db.timelineWorkPackages.sourceProjectId);
    await sweep(db.risks, db.risks.projectId, db.risks.sourceProjectId);
    await sweep(db.assumptions, db.assumptions.projectId,
        db.assumptions.sourceProjectId);
    await sweep(db.issues, db.issues.projectId, db.issues.sourceProjectId);
    await sweep(db.programDependencies, db.programDependencies.projectId,
        db.programDependencies.sourceProjectId);
    await sweep(db.projectActions, db.projectActions.projectId,
        db.projectActions.sourceProjectId);
    await sweep(db.decisions, db.decisions.projectId,
        db.decisions.sourceProjectId);
    await sweep(db.budgetLines, db.budgetLines.projectId,
        db.budgetLines.sourceProjectId);
    await sweep(db.forecastLines, db.forecastLines.projectId,
        db.forecastLines.sourceProjectId);
    await sweep(db.projectBudgets, db.projectBudgets.projectId,
        db.projectBudgets.sourceProjectId);
    await sweep(db.forecastSnapshots, db.forecastSnapshots.projectId,
        db.forecastSnapshots.sourceProjectId);
    await sweep(db.actualLines, db.actualLines.projectId,
        db.actualLines.sourceProjectId);
    await sweep(db.costCategories, db.costCategories.projectId,
        db.costCategories.sourceProjectId);
  }

  Future<List<ProgrammeLink>> _activeLinksForEntity(String id) async {
    final all = await db.programmeLinksDao.getLinksForEntity(id);
    return all.where((l) => l.status == 'active').toList();
  }

  /// Links a PROJECT pushes over: its own active rows. A programme also
  /// owns link rows (the other side of each pair), and pushing its native
  /// data over those would pull it straight back as a copy of itself —
  /// so push paths use this, never [_activeLinksForEntity].
  Future<List<ProgrammeLink>> _pushLinksForEntity(String id) async =>
      (await _activeLinksForEntity(id))
          .where((l) => l.ownerKind == 'project')
          .toList();

  Future<List<ProgrammeLink>> _fullLinksForEntity(String id) async =>
      (await _pushLinksForEntity(id))
          .where((l) => CascadeShareLevels.isFull(l.shareLevel))
          .toList();

  /// Pushes [payload] for ([itemKind], [itemId]) to every active link
  /// the source project is part of, regardless of share level — the
  /// always-on kinds (reports, charter, people, roles). Best-effort.
  Future<void> _pushToAllLinks({
    required String projectId,
    required String itemKind,
    required String itemId,
    required Map<String, dynamic> payload,
  }) async {
    if (gateway == null) return;
    final links = await _pushLinksForEntity(projectId);
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

  static int _applyRank(String kind) => switch (kind) {
        CascadeKinds.activity => 1,
        CascadeKinds.planDependency => 2,
        // Finance lines reference categories (and WPs), so categories go
        // first and the money after everything structural.
        CascadeKinds.costCategory => 3,
        CascadeKinds.budget => 4,
        CascadeKinds.forecastSnapshot => 4,
        CascadeKinds.actual => 4,
        _ => 0,
      };

  /// The per-link gate for RAID / actions / decisions. Pushes to every
  /// active link entitled to the row; cascaded copies never re-cascade.
  Future<void> _pushRegisterItem({
    required String projectId,
    required String itemKind,
    required String itemId,
    required DateTime? escalatedAt,
    required String? sourceProjectId,
    required Map<String, dynamic> payload,
  }) async {
    if (gateway == null || sourceProjectId != null) return;
    final links = await _pushLinksForEntity(projectId);
    final body = {...payload, 'escalated': escalatedAt != null};
    for (final link in links) {
      final entitled =
          CascadeShareLevels.isFull(link.shareLevel) || escalatedAt != null;
      try {
        if (entitled) {
          await gateway!.push(
            code: link.code,
            sourceEntityId: projectId,
            itemKind: itemKind,
            itemId: itemId,
            payload: body,
          );
        } else {
          // Not entitled (any more): withdraw it. This is what makes
          // "Stop sharing" take the row off a shared-items-only
          // programme while a full-detail one simply keeps it unflagged.
          await gateway!.delete(
              code: link.code, itemKind: itemKind, itemId: itemId);
        }
      } catch (_) {
        // Best-effort — next save / refresh will retry.
      }
    }
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

  Map<String, dynamic> _riskPayload(Risk r) => {
        if (r.ref != null) 'ref': r.ref,
        'description': r.description,
        'likelihood': r.likelihood,
        'impact': r.impact,
        'status': r.status,
        if (r.owner != null) 'owner': r.owner,
        if (r.mitigation != null) 'mitigation': r.mitigation,
        if (r.closedAt != null) 'closed_at': r.closedAt,
        if (r.closureNote != null) 'closure_note': r.closureNote,
        if (r.title != null) 'title': r.title,
        if (r.likelihoodTarget != null) 'likelihood_target': r.likelihoodTarget,
        if (r.impactTarget != null) 'impact_target': r.impactTarget,
        'strategy': r.strategy,
        if (r.assignee != null) 'assignee': r.assignee,
        if (r.enterpriseRiskLink != null)
          'enterprise_risk_link': r.enterpriseRiskLink,
        if (r.dueDate != null) 'due_date': r.dueDate,
        if (r.statusNote != null) 'status_note': r.statusNote,
        'steerco': r.steerco,
        if (r.lastReviewedAt != null) 'last_reviewed_at': r.lastReviewedAt,
        if (r.nextReviewAt != null) 'next_review_at': r.nextReviewAt,
        if (r.likelihoodRationale != null)
          'likelihood_rationale': r.likelihoodRationale,
        if (r.impactRationale != null) 'impact_rationale': r.impactRationale,
        if (r.sourceNote != null) 'source_note': r.sourceNote,
      };

  Map<String, dynamic> _assumptionPayload(Assumption a) => {
        if (a.ref != null) 'ref': a.ref,
        'description': a.description,
        'status': a.status,
        if (a.owner != null) 'owner': a.owner,
        if (a.closedAt != null) 'closed_at': a.closedAt,
        if (a.validatedBy != null) 'validated_by': a.validatedBy,
        if (a.sourceNote != null) 'source_note': a.sourceNote,
      };

  Map<String, dynamic> _issuePayload(Issue i) => {
        if (i.ref != null) 'ref': i.ref,
        'description': i.description,
        'priority': i.priority,
        'status': i.status,
        if (i.owner != null) 'owner': i.owner,
        if (i.dueDate != null) 'due_date': i.dueDate,
        if (i.resolution != null) 'resolution': i.resolution,
        if (i.closedAt != null) 'closed_at': i.closedAt,
        if (i.title != null) 'title': i.title,
        if (i.impactStatement != null) 'impact_statement': i.impactStatement,
        'escalation_required': i.escalationRequired,
        if (i.sourceNote != null) 'source_note': i.sourceNote,
      };

  Map<String, dynamic> _dependencyPayload(ProgramDependency d) => {
        if (d.ref != null) 'ref': d.ref,
        'description': d.description,
        'dependency_type': d.dependencyType,
        'status': d.status,
        if (d.owner != null) 'owner': d.owner,
        if (d.dueDate != null) 'due_date': d.dueDate,
        if (d.closedAt != null) 'closed_at': d.closedAt,
        if (d.counterparty != null) 'counterparty': d.counterparty,
        if (d.rationale != null) 'rationale': d.rationale,
        if (d.impactStatement != null) 'impact_statement': d.impactStatement,
        if (d.sourceNote != null) 'source_note': d.sourceNote,
        // plan_activity_id deliberately omitted — project-local id.
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
        if (d.optionsConsidered != null)
          'options_considered': d.optionsConsidered,
        if (d.impactStatement != null) 'impact_statement': d.impactStatement,
        if (d.decidedAt != null) 'decided_at': d.decidedAt,
        // plan_activity_id deliberately omitted — project-local id.
      };

  /// Plan detail payload. Months travel raw; when the source project has
  /// a calendar anchor the start month also travels as an absolute date so
  /// the programme can re-key onto its own axis. Day-precise start/end
  /// dates on the activity pass through untouched.
  Future<Map<String, dynamic>> _activityPayload(TimelineActivity a) async {
    final header = await db.programmeGanttDao.getHeader(a.projectId);
    final anchor = _parseDate(header?.month0Date);
    final startMonthDate = anchor == null || a.startMonth == null
        ? null
        : DateTime(anchor.year, anchor.month + a.startMonth!, 1)
            .toIso8601String();
    return {
      'work_package_id': a.workPackageId,
      'name': a.name,
      if (a.owner != null) 'owner': a.owner,
      if (a.ownerId != null) 'owner_id': a.ownerId,
      'activity_type': a.activityType,
      if (a.parentActivityId != null) 'parent_activity_id': a.parentActivityId,
      if (a.startMonth != null) 'start_month': a.startMonth,
      if (a.endMonth != null) 'end_month': a.endMonth,
      if (a.likelyMonth != null) 'likely_month': a.likelyMonth,
      if (a.safeMonth != null) 'safe_month': a.safeMonth,
      if (a.startDate != null) 'start_date': a.startDate,
      if (a.endDate != null) 'end_date': a.endDate,
      'start_month_date': ?startMonthDate,
      if (a.varianceRaidType != null) 'variance_raid_type': a.varianceRaidType,
      if (a.varianceRaidId != null) 'variance_raid_id': a.varianceRaidId,
      if (a.varianceRaidLinksJson != null)
        'variance_raid_links': a.varianceRaidLinksJson,
      'status': a.status,
      'is_critical': a.isCritical,
      'is_baseline': a.isBaseline,
      if (a.baselineStart != null) 'baseline_start': a.baselineStart,
      if (a.baselineEnd != null) 'baseline_end': a.baselineEnd,
      if (a.cellLabel != null) 'cell_label': a.cellLabel,
      if (a.notes != null) 'notes': a.notes,
      if (a.contributors != null) 'contributors': a.contributors,
      if (a.contributorIds != null) 'contributor_ids': a.contributorIds,
      'sort_order': a.sortOrder,
    };
  }

  Map<String, dynamic> _planDependencyPayload(TimelineDependency d) => {
        'from_activity_id': d.fromActivityId,
        'to_activity_id': d.toActivityId,
        'dependency_type': d.dependencyType,
        if (d.externalLabel != null) 'external_label': d.externalLabel,
        if (d.notes != null) 'notes': d.notes,
      };

  static DateTime? _parseDate(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      return DateTime.parse(iso);
    } catch (_) {
      return null;
    }
  }

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
      // Take the WP's cascaded plan detail down with it.
      final acts = await db.programmeGanttDao.getActivitiesForWP(localId);
      final ids = {for (final a in acts) a.id};
      if (ids.isNotEmpty) {
        await (db.delete(db.timelineDependencies)
              ..where((t) =>
                  t.fromActivityId.isIn(ids) | t.toActivityId.isIn(ids)))
            .go();
      }
      await db.programmeGanttDao.deleteActivitiesForWP(localId);
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

  /// The programme-side escalation stamp. Full-share links carry rows the
  /// PM never flagged, so the payload says which; senders from before the
  /// share level existed only ever pushed escalated rows, so a missing
  /// key reads as escalated.
  DateTime? _escalatedStamp(CascadeRecord rec) =>
      (rec.payload['escalated'] as bool? ?? true) ? DateTime.now() : null;

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
      likelihood: Value(normaliseLikelihood(p['likelihood'] as String?)),
      impact: Value(normaliseConsequence(p['impact'] as String?)),
      status: Value(p['status'] as String? ?? 'open'),
      owner: Value(p['owner'] as String?),
      mitigation: Value(p['mitigation'] as String?),
      closedAt: Value(p['closed_at'] as String?),
      closureNote: Value(p['closure_note'] as String?),
      title: Value(p['title'] as String?),
      likelihoodTarget: Value(p['likelihood_target'] as String?),
      impactTarget: Value(p['impact_target'] as String?),
      strategy: Value(p['strategy'] as String? ?? 'treat'),
      assignee: Value(p['assignee'] as String?),
      enterpriseRiskLink: Value(p['enterprise_risk_link'] as String?),
      dueDate: Value(p['due_date'] as String?),
      statusNote: Value(p['status_note'] as String?),
      steerco: Value(p['steerco'] as bool? ?? false),
      lastReviewedAt: Value(p['last_reviewed_at'] as String?),
      nextReviewAt: Value(p['next_review_at'] as String?),
      likelihoodRationale: Value(p['likelihood_rationale'] as String?),
      impactRationale: Value(p['impact_rationale'] as String?),
      sourceNote: Value(p['source_note'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(_escalatedStamp(rec)),
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
      closedAt: Value(p['closed_at'] as String?),
      validatedBy: Value(p['validated_by'] as String?),
      sourceNote: Value(p['source_note'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(_escalatedStamp(rec)),
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
      closedAt: Value(p['closed_at'] as String?),
      title: Value(p['title'] as String?),
      impactStatement: Value(p['impact_statement'] as String?),
      escalationRequired: Value(p['escalation_required'] as bool? ?? false),
      sourceNote: Value(p['source_note'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(_escalatedStamp(rec)),
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
      closedAt: Value(p['closed_at'] as String?),
      counterparty: Value(p['counterparty'] as String?),
      rationale: Value(p['rationale'] as String?),
      impactStatement: Value(p['impact_statement'] as String?),
      sourceNote: Value(p['source_note'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(_escalatedStamp(rec)),
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
      escalatedAt: Value(_escalatedStamp(rec)),
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
      optionsConsidered: Value(p['options_considered'] as String?),
      impactStatement: Value(p['impact_statement'] as String?),
      decidedAt: Value(p['decided_at'] as String?),
      source: const Value('cascade'),
      escalatedAt: Value(_escalatedStamp(rec)),
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

  String _activityLocalId(String sourceEntityId, String activityId) =>
      'cascade:${CascadeKinds.activity}:$sourceEntityId:$activityId';

  /// Re-keys a source RAID id (risk/assumption/issue/dependency/decision)
  /// onto the cascaded row's synthetic id so plan ↔ register links keep
  /// resolving on the programme side.
  String _remapRegisterId(String sourceEntityId, String kind, String id) =>
      'cascade:$kind:$sourceEntityId:$id';

  /// Programme-side copy of a linked project's activity or task. Months
  /// are re-keyed onto the programme's own axis when both sides carry a
  /// calendar anchor (the offset between the two anchors is applied to
  /// every month column); otherwise the raw indices are kept, assuming
  /// aligned axes — the same rule the WP swimlane bar uses.
  Future<void> _applyActivity(String programmeId, CascadeRecord rec) async {
    final id = _activityLocalId(rec.sourceEntityId, rec.itemId);
    if (rec.deleted) {
      await (db.delete(db.timelineDependencies)
            ..where((t) =>
                t.fromActivityId.equals(id) | t.toActivityId.equals(id)))
          .go();
      await db.programmeGanttDao.deleteActivity(id);
      return;
    }
    final p = rec.payload;
    final wpSource = p['work_package_id'] as String?;
    if (wpSource == null) return;
    final wpLocal = 'cascade:${rec.sourceEntityId}:$wpSource';

    final rawStart = p['start_month'] as int?;
    final header = await db.programmeGanttDao.getHeader(programmeId);
    final offset = cascadeMonthOffset(
      rawStartMonth: rawStart,
      startMonthDate: _parseDate(p['start_month_date'] as String?),
      programmeAnchor: _parseDate(header?.month0Date),
    );
    int? shift(int? m) => m == null ? null : m + offset;

    String? remapRaid(String? type, String? rid) => type == null || rid == null
        ? null
        : _remapRegisterId(rec.sourceEntityId, type, rid);
    final linksJson = p['variance_raid_links'] as String?;
    String? remappedLinks;
    if (linksJson != null) {
      try {
        final list = (jsonDecode(linksJson) as List)
            .cast<Map<String, dynamic>>()
            .map((m) => {
                  'type': m['type'],
                  'id': remapRaid(m['type'] as String?, m['id'] as String?),
                })
            .toList();
        remappedLinks = jsonEncode(list);
      } catch (_) {
        remappedLinks = null;
      }
    }
    String? remapIds(String? json) {
      if (json == null) return null;
      try {
        final list = (jsonDecode(json) as List)
            .map((e) => _remapPersonId(rec, e as String?))
            .toList();
        return jsonEncode(list);
      } catch (_) {
        return null;
      }
    }

    final parentSource = p['parent_activity_id'] as String?;
    await db.programmeGanttDao.upsertActivity(TimelineActivitiesCompanion(
      id: Value(id),
      workPackageId: Value(wpLocal),
      projectId: Value(programmeId),
      name: Value(p['name'] as String? ?? '(unnamed)'),
      owner: Value(p['owner'] as String?),
      ownerId: Value(_remapPersonId(rec, p['owner_id'] as String?)),
      activityType: Value(p['activity_type'] as String? ?? 'activity'),
      parentActivityId: Value(parentSource == null
          ? null
          : _activityLocalId(rec.sourceEntityId, parentSource)),
      startMonth: Value(shift(rawStart)),
      endMonth: Value(shift(p['end_month'] as int?)),
      likelyMonth: Value(shift(p['likely_month'] as int?)),
      safeMonth: Value(shift(p['safe_month'] as int?)),
      startDate: Value(p['start_date'] as String?),
      endDate: Value(p['end_date'] as String?),
      varianceRaidType: Value(p['variance_raid_type'] as String?),
      varianceRaidId: Value(remapRaid(p['variance_raid_type'] as String?,
          p['variance_raid_id'] as String?)),
      varianceRaidLinksJson: Value(remappedLinks),
      status: Value(p['status'] as String? ?? 'not_started'),
      isCritical: Value(p['is_critical'] as bool? ?? false),
      isBaseline: Value(p['is_baseline'] as bool? ?? false),
      baselineStart: Value(shift(p['baseline_start'] as int?)),
      baselineEnd: Value(shift(p['baseline_end'] as int?)),
      cellLabel: Value(p['cell_label'] as String?),
      notes: Value(p['notes'] as String?),
      contributors: Value(p['contributors'] as String?),
      contributorIds: Value(remapIds(p['contributor_ids'] as String?)),
      sortOrder: Value(p['sort_order'] as int? ?? 0),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  String _financeId(String kind, String src, String id) =>
      'cascade:$kind:$src:$id';

  Future<void> _applyCostCategory(
      String programmeId, CascadeRecord rec) async {
    final id = _financeId(CascadeKinds.costCategory, rec.sourceEntityId, rec.itemId);
    if (rec.deleted) {
      await (db.delete(db.costCategories)..where((t) => t.id.equals(id))).go();
      return;
    }
    final p = rec.payload;
    await db.financeDao.upsertCategoryRaw(CostCategoriesCompanion(
      id: Value(id),
      projectId: Value(programmeId),
      name: Value(p['name'] as String? ?? '(unnamed)'),
      sortOrder: Value(p['sort_order'] as int? ?? 0),
      sourceProjectId: Value(rec.sourceEntityId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  String? _remapWorkstream(String src, String? wpId) =>
      wpId == null ? null : 'cascade:$src:$wpId';

  /// The approved budget with its lines. Only one budget per project is
  /// ever approved, so applying a new one also drops any other cascaded
  /// budget from the same source (the superseded one) — replay alone is
  /// then correct after a supersede, no tombstone choreography needed.
  Future<void> _applyBudget(String programmeId, CascadeRecord rec) async {
    final src = rec.sourceEntityId;
    final id = _financeId(CascadeKinds.budget, src, rec.itemId);
    Future<void> dropBudget(String budgetId) async {
      await (db.delete(db.budgetLines)..where((t) => t.budgetId.equals(budgetId)))
          .go();
      await (db.delete(db.projectBudgets)..where((t) => t.id.equals(budgetId)))
          .go();
    }
    if (rec.deleted) {
      await dropBudget(id);
      return;
    }
    final p = rec.payload;
    await db.transaction(() async {
      // Supersede: any other cascaded budget from this source goes.
      final others = (await db.financeDao.getCascadedBudgets(programmeId))
          .where((b) => b.sourceProjectId == src && b.id != id);
      for (final o in others) {
        await dropBudget(o.id);
      }
      await db.financeDao.upsertBudgetRaw(ProjectBudgetsCompanion(
        id: Value(id),
        projectId: Value(programmeId),
        name: Value(p['name'] as String? ?? '(unnamed)'),
        status: Value(p['status'] as String? ?? 'approved'),
        approvedBy: Value(p['approved_by'] as String?),
        approvedAt: Value(_parseDate(p['approved_at'] as String?)),
        currency: Value(p['currency'] as String? ?? 'AUD'),
        fundingSource: Value(p['funding_source'] as String?),
        notes: Value(p['notes'] as String?),
        varianceToleranceBp: Value(p['variance_tolerance_bp'] as int? ?? 500),
        sourceProjectId: Value(src),
        updatedAt: Value(DateTime.now()),
      ));
      // Lines are replaced wholesale — the payload is the truth.
      await (db.delete(db.budgetLines)..where((t) => t.budgetId.equals(id))).go();
      for (final raw in (p['lines'] as List? ?? const [])) {
        final l = (raw as Map).cast<String, dynamic>();
        await db.financeDao.upsertLineRaw(BudgetLinesCompanion(
          id: Value(_financeId('budget_line', src, l['id'] as String)),
          projectId: Value(programmeId),
          budgetId: Value(id),
          costCategoryId: Value(_financeId(CascadeKinds.costCategory, src,
              l['cost_category_id'] as String)),
          workstreamId:
              Value(_remapWorkstream(src, l['workstream_id'] as String?)),
          financialYear: Value(l['financial_year'] as String? ?? ''),
          amountMinor: Value(l['amount_minor'] as int? ?? 0),
          notes: Value(l['notes'] as String?),
          sourceProjectId: Value(src),
          updatedAt: Value(DateTime.now()),
        ));
      }
    });
  }

  Future<void> _applyForecastSnapshot(
      String programmeId, CascadeRecord rec) async {
    final src = rec.sourceEntityId;
    final id = _financeId(CascadeKinds.forecastSnapshot, src, rec.itemId);
    if (rec.deleted) {
      await (db.delete(db.forecastLines)..where((t) => t.snapshotId.equals(id)))
          .go();
      await (db.delete(db.forecastSnapshots)..where((t) => t.id.equals(id)))
          .go();
      return;
    }
    final p = rec.payload;
    await db.transaction(() async {
      await db.financeDao.upsertSnapshotRaw(ForecastSnapshotsCompanion(
        id: Value(id),
        projectId: Value(programmeId),
        period: Value(p['period'] as String? ?? ''),
        status: Value(p['status'] as String? ?? 'submitted'),
        submittedAt: Value(_parseDate(p['submitted_at'] as String?)),
        sourceProjectId: Value(src),
        updatedAt: Value(DateTime.now()),
      ));
      await (db.delete(db.forecastLines)..where((t) => t.snapshotId.equals(id)))
          .go();
      for (final raw in (p['lines'] as List? ?? const [])) {
        final l = (raw as Map).cast<String, dynamic>();
        await db.financeDao.upsertForecastLineRaw(ForecastLinesCompanion(
          id: Value(_financeId('forecast_line', src, l['id'] as String)),
          projectId: Value(programmeId),
          snapshotId: Value(id),
          costCategoryId: Value(_financeId(CascadeKinds.costCategory, src,
              l['cost_category_id'] as String)),
          workstreamId:
              Value(_remapWorkstream(src, l['workstream_id'] as String?)),
          financialYear: Value(l['financial_year'] as String? ?? ''),
          amountMinor: Value(l['amount_minor'] as int? ?? 0),
          notes: Value(l['notes'] as String?),
          sourceProjectId: Value(src),
          updatedAt: Value(DateTime.now()),
        ));
      }
    });
  }

  Future<void> _applyActual(String programmeId, CascadeRecord rec) async {
    final src = rec.sourceEntityId;
    final id = _financeId(CascadeKinds.actual, src, rec.itemId);
    if (rec.deleted) {
      await (db.delete(db.actualLines)..where((t) => t.id.equals(id))).go();
      return;
    }
    final p = rec.payload;
    final cat = p['cost_category_id'] as String?;
    if (cat == null) return;
    await db.financeDao.upsertActualLineRaw(ActualLinesCompanion(
      id: Value(id),
      projectId: Value(programmeId),
      period: Value(p['period'] as String? ?? ''),
      costCategoryId: Value(_financeId(CascadeKinds.costCategory, src, cat)),
      workstreamId: Value(_remapWorkstream(src, p['workstream_id'] as String?)),
      amountMinor: Value(p['amount_minor'] as int? ?? 0),
      source: Value(p['source'] as String? ?? 'manual'),
      sourceRef: Value(p['source_ref'] as String?),
      enteredBy: Value(p['entered_by'] as String?),
      notes: Value(p['notes'] as String?),
      sourceProjectId: Value(src),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Programme-side copy of a Gantt arrow. Endpoints are re-keyed to the
  /// cascaded activity ids; a register marker in the notes (a RAID
  /// dependency or decision drawn onto the plan) is re-keyed the same
  /// way so the programme's plan-link code still finds its RAID row.
  Future<void> _applyPlanDependency(
      String programmeId, CascadeRecord rec) async {
    final id =
        'cascade:${CascadeKinds.planDependency}:${rec.sourceEntityId}:${rec.itemId}';
    if (rec.deleted) {
      await db.programmeGanttDao.deleteDependency(id);
      return;
    }
    final p = rec.payload;
    final from = p['from_activity_id'] as String? ?? '';
    final to = p['to_activity_id'] as String?;
    if (to == null || to.isEmpty) return;
    await db.programmeGanttDao.upsertDependency(TimelineDependenciesCompanion(
      id: Value(id),
      projectId: Value(programmeId),
      fromActivityId:
          Value(from.isEmpty ? '' : _activityLocalId(rec.sourceEntityId, from)),
      toActivityId: Value(_activityLocalId(rec.sourceEntityId, to)),
      dependencyType: Value(p['dependency_type'] as String? ?? 'finish_to_start'),
      externalLabel: Value(p['external_label'] as String?),
      notes: Value(remapPlanLinkNote(rec.sourceEntityId, p['notes'] as String?)),
      sourceProjectId: Value(rec.sourceEntityId),
    ));
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
