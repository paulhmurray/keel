part of '../database.dart';

/// Canvas band identifiers. Stored as text in [CanvasCards.band]. Lives
/// outside the widget tree so DAO callers and the UI agree on the values.
class CanvasBands {
  static const thisWeek = 'this_week';
  static const next30Days = 'next_30_days';
  static const horizon = 'horizon';

  static const all = [thisWeek, next30Days, horizon];

  static String label(String band) {
    switch (band) {
      case thisWeek:
        return 'This Week';
      case next30Days:
        return 'Next 30 Days';
      case horizon:
        return 'Horizon';
      default:
        return band;
    }
  }
}

/// Card sizes. Stored as text in [CanvasCards.size]. Width × height in px:
/// small 200×120, medium 240×160, large 280×220.
class CanvasCardSize {
  static const small = 'small';
  static const medium = 'medium';
  static const large = 'large';

  static const all = [small, medium, large];
}

/// Linked-item types — matches the formal item kinds Canvas can reference.
/// 'journal' is link-only (a Canvas card surfacing a journal extract);
/// it cannot be a promotion target.
class CanvasLinkType {
  static const risk = 'risk';
  static const assumption = 'assumption';
  static const issue = 'issue';
  static const dependency = 'dependency';
  static const decision = 'decision';
  static const action = 'action';
  static const milestone = 'milestone';
  static const activity = 'activity';
  static const journal = 'journal';

  static const promotable = [
    risk,
    assumption,
    issue,
    dependency,
    decision,
    action,
    milestone,
    activity,
  ];
}

@DriftAccessor(tables: [CanvasCards, CanvasSequences])
class CanvasCardsDao extends DatabaseAccessor<AppDatabase>
    with _$CanvasCardsDaoMixin {
  CanvasCardsDao(super.db);

  // ---- Cards ---------------------------------------------------------------

  Stream<List<CanvasCard>> watchCardsForProject(String projectId) {
    return (select(canvasCards)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.band),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Future<List<CanvasCard>> getCardsForProject(String projectId) {
    return (select(canvasCards)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
  }

  Stream<List<CanvasCard>> watchCardsForBand(
      String projectId, String band) {
    return (select(canvasCards)
          ..where((t) =>
              t.projectId.equals(projectId) & t.band.equals(band))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<CanvasCard?> getCardById(String id) {
    return (select(canvasCards)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertCard(CanvasCardsCompanion entry) {
    return into(canvasCards).insert(entry);
  }

  Future<bool> updateCard(CanvasCardsCompanion entry) {
    return update(canvasCards).replace(entry);
  }

  Future<int> patchCard(String id, CanvasCardsCompanion patch) {
    final withTimestamp = patch.copyWith(updatedAt: Value(DateTime.now()));
    return (update(canvasCards)..where((t) => t.id.equals(id)))
        .write(withTimestamp);
  }

  Future<void> deleteCard(String id) async {
    await transaction(() async {
      await (delete(canvasSequences)
            ..where((t) =>
                t.fromCardId.equals(id) | t.toCardId.equals(id)))
          .go();
      await (delete(canvasCards)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Find any card in [projectId] that links to the given formal item.
  /// Used by source modules to render the "In Canvas" indicator.
  Future<CanvasCard?> findCardLinkedTo({
    required String projectId,
    required String itemType,
    required String itemId,
  }) {
    return (select(canvasCards)
          ..where((t) =>
              t.projectId.equals(projectId) &
              t.linkedItemType.equals(itemType) &
              t.linkedItemId.equals(itemId))
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<CanvasCard?> watchCardLinkedTo({
    required String projectId,
    required String itemType,
    required String itemId,
  }) {
    return (select(canvasCards)
          ..where((t) =>
              t.projectId.equals(projectId) &
              t.linkedItemType.equals(itemType) &
              t.linkedItemId.equals(itemId))
          ..limit(1))
        .watchSingleOrNull();
  }

  // ---- Sequences (arrows between cards) -----------------------------------

  Stream<List<CanvasSequence>> watchSequencesForProject(String projectId) {
    return (select(canvasSequences)
          ..where((t) => t.projectId.equals(projectId)))
        .watch();
  }

  /// One-shot read of a project's sequences — used by sync export.
  Future<List<CanvasSequence>> getSequencesForProject(String projectId) {
    return (select(canvasSequences)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
  }

  Future<void> addSequence({
    required String id,
    required String projectId,
    required String fromCardId,
    required String toCardId,
  }) {
    if (fromCardId == toCardId) return Future.value();
    return into(canvasSequences).insertOnConflictUpdate(
      CanvasSequencesCompanion.insert(
        id: id,
        projectId: projectId,
        fromCardId: fromCardId,
        toCardId: toCardId,
      ),
    );
  }

  Future<int> deleteSequence(String id) {
    return (delete(canvasSequences)..where((t) => t.id.equals(id))).go();
  }

  Future<int> deleteSequenceBetween(String fromCardId, String toCardId) {
    return (delete(canvasSequences)
          ..where((t) =>
              t.fromCardId.equals(fromCardId) &
              t.toCardId.equals(toCardId)))
        .go();
  }

  // ---- Tags ---------------------------------------------------------------

  /// Watches all cards for [projectId] and emits a map of tag → card
  /// count, sorted alphabetically by tag. Used by the filter popup to
  /// surface available tags with their occurrence count.
  ///
  /// Tag JSON parsing is done in Dart (Drift has no JSON type); for
  /// typical project sizes (< a few hundred cards) this is plenty fast.
  Stream<Map<String, int>> watchTagCountsForProject(String projectId) {
    return watchCardsForProject(projectId).map((cards) {
      final counts = <String, int>{};
      for (final c in cards) {
        for (final tag in _decodeTagsRaw(c.tags)) {
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      }
      final sortedKeys = counts.keys.toList()..sort();
      return {for (final k in sortedKeys) k: counts[k]!};
    });
  }

  /// One-shot variant of [watchTagCountsForProject]. Returns the same
  /// map computed against the current state of the DB.
  Future<Map<String, int>> getTagCountsForProject(String projectId) async {
    final cards = await getCardsForProject(projectId);
    final counts = <String, int>{};
    for (final c in cards) {
      for (final tag in _decodeTagsRaw(c.tags)) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final sortedKeys = counts.keys.toList()..sort();
    return {for (final k in sortedKeys) k: counts[k]!};
  }

  /// Minimal JSON-array parser scoped to the DAO so it doesn't pull in
  /// the feature-level CanvasTags helper from a core layer. Returns an
  /// empty list on null / empty / malformed input — never throws.
  List<String> _decodeTagsRaw(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } catch (_) {
      // Treat malformed payloads as no tags.
    }
    return const [];
  }
}
