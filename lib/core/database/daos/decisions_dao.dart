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

  // ── Escalation (Phase C.6) ────────────────────────────────────────────

  Future<void> setDecisionEscalated(String id, bool escalated) {
    return (update(decisions)..where((t) => t.id.equals(id))).write(
      DecisionsCompanion(
        escalatedAt: Value(escalated ? DateTime.now() : null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<Decision>> getEscalatedDecisionsForProject(
          String projectId) =>
      (select(decisions)
            ..where((t) =>
                t.projectId.equals(projectId) &
                t.escalatedAt.isNotNull() &
                t.sourceProjectId.isNull()))
          .get();

  /// Watches overdue cascaded decisions on a programme. "Overdue" here
  /// means status is still 'pending' AND dueDate < today — once a
  /// decision is approved / rejected / deferred / closed, it's been
  /// acted on (even 'deferred' = an explicit choice was made to push
  /// it back), so it no longer counts as overdue.
  Stream<List<Decision>> watchOverdueCascadedDecisionsForProgramme(
      String programmeId) {
    final today = _todayIso();
    return (select(decisions)
          ..where((t) =>
              t.projectId.equals(programmeId) &
              t.sourceProjectId.isNotNull() &
              t.dueDate.isNotNull() &
              t.dueDate.isSmallerThanValue(today) &
              t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .watch();
  }

  Future<List<Decision>> getOverdueCascadedDecisionsForProgramme(
      String programmeId) {
    final today = _todayIso();
    return (select(decisions)
          ..where((t) =>
              t.projectId.equals(programmeId) &
              t.sourceProjectId.isNotNull() &
              t.dueDate.isNotNull() &
              t.dueDate.isSmallerThanValue(today) &
              t.status.equals('pending')))
        .get();
  }

  String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
