import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// Which register item a plan arrow is bound to. Decisions gate an
/// activity the same way an inbound dependency does — the activity
/// can't start until the call is made — so they share the mechanism.
enum PlanLinkKind { dependency, decision }

/// Bridges a RAID dependency to the plan: when the PM ticks "show on
/// plan", an *external* timeline dependency is written against the
/// activity the RAID item gates, so the Gantt draws the arrow. The
/// timeline row is tagged in its `notes` column so it can be found,
/// re-labelled and removed as the RAID item changes — the activity
/// dialog keeps existing external rows keyed by label, so the tag
/// survives activity saves too.
class DependencyPlanLink {
  DependencyPlanLink._();

  static String _prefix(PlanLinkKind kind) => switch (kind) {
        PlanLinkKind.dependency => 'raid-dependency:',
        PlanLinkKind.decision => 'raid-decision:',
      };

  /// The marker stored in the timeline row's notes.
  static String noteFor(String itemId,
          {PlanLinkKind kind = PlanLinkKind.dependency}) =>
      '${_prefix(kind)}$itemId';

  /// The RAID dependency id a timeline row is bound to, or null.
  static String? dependencyIdFromNote(String? note) =>
      itemIdFromNote(note, kind: PlanLinkKind.dependency);

  /// The register item id a timeline row is bound to for [kind], or null.
  static String? itemIdFromNote(String? note,
      {PlanLinkKind kind = PlanLinkKind.dependency}) {
    final prefix = _prefix(kind);
    return note != null && note.startsWith(prefix)
        ? note.substring(prefix.length)
        : null;
  }

  /// Label shown on the Gantt: "D4 · Vendor delivers API keys".
  static String labelFor({required String? ref, required String description}) {
    final d = description.trim();
    final short = d.length > 60 ? '${d.substring(0, 57)}…' : d;
    return ref == null || ref.isEmpty ? short : '$ref · $short';
  }

  /// Only inbound/bilateral dependencies gate an activity's start; an
  /// outbound one is something we deliver, so no arrow into the plan.
  static bool canShowOnPlan(String dependencyType) =>
      dependencyType != 'outbound';

  /// The timeline row bound to [dependencyId], if any.
  static Future<TimelineDependency?> find(
      AppDatabase db, String projectId, String dependencyId,
      {PlanLinkKind kind = PlanLinkKind.dependency}) async {
    final note = noteFor(dependencyId, kind: kind);
    final all = await db.programmeGanttDao.getDependencies(projectId);
    for (final d in all) {
      if (d.notes == note) return d;
    }
    return null;
  }

  /// Reconciles the timeline row with the RAID item: creates, moves,
  /// re-labels or deletes it so the plan matches [show] + [activityId].
  static Future<void> sync(
    AppDatabase db, {
    required String projectId,
    required String dependencyId,
    required String? ref,
    required String description,
    required String dependencyType,
    required String? activityId,
    required bool show,
    PlanLinkKind kind = PlanLinkKind.dependency,
  }) async {
    final existing = await find(db, projectId, dependencyId, kind: kind);
    final wanted =
        show && activityId != null && canShowOnPlan(dependencyType);
    if (!wanted) {
      if (existing != null) {
        await db.programmeGanttDao.deleteDependency(existing.id);
      }
      return;
    }
    await db.programmeGanttDao.upsertDependency(TimelineDependenciesCompanion(
      id: Value(existing?.id ?? const Uuid().v4()),
      projectId: Value(projectId),
      fromActivityId: const Value(''),
      toActivityId: Value(activityId),
      dependencyType: const Value('external'),
      externalLabel: Value(labelFor(ref: ref, description: description)),
      notes: Value(noteFor(dependencyId, kind: kind)),
    ));
  }

  /// Drops the timeline row when the register item goes away (delete or
  /// conversion to another kind).
  static Future<void> remove(
      AppDatabase db, String projectId, String dependencyId,
      {PlanLinkKind kind = PlanLinkKind.dependency}) async {
    final existing = await find(db, projectId, dependencyId, kind: kind);
    if (existing != null) {
      await db.programmeGanttDao.deleteDependency(existing.id);
    }
  }
}
