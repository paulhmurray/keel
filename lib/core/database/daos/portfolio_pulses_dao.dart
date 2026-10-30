part of '../database.dart';

/// Portfolio-side store for cascaded programme pulses. Rows are keyed per
/// programme per ISO week (the cascade item id), so the week's pulse is
/// replaced in place and history accrues one row a week.
@DriftAccessor(tables: [PortfolioPulses])
class PortfolioPulsesDao extends DatabaseAccessor<AppDatabase>
    with _$PortfolioPulsesDaoMixin {
  PortfolioPulsesDao(super.db);

  Future<void> upsert(PortfolioPulsesCompanion entry) =>
      into(portfolioPulses).insertOnConflictUpdate(entry);

  Future<void> deleteById(String id) =>
      (delete(portfolioPulses)..where((t) => t.id.equals(id))).go();

  /// Every pulse the portfolio holds, newest first.
  Future<List<PortfolioPulse>> getForPortfolio(String portfolioId) =>
      (select(portfolioPulses)
            ..where((t) => t.portfolioId.equals(portfolioId))
            ..orderBy([(t) => OrderingTerm.desc(t.capturedAt)]))
          .get();

  Stream<List<PortfolioPulse>> watchForPortfolio(String portfolioId) =>
      (select(portfolioPulses)
            ..where((t) => t.portfolioId.equals(portfolioId))
            ..orderBy([(t) => OrderingTerm.desc(t.capturedAt)]))
          .watch();

  /// The most recent pulse per programme. Pure reduction over
  /// [getForPortfolio] so the overview and tests share one definition.
  Future<List<PortfolioPulse>> getLatestPerProgramme(String portfolioId) async =>
      latestPerProgramme(await getForPortfolio(portfolioId));

  /// Weekly history for one programme, oldest first (for trends).
  Future<List<PortfolioPulse>> getHistory(
          String portfolioId, String programmeId) =>
      (select(portfolioPulses)
            ..where((t) =>
                t.portfolioId.equals(portfolioId) &
                t.sourceProgrammeId.equals(programmeId))
            ..orderBy([(t) => OrderingTerm.asc(t.weekOf)]))
          .get();

  /// Drops every pulse from [programmeId] — used when the link is revoked.
  Future<void> deleteForProgramme(String portfolioId, String programmeId) =>
      (delete(portfolioPulses)
            ..where((t) =>
                t.portfolioId.equals(portfolioId) &
                t.sourceProgrammeId.equals(programmeId)))
          .go();
}

/// Newest pulse per source programme from a newest-first list.
List<PortfolioPulse> latestPerProgramme(List<PortfolioPulse> all) {
  final seen = <String>{};
  final out = <PortfolioPulse>[];
  for (final p in all) {
    if (seen.add(p.sourceProgrammeId)) out.add(p);
  }
  out.sort((a, b) => (a.sourceProgrammeName ?? '')
      .toLowerCase()
      .compareTo((b.sourceProgrammeName ?? '').toLowerCase()));
  return out;
}
