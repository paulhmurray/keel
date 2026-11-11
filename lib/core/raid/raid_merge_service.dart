/// Writes behind "Find duplicates": one survivor, the rest closed.
///
/// Merging never deletes — closed items are the audit trail — so every
/// other member closes with a note naming the survivor, and the
/// survivor records what it absorbed (and its old wording, when the
/// merged statement is taken). A survivor can move register first
/// (an assumption kept as the dependency it really is) through the
/// conversion service, which keeps the row id so links still point at
/// it. All in one transaction. Cascade pushes are the caller's: they
/// need the UI's sync provider.
library;

import 'package:drift/drift.dart' show Value;

import '../database/database.dart';
import 'dependency_plan_link.dart';
import 'raid_conversion_service.dart';
import 'raid_duplicates.dart';
import 'raid_lifecycle.dart';

class MergeOutcome {
  final String survivorId;
  final RaidKind survivorKind;
  final String? survivorRef;
  /// (kind, id) of every member closed as a duplicate.
  final List<(RaidKind, String)> closed;
  const MergeOutcome({
    required this.survivorId,
    required this.survivorKind,
    required this.survivorRef,
    required this.closed,
  });
}

/// Every companion carries the current description: the DAO upserts are
/// insert-or-update, and the insert shape rejects an absent description.
class RaidMergeService {
  final AppDatabase db;
  final RaidConversionService _conversion;

  RaidMergeService(this.db, {RaidConversionService? conversion})
      : _conversion = conversion ?? RaidConversionService(db);

  /// Merges [group] into [survivor]. [keepAs] is the register the
  /// survivor ends up in (one of the members' kinds). [mergedDescription],
  /// when given and different, replaces the survivor's wording.
  Future<MergeOutcome> merge({
    required DuplicateGroup group,
    required DuplicateItem survivor,
    required RaidKind keepAs,
    String? mergedDescription,
    DateTime? now,
  }) async {
    assert(group.members.any((m) => m.id == survivor.id),
        'survivor must be a member of the group');
    assert(group.members.any((m) => m.kind == keepAs),
        'keepAs must be one of the members\' registers');
    final when = now ?? DateTime.now();
    final others = group.members.where((m) => m.id != survivor.id).toList();

    var kind = survivor.kind;
    String? ref = survivor.ref;
    late final String survivorLabel;

    // One transaction: the register move (the conversion service's own
    // transaction nests inside), the survivor's note, the closures. A
    // failure anywhere leaves the register as it was.
    await db.transaction(() async {
      if (keepAs != kind) {
        ref = await _conversion.convert(id: survivor.id, from: kind, to: keepAs);
        kind = keepAs;
      }
      survivorLabel =
          ref == null || ref!.isEmpty ? kind.label : '${kind.label} $ref';
      await _annotateSurvivor(
        kind: kind,
        id: survivor.id,
        absorbed: [for (final o in others) o.label],
        mergedDescription: mergedDescription,
        when: when,
      );
      for (final o in others) {
        await _closeAsDuplicate(o, survivorLabel: survivorLabel, when: when);
      }
    });

    return MergeOutcome(
      survivorId: survivor.id,
      survivorKind: kind,
      survivorRef: ref,
      closed: [for (final o in others) (o.kind, o.id)],
    );
  }

  Future<void> _annotateSurvivor({
    required RaidKind kind,
    required String id,
    required List<String> absorbed,
    required String? mergedDescription,
    required DateTime when,
  }) async {
    String? newText(String current) {
      final t = mergedDescription?.trim() ?? '';
      return t.isEmpty || t == current.trim() ? null : t;
    }

    switch (kind) {
      case RaidKind.risk:
        final r = await db.raidDao.getRiskById(id);
        if (r == null) return;
        final text = newText(r.description);
        await db.raidDao.upsertRisk(RisksCompanion(
          id: Value(r.id),
          projectId: Value(r.projectId),
          description: Value(text ?? r.description),
          sourceNote: Value(mergeSurvivorNote(
            existingSourceNote: r.sourceNote,
            absorbedLabels: absorbed,
            previousDescription: text == null ? null : r.description,
            when: when,
          )),
          updatedAt: Value(when),
        ));
      case RaidKind.assumption:
        final a = await db.raidDao.getAssumptionById(id);
        if (a == null) return;
        final text = newText(a.description);
        await db.raidDao.upsertAssumption(AssumptionsCompanion(
          id: Value(a.id),
          projectId: Value(a.projectId),
          description: Value(text ?? a.description),
          sourceNote: Value(mergeSurvivorNote(
            existingSourceNote: a.sourceNote,
            absorbedLabels: absorbed,
            previousDescription: text == null ? null : a.description,
            when: when,
          )),
          updatedAt: Value(when),
        ));
      case RaidKind.issue:
        final i = await db.raidDao.getIssueById(id);
        if (i == null) return;
        final text = newText(i.description);
        await db.raidDao.upsertIssue(IssuesCompanion(
          id: Value(i.id),
          projectId: Value(i.projectId),
          description: Value(text ?? i.description),
          sourceNote: Value(mergeSurvivorNote(
            existingSourceNote: i.sourceNote,
            absorbedLabels: absorbed,
            previousDescription: text == null ? null : i.description,
            when: when,
          )),
          updatedAt: Value(when),
        ));
      case RaidKind.dependency:
        final d = await db.raidDao.getDependencyById(id);
        if (d == null) return;
        final text = newText(d.description);
        await db.raidDao.upsertDependency(ProgramDependenciesCompanion(
          id: Value(d.id),
          projectId: Value(d.projectId),
          description: Value(text ?? d.description),
          sourceNote: Value(mergeSurvivorNote(
            existingSourceNote: d.sourceNote,
            absorbedLabels: absorbed,
            previousDescription: text == null ? null : d.description,
            when: when,
          )),
          updatedAt: Value(when),
        ));
      case RaidKind.decision:
        throw UnsupportedError('Decisions are not part of the duplicate check');
    }
  }

  Future<void> _closeAsDuplicate(
    DuplicateItem o, {
    required String survivorLabel,
    required DateTime when,
  }) async {
    Value<String?> closedAt(String? existing) => Value(nextClosedAt(
          kind: o.kind,
          newStatus: 'closed',
          existing: existing,
          today: when,
        ));
    switch (o.kind) {
      case RaidKind.risk:
        final r = await db.raidDao.getRiskById(o.id);
        if (r == null) return;
        await db.raidDao.upsertRisk(RisksCompanion(
          id: Value(r.id),
          projectId: Value(r.projectId),
          description: Value(r.description),
          status: const Value('closed'),
          closedAt: closedAt(r.closedAt),
          sourceNote: Value(mergeClosedNote(
            existingSourceNote: r.sourceNote,
            survivorLabel: survivorLabel,
            when: when,
          )),
          updatedAt: Value(when),
        ));
      case RaidKind.assumption:
        final a = await db.raidDao.getAssumptionById(o.id);
        if (a == null) return;
        await db.raidDao.upsertAssumption(AssumptionsCompanion(
          id: Value(a.id),
          projectId: Value(a.projectId),
          description: Value(a.description),
          status: const Value('closed'),
          closedAt: closedAt(a.closedAt),
          sourceNote: Value(mergeClosedNote(
            existingSourceNote: a.sourceNote,
            survivorLabel: survivorLabel,
            when: when,
          )),
          updatedAt: Value(when),
        ));
      case RaidKind.issue:
        final i = await db.raidDao.getIssueById(o.id);
        if (i == null) return;
        await db.raidDao.upsertIssue(IssuesCompanion(
          id: Value(i.id),
          projectId: Value(i.projectId),
          description: Value(i.description),
          status: const Value('closed'),
          closedAt: closedAt(i.closedAt),
          sourceNote: Value(mergeClosedNote(
            existingSourceNote: i.sourceNote,
            survivorLabel: survivorLabel,
            when: when,
          )),
          updatedAt: Value(when),
        ));
      case RaidKind.dependency:
        final d = await db.raidDao.getDependencyById(o.id);
        if (d == null) return;
        await db.raidDao.upsertDependency(ProgramDependenciesCompanion(
          id: Value(d.id),
          projectId: Value(d.projectId),
          description: Value(d.description),
          status: const Value('closed'),
          closedAt: closedAt(d.closedAt),
          sourceNote: Value(mergeClosedNote(
            existingSourceNote: d.sourceNote,
            survivorLabel: survivorLabel,
            when: when,
          )),
          updatedAt: Value(when),
        ));
        // A closed dependency no longer gates anything: its arrow comes
        // off the Gantt, as it does when a form closes it.
        await DependencyPlanLink.remove(db, d.projectId, d.id);
      case RaidKind.decision:
        throw UnsupportedError('Decisions are not part of the duplicate check');
    }
  }
}
