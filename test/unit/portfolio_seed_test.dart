import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/portfolio/programme_pulse.dart';
import 'package:keel/core/seed/portfolio_seed_service.dart';

/// The PMO demo seeds a full tree and cascades it, so the portfolio page
/// has something to argue with the moment it opens.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('seeds portfolio → 3 programmes → 7 projects, all linked', () async {
    expect(await PortfolioSeedService.seed(db), PortfolioSeedOutcome.created);
    final all = await db.projectDao.getAllProjects();
    expect(all.where((p) => p.kind == 'portfolio'), hasLength(1));
    expect(all.where((p) => p.kind == 'programme'), hasLength(3));
    expect(all.where((p) => p.kind == 'project'), hasLength(7));

    final portLinks = await db.programmeLinksDao
        .getLinksForEntity(PortfolioSeedService.portfolioId);
    expect(portLinks.where((l) => l.status == 'active'), hasLength(3));
    for (final prog in all.where((p) => p.kind == 'programme')) {
      final down =
          await db.programmeLinksDao.getProjectLinksForProgramme(prog.id);
      expect(down, isNotEmpty, reason: '${prog.name} has linked projects');
    }
  });

  test('cascade pass lands a pulse per programme with the intended profiles',
      () async {
    await PortfolioSeedService.seed(db);
    final rows = await db.portfolioPulsesDao
        .getLatestPerProgramme(PortfolioSeedService.portfolioId);
    expect(rows, hasLength(3));
    final byName = {
      for (final r in rows)
        r.sourceProgrammeName!: ProgrammePulse.fromJson(
            (jsonDecode(r.payload) as Map).cast<String, dynamic>()),
    };

    final channels = byName['Customer Channels']!;
    expect(channels.health.computedRag, 'red');
    expect(channels.health.reportedRag, 'green');
    expect(channels.health.watermelon, isTrue);
    expect(channels.decisions.pastNeedBy, greaterThanOrEqualTo(3));
    expect(channels.finance?.breachingProjects, 1);
    expect(channels.raid.escalatedOpen, greaterThan(0));

    final core = byName['Core Banking Modernisation']!;
    expect(core.health.computedRag, 'amber');
    expect(core.health.reportedRag, 'amber');
    expect(core.health.watermelon, isFalse);
    expect(core.flow.projectsLinked, 3);
    expect(core.finance?.breachingProjects, 0);

    final reg = byName['Regulatory & Risk Uplift']!;
    expect(reg.health.computedRag, 'green');
    expect(reg.completeness.score, 100);

    // Marcus Webb sits on projects in every programme; within Core Banking
    // alone he is on all three.
    expect(core.flow.maxProjectsPerPerson, 3);
    expect(core.flow.topLoaded.first.name, 'Marcus Webb');
  });

  test('backfills weekly history behind the live pulse, drifting organically',
      () async {
    await PortfolioSeedService.seed(db);
    final history = await db.portfolioPulsesDao
        .getHistory(PortfolioSeedService.portfolioId, 'seed-prog-ch');
    expect(history, hasLength(PortfolioSeedService.historyWeeks + 1));
    final weeks = history.map((r) => r.weekOf).toList();
    expect(weeks, [...weeks]..sort(), reason: 'oldest first');
    expect(weeks.toSet(), hasLength(weeks.length), reason: 'one row per week');
    expect(history.every((r) => r.linkCode != null), isTrue);
    // Customer Channels gets worse over time: decisions slip past need-by
    // as the weeks go on, never the other way.
    final pastNeedBy = history
        .map((r) => ProgrammePulse.fromJson(
                (jsonDecode(r.payload) as Map).cast<String, dynamic>())
            .decisions
            .pastNeedBy)
        .toList();
    for (var i = 1; i < pastNeedBy.length; i++) {
      expect(pastNeedBy[i], greaterThanOrEqualTo(pastNeedBy[i - 1]));
    }
    expect(pastNeedBy.last, greaterThan(pastNeedBy.first));
  });

  test('is idempotent: a second call does nothing', () async {
    expect(await PortfolioSeedService.seed(db), PortfolioSeedOutcome.created);
    expect(await PortfolioSeedService.seed(db), PortfolioSeedOutcome.unchanged);
    expect((await db.projectDao.getAllProjects()), hasLength(11));
  });

  test('an already-loaded demo without history gets it backfilled in place',
      () async {
    await PortfolioSeedService.seed(db);
    // Simulate a demo seeded by the older build: live pulses only.
    final liveWeek = (await db.portfolioPulsesDao
            .getLatestPerProgramme(PortfolioSeedService.portfolioId))
        .first
        .weekOf;
    await (db.delete(db.portfolioPulses)
          ..where((t) => t.weekOf.isNotValue(liveWeek)))
        .go();
    expect(
        await db.portfolioPulsesDao.getHistory(PortfolioSeedService.portfolioId, 'seed-prog-ch'),
        hasLength(1));
    expect(await PortfolioSeedService.seed(db), PortfolioSeedOutcome.backfilled);
    expect(
        await db.portfolioPulsesDao.getHistory(PortfolioSeedService.portfolioId, 'seed-prog-ch'),
        hasLength(PortfolioSeedService.historyWeeks + 1));
    expect(await PortfolioSeedService.seed(db), PortfolioSeedOutcome.unchanged);
  });

  test('a half-deleted demo (portfolio gone, programmes left) reseeds cleanly '
      'without doubling links', () async {
    await PortfolioSeedService.seed(db);
    await db.deleteProjectCascade(PortfolioSeedService.portfolioId);
    expect(await PortfolioSeedService.seed(db), PortfolioSeedOutcome.created);
    expect((await db.projectDao.getAllProjects()), hasLength(11));

    final portLinks = await db.programmeLinksDao
        .getLinksForEntity(PortfolioSeedService.portfolioId);
    expect(portLinks.where((l) => l.status == 'active'), hasLength(3));
    expect(portLinks, hasLength(3), reason: 'no stale rows from the first seed');
    expect(
        await db.programmeLinksDao.getProjectLinksForProgramme('seed-prog-cb'),
        hasLength(3));
    final rows = await db.portfolioPulsesDao
        .getLatestPerProgramme(PortfolioSeedService.portfolioId);
    final core = rows.firstWhere((r) => r.sourceProgrammeId == 'seed-prog-cb');
    final pulse = ProgrammePulse.fromJson(
        (jsonDecode(core.payload) as Map).cast<String, dynamic>());
    expect(pulse.flow.projectsLinked, 3);
    expect(await db.select(db.programmeLinks).get(), hasLength(20),
        reason: '7 project pairs + 3 portfolio pairs, two rows each');
  });
}
