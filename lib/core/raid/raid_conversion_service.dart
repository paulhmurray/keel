import 'package:drift/drift.dart';

import '../database/database.dart';

/// The five convertible item kinds. Enum names double as the type strings
/// stored in canvas/journal/inbox links ('risk', 'assumption', …).
enum RaidKind { risk, assumption, issue, dependency, decision }

extension RaidKindExt on RaidKind {
  String get label => switch (this) {
        RaidKind.risk => 'Risk',
        RaidKind.assumption => 'Assumption',
        RaidKind.issue => 'Issue',
        RaidKind.dependency => 'Dependency',
        RaidKind.decision => 'Decision',
      };

  String get refPrefix => switch (this) {
        RaidKind.risk => 'R',
        RaidKind.assumption => 'A',
        RaidKind.issue => 'I',
        RaidKind.dependency => 'D',
        RaidKind.decision => 'DC',
      };

  List<String> get statuses => switch (this) {
        RaidKind.risk => const ['open', 'in progress', 'closed', 'accepted'],
        RaidKind.assumption =>
          const ['open', 'validated', 'invalidated', 'closed'],
        RaidKind.issue => const ['open', 'in progress', 'resolved', 'closed'],
        RaidKind.dependency =>
          const ['open', 'in progress', 'resolved', 'closed', 'blocked'],
        RaidKind.decision =>
          const ['pending', 'approved', 'rejected', 'deferred', 'closed'],
      };
}

/// The type-agnostic view of a RAID item used as the conversion vehicle.
class _SourceFields {
  final String id;
  final String projectId;
  final String? ref;
  final String description;
  final String? owner;
  final String status;
  final String source;
  final String? sourceNote;
  final String? dueDate;
  final DateTime createdAt;
  final String? sourceProjectId;
  // Type-specific free text that has no column on other kinds; folded
  // into the conversion note so nothing is silently lost.
  final List<(String, String)> extras;

  const _SourceFields({
    required this.id,
    required this.projectId,
    required this.ref,
    required this.description,
    required this.owner,
    required this.status,
    required this.source,
    required this.sourceNote,
    required this.dueDate,
    required this.createdAt,
    required this.sourceProjectId,
    required this.extras,
  });
}

/// Converts a RAID item (or any of the four to a Decision) in place:
/// the row moves to the target table but KEEPS ITS ID, so canvas cards,
/// journal links and inbox links stay valid — only their stored type
/// string is rewritten. The item gets a fresh ref in the target sequence
/// and a provenance note; type-specific fields that have no home on the
/// target are appended to the note instead of being dropped.
class RaidConversionService {
  final AppDatabase db;

  RaidConversionService(this.db);

  /// Returns the new ref (e.g. 'I7'). Throws [StateError] for items
  /// cascaded in from another project — those are read-only here.
  Future<String> convert({
    required String id,
    required RaidKind from,
    required RaidKind to,
  }) async {
    assert(from != to);
    assert(from != RaidKind.decision, 'decisions are not converted from');

    final src = await _loadSource(id, from);
    if (src == null) {
      throw StateError('${from.label} $id not found');
    }
    if (src.sourceProjectId != null) {
      throw StateError('Cascaded items are read-only and cannot convert');
    }

    return db.transaction(() async {
      final newRef = await _nextRef(to, src.projectId);
      final now = DateTime.now();

      // Provenance + preserved leftovers, appended to the source note.
      final noteParts = <String>[
        if (src.sourceNote != null && src.sourceNote!.isNotEmpty)
          src.sourceNote!,
        'Converted from ${from.label.toLowerCase()} ${src.ref ?? ''}'.trim(),
        for (final (label, text) in src.extras) '$label: $text',
      ];
      final note = noteParts.join(' · ');

      final status = to.statuses.contains(src.status)
          ? src.status
          : (src.status == 'closed' ? 'closed' : to.statuses.first);

      await _insertTarget(to, src, newRef, note, status, now);
      await _deleteSource(from, id);
      await _rewriteLinks(id, to, now);
      return newRef;
    });
  }

  Future<_SourceFields?> _loadSource(String id, RaidKind from) async {
    switch (from) {
      case RaidKind.risk:
        final r = await db.raidDao.getRiskById(id);
        if (r == null) return null;
        return _SourceFields(
          id: r.id,
          projectId: r.projectId,
          ref: r.ref,
          description: r.description,
          owner: r.owner,
          status: r.status,
          source: r.source,
          sourceNote: r.sourceNote,
          dueDate: null,
          createdAt: r.createdAt,
          sourceProjectId: r.sourceProjectId,
          extras: [
            if (r.mitigation?.isNotEmpty ?? false)
              ('Mitigation', r.mitigation!),
            if (r.likelihoodRationale?.isNotEmpty ?? false)
              ('Likelihood rationale', r.likelihoodRationale!),
            if (r.impactRationale?.isNotEmpty ?? false)
              ('Impact rationale', r.impactRationale!),
          ],
        );
      case RaidKind.assumption:
        final a = await db.raidDao.getAssumptionById(id);
        if (a == null) return null;
        return _SourceFields(
          id: a.id,
          projectId: a.projectId,
          ref: a.ref,
          description: a.description,
          owner: a.owner,
          status: a.status,
          source: a.source,
          sourceNote: a.sourceNote,
          dueDate: null,
          createdAt: a.createdAt,
          sourceProjectId: a.sourceProjectId,
          extras: [
            if (a.validatedBy?.isNotEmpty ?? false)
              ('Validated by', a.validatedBy!),
          ],
        );
      case RaidKind.issue:
        final i = await db.raidDao.getIssueById(id);
        if (i == null) return null;
        return _SourceFields(
          id: i.id,
          projectId: i.projectId,
          ref: i.ref,
          description: i.description,
          owner: i.owner,
          status: i.status,
          source: i.source,
          sourceNote: i.sourceNote,
          dueDate: i.dueDate,
          createdAt: i.createdAt,
          sourceProjectId: i.sourceProjectId,
          extras: [
            if (i.title?.isNotEmpty ?? false) ('Title', i.title!),
            if (i.impactStatement?.isNotEmpty ?? false)
              ('Impact', i.impactStatement!),
            if (i.resolution?.isNotEmpty ?? false)
              ('Resolution', i.resolution!),
          ],
        );
      case RaidKind.dependency:
        final d = await db.raidDao.getDependencyById(id);
        if (d == null) return null;
        return _SourceFields(
          id: d.id,
          projectId: d.projectId,
          ref: d.ref,
          description: d.description,
          owner: d.owner,
          status: d.status,
          source: d.source,
          sourceNote: d.sourceNote,
          dueDate: d.dueDate,
          createdAt: d.createdAt,
          sourceProjectId: d.sourceProjectId,
          extras: const [],
        );
      case RaidKind.decision:
        return null;
    }
  }

  Future<void> _insertTarget(RaidKind to, _SourceFields src, String ref,
      String note, String status, DateTime now) async {
    final noteValue = Value<String?>(note.isEmpty ? null : note);
    switch (to) {
      case RaidKind.risk:
        await db.raidDao.insertRisk(RisksCompanion(
          id: Value(src.id),
          projectId: Value(src.projectId),
          ref: Value(ref),
          description: Value(src.description),
          owner: Value(src.owner),
          status: Value(status),
          source: Value(src.source),
          sourceNote: noteValue,
          createdAt: Value(src.createdAt),
          updatedAt: Value(now),
        ));
      case RaidKind.assumption:
        await db.raidDao.insertAssumption(AssumptionsCompanion(
          id: Value(src.id),
          projectId: Value(src.projectId),
          ref: Value(ref),
          description: Value(src.description),
          owner: Value(src.owner),
          status: Value(status),
          source: Value(src.source),
          sourceNote: noteValue,
          createdAt: Value(src.createdAt),
          updatedAt: Value(now),
        ));
      case RaidKind.issue:
        await db.raidDao.insertIssue(IssuesCompanion(
          id: Value(src.id),
          projectId: Value(src.projectId),
          ref: Value(ref),
          description: Value(src.description),
          owner: Value(src.owner),
          dueDate: Value(src.dueDate),
          status: Value(status),
          source: Value(src.source),
          sourceNote: noteValue,
          createdAt: Value(src.createdAt),
          updatedAt: Value(now),
        ));
      case RaidKind.dependency:
        await db.raidDao.insertDependency(ProgramDependenciesCompanion(
          id: Value(src.id),
          projectId: Value(src.projectId),
          ref: Value(ref),
          description: Value(src.description),
          owner: Value(src.owner),
          dueDate: Value(src.dueDate),
          status: Value(status),
          source: Value(src.source),
          sourceNote: noteValue,
          createdAt: Value(src.createdAt),
          updatedAt: Value(now),
        ));
      case RaidKind.decision:
        await db.decisionsDao.insertDecision(DecisionsCompanion(
          id: Value(src.id),
          projectId: Value(src.projectId),
          ref: Value(ref),
          description: Value(src.description),
          decisionMaker: Value(src.owner),
          dueDate: Value(src.dueDate),
          status: Value(status),
          source: Value(src.source),
          sourceNote: noteValue,
          createdAt: Value(src.createdAt),
          updatedAt: Value(now),
        ));
    }
  }

  Future<void> _deleteSource(RaidKind from, String id) async {
    switch (from) {
      case RaidKind.risk:
        await db.raidDao.deleteRisk(id);
      case RaidKind.assumption:
        await db.raidDao.deleteAssumption(id);
      case RaidKind.issue:
        await db.raidDao.deleteIssue(id);
      case RaidKind.dependency:
        await db.raidDao.deleteDependency(id);
      case RaidKind.decision:
        throw StateError('decisions are not converted from');
    }
  }

  /// The row id is unchanged, so links keep pointing at it — only the
  /// stored type string needs to follow the item to its new table.
  Future<void> _rewriteLinks(String id, RaidKind to, DateTime now) async {
    await (db.update(db.canvasCards)
          ..where((t) => t.linkedItemId.equals(id)))
        .write(CanvasCardsCompanion(
      linkedItemType: Value(to.name),
      updatedAt: Value(now),
    ));
    await (db.update(db.canvasCards)
          ..where((t) => t.promotedToId.equals(id)))
        .write(CanvasCardsCompanion(
      promotedToType: Value(to.name),
      updatedAt: Value(now),
    ));
    await (db.update(db.journalEntryLinks)
          ..where((t) => t.itemId.equals(id)))
        .write(JournalEntryLinksCompanion(itemType: Value(to.name)));
    await (db.update(db.inboxItems)
          ..where((t) => t.linkedItemId.equals(id)))
        .write(InboxItemsCompanion(
      linkedItemType: Value(to.name),
      updatedAt: Value(now),
    ));
    await (db.update(db.raidItemLinks)..where((t) => t.fromId.equals(id)))
        .write(RaidItemLinksCompanion(fromType: Value(to.name)));
    await (db.update(db.raidItemLinks)..where((t) => t.toId.equals(id)))
        .write(RaidItemLinksCompanion(toType: Value(to.name)));
  }

  Future<String> _nextRef(RaidKind to, String projectId) async {
    final prefix = to.refPrefix;
    final refs = switch (to) {
      RaidKind.risk => (await db.raidDao.getRisksForProject(projectId))
          .map((r) => r.ref),
      RaidKind.assumption =>
        (await db.raidDao.getAssumptionsForProject(projectId))
            .map((a) => a.ref),
      RaidKind.issue =>
        (await db.raidDao.getIssuesForProject(projectId)).map((i) => i.ref),
      RaidKind.dependency =>
        (await db.raidDao.getDependenciesForProject(projectId))
            .map((d) => d.ref),
      RaidKind.decision =>
        (await db.decisionsDao.getDecisionsForProject(projectId))
            .map((d) => d.ref),
    };
    final nums = refs
        .whereType<String>()
        .where((r) => r.startsWith(prefix))
        .map((r) => int.tryParse(r.substring(prefix.length)) ?? 0)
        .toList()
      ..sort();
    return '$prefix${(nums.isEmpty ? 0 : nums.last) + 1}';
  }
}
