import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import '../database/database.dart';
import 'journal_parser.dart';

class JournalLinker {
  final AppDatabase db;
  final String projectId;
  final String entryId;

  JournalLinker({
    required this.db,
    required this.projectId,
    required this.entryId,
  });

  Future<void> commitDeltas(List<DetectedDelta> deltas) async {
    for (final delta in deltas) {
      if (!delta.confirmed) continue;
      final itemId = await _createItem(delta);
      if (itemId != null) {
        await db.journalDao.insertLink(JournalEntryLinksCompanion(
          id: Value(const Uuid().v4()),
          entryId: Value(entryId),
          itemType: Value(_itemTypeName(delta.type)),
          itemId: Value(itemId),
          linkType: const Value('created'),
          createdAt: Value(DateTime.now()),
        ));
      }
    }
    // Mark entry as confirmed
    final existing = await db.journalDao.getEntryById(entryId);
    if (existing != null) {
      await db.journalDao.upsertEntry(JournalEntriesCompanion(
        id: Value(entryId),
        projectId: Value(projectId),
        title: Value(existing.title),
        body: Value(existing.body),
        entryDate: Value(existing.entryDate),
        meetingContext: Value(existing.meetingContext),
        parsed: const Value(true),
        confirmedAt: Value(DateTime.now()),
        createdAt: Value(existing.createdAt),
        updatedAt: Value(DateTime.now()),
      ));
    }
  }

  Future<String?> _createItem(DetectedDelta delta) async {
    final id = const Uuid().v4();
    final f = delta.editFields;

    switch (delta.type) {
      case DeltaType.action:
        final existing = await db.actionsDao.getActionsForProject(projectId);
        final nums = existing
            .where((a) => a.ref != null && a.ref!.startsWith('AC'))
            .map((a) => int.tryParse(a.ref!.substring(2)) ?? 0)
            .toList()..sort();
        final ref = 'AC${(nums.isEmpty ? 0 : nums.last) + 1}';
        await db.actionsDao.insertAction(ProjectActionsCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(f['description'] ?? delta.title),
          owner: Value(f['owner']),
          dueDate: Value(f['dueDate']),
          status: const Value('open'),
          priority: const Value('medium'),
          source: const Value('journal'),
          sourceNote: Value('From journal entry'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
        return id;

      case DeltaType.decision:
        final existing = await db.decisionsDao.getDecisionsForProject(projectId);
        final nums = existing
            .where((d) => d.ref != null && d.ref!.startsWith('DC'))
            .map((d) => int.tryParse(d.ref!.substring(2)) ?? 0)
            .toList()..sort();
        final ref = 'DC${(nums.isEmpty ? 0 : nums.last) + 1}';
        await db.decisionsDao.insertDecision(DecisionsCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(f['description'] ?? delta.title),
          decisionMaker: Value(f['decisionMaker']),
          status: const Value('decided'),
          source: const Value('journal'),
          sourceNote: Value('From journal entry'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
        return id;

      case DeltaType.risk:
        final existing = await db.raidDao.getRisksForProject(projectId);
        final nums = existing
            .where((r) => r.ref != null && r.ref!.startsWith('R'))
            .map((r) => int.tryParse(r.ref!.substring(1)) ?? 0)
            .toList()..sort();
        final ref = 'R${(nums.isEmpty ? 0 : nums.last) + 1}';
        await db.raidDao.insertRisk(RisksCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(f['description'] ?? delta.title),
          likelihood: Value(f['likelihood'] ?? 'medium'),
          impact: Value(f['impact'] ?? 'medium'),
          status: const Value('open'),
          source: const Value('journal'),
          sourceNote: Value('From journal entry'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
        return id;

      case DeltaType.issue:
        final existing = await db.raidDao.getIssuesForProject(projectId);
        final nums = existing
            .where((i) => i.ref != null && i.ref!.startsWith('I'))
            .map((i) => int.tryParse(i.ref!.substring(1)) ?? 0)
            .toList()..sort();
        final ref = 'I${(nums.isEmpty ? 0 : nums.last) + 1}';
        await db.raidDao.insertIssue(IssuesCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(f['description'] ?? delta.title),
          owner: Value(f['owner']),
          priority: Value(f['priority'] ?? 'medium'),
          status: const Value('open'),
          source: const Value('journal'),
          sourceNote: Value('From journal entry'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
        return id;

      case DeltaType.dependency:
        final existing = await db.raidDao.getDependenciesForProject(projectId);
        final nums = existing
            .where((d) => d.ref != null && d.ref!.startsWith('D'))
            .map((d) => int.tryParse(d.ref!.substring(1)) ?? 0)
            .toList()..sort();
        final ref = 'D${(nums.isEmpty ? 0 : nums.last) + 1}';
        await db.raidDao.insertDependency(ProgramDependenciesCompanion(
          id: Value(id),
          projectId: Value(projectId),
          ref: Value(ref),
          description: Value(f['description'] ?? delta.title),
          owner: Value(f['owner']),
          status: const Value('open'),
          source: const Value('journal'),
          sourceNote: Value('From journal entry'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
        return id;

      case DeltaType.timelineChange:
        // Timeline changes are stored as context entries
        await db.contextDao.insertEntry(ContextEntriesCompanion(
          id: Value(id),
          projectId: Value(projectId),
          title: Value(delta.title),
          content: Value(f['description'] ?? delta.title),
          entryType: const Value('timeline_change'),
          source: const Value('journal'),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
        return id;
    }
  }

  String _itemTypeName(DeltaType type) {
    switch (type) {
      case DeltaType.action: return 'action';
      case DeltaType.decision: return 'decision';
      case DeltaType.risk: return 'risk';
      case DeltaType.issue: return 'issue';
      case DeltaType.dependency: return 'dependency';
      case DeltaType.timelineChange: return 'timeline_change';
    }
  }
}
