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
    expect(await PortfolioSeedService.seed(db), isTrue);
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

  test('is idempotent: a second call does nothing', () async {
    expect(await PortfolioSeedService.seed(db), isTrue);
    expect(await PortfolioSeedService.seed(db), isFalse);
    expect((await db.projectDao.getAllProjects()), hasLength(11));
  });
}
