part of '../database.dart';

@DriftAccessor(tables: [Decisions])
class DecisionsDao extends DatabaseAccessor<AppDatabase>
    with _$DecisionsDaoMixin {
  DecisionsDao(super.db);

  Stream<List<Decision>> watchDecisionsForProject(String projectId) {
    return (select(decisions)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<Decision>> getDecisionsForProject(String projectId) {
    return (select(decisions)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Stream<List<Decision>> watchPendingDecisionsForProject(String projectId) {
    return (select(decisions)
          ..where((t) =>
              t.projectId.equals(projectId) & t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<Decision?> getDecisionById(String id) {
    return (select(decisions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertDecision(DecisionsCompanion entry) {
    return into(decisions).insert(entry);
  }

  Future<bool> updateDecision(DecisionsCompanion entry) {
    return update(decisions).replace(entry);
  }

  Future<int> deleteDecision(String id) {
    return (delete(decisions)..where((t) => t.id.equals(id))).go();
  }

  Future<void> upsertDecision(DecisionsCompanion entry) {
    return into(decisions).insertOnConflictUpdate(entry);
  }
}
