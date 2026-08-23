import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/seed/seed_service.dart';

void main() {
  late AppDatabase db;
  const pid = 'seed-horizon-001';

  setUp(() async {
    db = AppDatabase.memory();
    await SeedService.seedDemoProject(db);
  });
  tearDown(() async => db.close());

  group('SeedService — finance', () {
    test('seeds the five default categories', () async {
      final cats = await db.financeDao.getCategories(pid);
      expect(cats.map((c) => c.name).toList(),
          ['People', 'Vendor', 'Technology', 'Other', 'Contingency']);
    });

    test('approved re-baseline totals exactly £42.0M', () async {
      final approved = await db.financeDao.getApprovedBudget(pid);
      expect(approved, isNotNull);
      expect(approved!.name, contains('Re-baseline'));
      expect(approved.currency, 'GBP');
      expect(approved.approvedBy, 'Richard Okafor');
      final totals = await db.financeDao.getTotals(approved.id);
      expect(totals.totalMinor, 4200000000); // £42,000,000.00 in pence
    });

    test('original business case is superseded at exactly £40.0M', () async {
      final budgets = await db.financeDao.getBudgets(pid);
      expect(budgets.length, 3);
      final v1 = budgets.firstWhere((b) => b.status == 'superseded');
      expect(v1.name, contains('Original Business Case'));
      final totals = await db.financeDao.getTotals(v1.id);
      expect(totals.totalMinor, 4000000000); // £40,000,000.00 in pence
    });

    test('an editable working draft exists with FY27 extension lines',
        () async {
      final budgets = await db.financeDao.getBudgets(pid);
      final draft = budgets.firstWhere((b) => b.status == 'draft');
      expect(draft.name, contains('FY27'));
      final lines = await db.financeDao.getLines(draft.id);
      // Copy of the approved v2 (11 lines) + two FY27 extension lines.
      expect(lines.length, 13);
      expect(lines.where((l) => l.financialYear == 'FY27').length, 2);
      final totals = await db.financeDao.getTotals(draft.id);
      // £42.0M + £1.2M + £0.6M
      expect(totals.totalMinor, 4380000000);
    });

    test('audit trail includes the People FY26 correction and both approvals',
        () async {
      final log = await db.financeDao.getAuditLog(pid);
      final correction = log.where((e) =>
          e.field == 'amountMinor' &&
          e.oldValue == '${7400000 * 100}' &&
          e.newValue == '${7600000 * 100}');
      expect(correction.length, 1);
      final approvals = log.where(
          (e) => e.field == 'status' && e.newValue == 'approved');
      expect(approvals.length, 2);
      final supersessions = log.where(
          (e) => e.field == 'status' && e.newValue == 'superseded');
      expect(supersessions.length, 1);
    });

    test('forecast: 3 submitted months + working July breaching tolerance',
        () async {
      final snaps = await db.financeDao.getSnapshots(pid);
      expect(snaps.length, 4);
      expect(snaps.where((s) => s.status == 'submitted').length, 3);
      final working = snaps.firstWhere((s) => s.status == 'working');
      expect(working.period, '2026-07');
      final julTotals = await db.financeDao.getForecastTotals(working.id);
      expect(julTotals.totalMinor, 4420000000); // £44.2M

      // +2.2M on 42.0M = 523.8bp → 524, beyond the 500bp tolerance.
      final approved = await db.financeDao.getApprovedBudget(pid);
      final budgetTotals = await db.financeDao.getTotals(approved!.id);
      expect(budgetTotals.totalMinor, 4200000000);
      expect(approved.varianceToleranceBp, 500);

      final trend = await db.financeDao.getForecastTrend(pid);
      expect(trend.map((t) => t.totalMinor).toList(),
          [4200000000, 4230000000, 4290000000, 4420000000]);
    });

    test('actuals: six months of manual entries with audit trail',
        () async {
      final actuals = await db.financeDao.getActuals(pid);
      expect(actuals.length, 24); // 6 months × 4 categories
      final totals = await db.financeDao.getActualsTotals(pid);
      expect(totals.byFinancialYear.keys.length, 6); // keyed by period
      expect(totals.totalMinor, greaterThan(0));
      expect(actuals.every((a) => a.source == 'manual'), isTrue);
    });

    test('some lines carry workstream tags pointing at seeded WPs', () async {
      final approved = await db.financeDao.getApprovedBudget(pid);
      final lines = await db.financeDao.getLines(approved!.id);
      final wpIds = (await db.programmeGanttDao.getWorkPackages(pid))
          .map((wp) => wp.id)
          .toSet();
      final tagged =
          lines.where((l) => l.workstreamId != null).toList();
      expect(tagged, isNotEmpty);
      for (final l in tagged) {
        expect(wpIds, contains(l.workstreamId),
            reason: '${l.workstreamId} should be a seeded work package');
      }
    });
  });

  group('SeedService — canvas', () {
    test('seeds cards in all three bands with a sequence', () async {
      final cards = await db.canvasCardsDao.getCardsForProject(pid);
      expect(cards.map((c) => c.band).toSet(),
          {'this_week', 'next_30_days', 'horizon'});
      final seqs = await db.canvasCardsDao.getSequencesForProject(pid);
      expect(seqs, isNotEmpty);
      final cardIds = cards.map((c) => c.id).toSet();
      for (final s in seqs) {
        expect(cardIds, containsAll([s.fromCardId, s.toCardId]));
      }
    });

    test('seeds SWOT and pre-mortem template instances', () async {
      final templates =
          await db.canvasTemplatesDao.getTemplatesForProject(pid);
      expect(templates.map((t) => t.templateType).toSet(),
          containsAll({'swot', 'pre_mortem'}));
      for (final t in templates) {
        expect(t.content, isNot('{}'));
      }
    });
  });

  group('SeedService — journal series', () {
    test('steerco entries grouped into a series, one favourite', () async {
      final series = await db.journalSeriesDao.getForProject(pid);
      expect(series.length, 1);
      final entries =
          await db.journalDao.getEntriesForSeries(series.first.id);
      expect(entries.length, 2);
      final all = await db.journalDao.getEntriesForProject(pid);
      expect(all.where((e) => e.isFavourite).length, 1);
    });
  });
}
