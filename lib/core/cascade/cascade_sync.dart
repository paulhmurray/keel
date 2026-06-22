import '../database/database.dart';
import 'cascade_service.dart';

/// Drives a full cascade reconcile for [projectId] as part of a sync.
///
/// Cascade and project-blob sync are separate channels on the server, so
/// pushing/pulling a project's own encrypted blob does nothing for the
/// portfolio link. This function bridges that gap: it is meant to run on
/// every sync so escalated items and cascaded data actually flow without
/// waiting for an app relaunch.
///
/// Order matters:
///   1. Activate any `pending_remote` links whose partner has since joined
///      (so a link paired between syncs starts flowing on this very call).
///   2. Then, depending on the entity kind:
///      - **programme** → pull cascaded items down from every active link.
///      - **project**   → replay every cascade-eligible row up to every
///        active linked programme. This is the path that was previously
///        only invoked at escalate-time, which silently dropped anything
///        escalated while the link was still pending or while offline.
///
/// Pure orchestration over the injected [cascade] service and optional
/// [linksGateway] — no http client — so it is unit-testable with fakes.
/// Returns the number of cascaded items applied on the programme side
/// (always 0 on the project side).
Future<int> reconcileCascade({
  required AppDatabase db,
  required CascadeService cascade,
  required String projectId,
  RemoteLinksGateway? linksGateway,
  String? remoteUserId,
}) async {
  // 1) Activate links the server now reports as fully paired.
  if (linksGateway != null && remoteUserId != null) {
    try {
      await db.programmeLinksDao.refreshPendingLinks(
        remoteUserId: remoteUserId,
        remote: linksGateway,
      );
    } catch (_) {
      // Non-fatal — pending links retry on the next sync / launch.
    }
  }

  final project = await db.projectDao.getProjectById(projectId);
  if (project == null) return 0;

  // 2a) Programme side: pull everything our linked projects have published.
  if (project.kind == 'programme') {
    return cascade.pullForProgramme(project.id);
  }

  // 2b) Project side: replay all cascade-eligible content up the links.
  // Each push is internally guarded (escalation flag, never-re-cascade,
  // active-links-only) and best-effort, so calling them unconditionally
  // is safe and idempotent.
  await cascade.pushAllEscalatedRaid(project.id);
  await cascade.pushAllEscalatedDelivery(project.id);
  await cascade.pushAllWorkPackages(project.id);
  await cascade.pushAllStatusReports(project.id);
  await cascade.pushAllPeople(projectId: project.id, projectName: project.name);
  await cascade.pushCurrentCharter(
      projectId: project.id, projectName: project.name);
  return 0;
}
