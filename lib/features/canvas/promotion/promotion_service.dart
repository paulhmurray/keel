import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';

/// Creates a formal programme item from a Canvas card. The card stays in
/// Canvas with `promotedAt` set, so the PM can see the provenance later
/// ("this risk started as a card in Canvas on 12 June").
class PromotionService {
  final AppDatabase db;
  PromotionService(this.db);

  /// Promote [card] into a formal item of [targetType] (one of
  /// [CanvasLinkType.promotable]). Returns the new item's id, or null if
  /// the target type isn't supported.
  Future<String?> promote({
    required CanvasCard card,
    required String targetType,
  }) async {
    final uuid = const Uuid();
    final now = DateTime.now();
    final id = uuid.v4();

    switch (targetType) {
      case CanvasLinkType.action:
        await db.actionsDao.insertAction(
          ProjectActionsCompanion.insert(
            id: id,
            projectId: card.projectId,
            description: _descriptionFor(card),
            source: const Value('canvas'),
          ),
        );
        break;
      case CanvasLinkType.decision:
        await db.decisionsDao.insertDecision(
          DecisionsCompanion.insert(
            id: id,
            projectId: card.projectId,
            description: _descriptionFor(card),
            source: const Value('canvas'),
          ),
        );
        break;
      case CanvasLinkType.risk:
        await db.raidDao.insertRisk(
          RisksCompanion.insert(
            id: id,
            projectId: card.projectId,
            description: _descriptionFor(card),
            source: const Value('canvas'),
          ),
        );
        break;
      case CanvasLinkType.assumption:
        await db.raidDao.insertAssumption(
          AssumptionsCompanion.insert(
            id: id,
            projectId: card.projectId,
            description: _descriptionFor(card),
            source: const Value('canvas'),
          ),
        );
        break;
      case CanvasLinkType.issue:
        await db.raidDao.insertIssue(
          IssuesCompanion.insert(
            id: id,
            projectId: card.projectId,
            description: _descriptionFor(card),
            source: const Value('canvas'),
          ),
        );
        break;
      case CanvasLinkType.dependency:
        await db.raidDao.insertDependency(
          ProgramDependenciesCompanion.insert(
            id: id,
            projectId: card.projectId,
            description: _descriptionFor(card),
            source: const Value('canvas'),
          ),
        );
        break;
      case CanvasLinkType.milestone:
        await db.milestonesDao.upsert(
          MilestonesCompanion.insert(
            id: id,
            projectId: card.projectId,
            name: card.title,
            date: now.toIso8601String().substring(0, 10),
            notes: Value(card.body),
          ),
        );
        break;
      case CanvasLinkType.activity:
        // Activities need a workstream — pick the first one in the project,
        // or skip promotion if none exists.
        final ws =
            await db.workstreamsDao.getForProject(card.projectId);
        if (ws.isEmpty) return null;
        final today = now.toIso8601String().substring(0, 10);
        await db.workstreamActivitiesDao.upsert(
          WorkstreamActivitiesCompanion.insert(
            id: id,
            workstreamId: ws.first.id,
            projectId: card.projectId,
            name: card.title,
            startDate: today,
            endDate: today,
            notes: Value(card.body),
          ),
        );
        break;
      default:
        return null;
    }

    await db.canvasCardsDao.patchCard(
      card.id,
      CanvasCardsCompanion(
        promotedAt: Value(now),
        promotedToType: Value(targetType),
        promotedToId: Value(id),
      ),
    );
    return id;
  }

  String _descriptionFor(CanvasCard card) {
    final body = card.body?.trim();
    if (body == null || body.isEmpty) return card.title;
    return '${card.title}\n\n$body';
  }

  /// Reverts a previously-promoted card. Clears the promotion fields
  /// (`promotedAt`, `promotedToType`, `promotedToId`) so the card returns
  /// to its un-promoted state and can be re-promoted later.
  ///
  /// When [deletePromotedItem] is true the formal item that promotion
  /// created is also removed from its source module. Use this when the
  /// promotion was premature; leave it false when the formal item has
  /// taken on a life of its own (comments, owner, edits) that you don't
  /// want to lose.
  ///
  /// No-op on cards that were never promoted. Returns true when the
  /// card's promotion state was cleared, false otherwise.
  Future<bool> revert(
    CanvasCard card, {
    bool deletePromotedItem = false,
  }) async {
    if (card.promotedAt == null) return false;
    if (deletePromotedItem &&
        card.promotedToType != null &&
        card.promotedToId != null) {
      await _deletePromotedItem(card.promotedToType!, card.promotedToId!);
    }
    await db.canvasCardsDao.patchCard(
      card.id,
      const CanvasCardsCompanion(
        promotedAt: Value(null),
        promotedToType: Value(null),
        promotedToId: Value(null),
      ),
    );
    return true;
  }

  Future<void> _deletePromotedItem(String type, String id) async {
    switch (type) {
      case CanvasLinkType.action:
        await db.actionsDao.deleteAction(id);
        break;
      case CanvasLinkType.decision:
        await db.decisionsDao.deleteDecision(id);
        break;
      case CanvasLinkType.risk:
        await db.raidDao.deleteRisk(id);
        break;
      case CanvasLinkType.assumption:
        await db.raidDao.deleteAssumption(id);
        break;
      case CanvasLinkType.issue:
        await db.raidDao.deleteIssue(id);
        break;
      case CanvasLinkType.dependency:
        await db.raidDao.deleteDependency(id);
        break;
      case CanvasLinkType.milestone:
        await db.milestonesDao.deleteMilestone(id);
        break;
      case CanvasLinkType.activity:
        await db.workstreamActivitiesDao.deleteActivity(id);
        break;
    }
  }
}
