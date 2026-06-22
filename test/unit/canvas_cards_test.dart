import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/promotion/promotion_service.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(
      ProjectsCompanion.insert(id: 'p1', name: 'P1'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<CanvasCard> insertCard({
    required String id,
    String band = CanvasBands.thisWeek,
    String title = 'A card',
    String? body,
    String? linkedType,
    String? linkedId,
  }) async {
    await db.canvasCardsDao.insertCard(
      CanvasCardsCompanion.insert(
        id: id,
        projectId: 'p1',
        title: title,
        body: Value(body),
        band: Value(band),
        linkedItemType: Value(linkedType),
        linkedItemId: Value(linkedId),
      ),
    );
    return (await db.canvasCardsDao.getCardById(id))!;
  }

  group('CanvasCardsDao', () {
    test('inserts and lists by project', () async {
      await insertCard(id: 'c1');
      await insertCard(id: 'c2', band: CanvasBands.horizon);
      final all = await db.canvasCardsDao.getCardsForProject('p1');
      expect(all.length, 2);
      expect(all.map((c) => c.id).toSet(), {'c1', 'c2'});
    });

    test('patchCard updates only the supplied fields and bumps updatedAt',
        () async {
      final before = await insertCard(id: 'c1', title: 'first');
      // Drift's currentDateAndTime is second-precision; sleep past it so
      // the bumped updatedAt is observably later.
      await Future.delayed(const Duration(milliseconds: 1100));
      await db.canvasCardsDao.patchCard(
        'c1',
        const CanvasCardsCompanion(title: Value('second')),
      );
      final after = await db.canvasCardsDao.getCardById('c1');
      expect(after!.title, 'second');
      expect(after.band, before.band);
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
    });

    test('deleteCard cascades to incoming and outgoing sequences', () async {
      await insertCard(id: 'a');
      await insertCard(id: 'b');
      await insertCard(id: 'c');
      await db.canvasCardsDao.addSequence(
        id: 's1', projectId: 'p1', fromCardId: 'a', toCardId: 'b');
      await db.canvasCardsDao.addSequence(
        id: 's2', projectId: 'p1', fromCardId: 'b', toCardId: 'c');
      await db.canvasCardsDao.deleteCard('b');

      final remainingCards =
          await db.canvasCardsDao.getCardsForProject('p1');
      expect(remainingCards.map((c) => c.id).toSet(), {'a', 'c'});

      final remainingSeqs = await db.select(db.canvasSequences).get();
      expect(remainingSeqs, isEmpty);
    });

    test('addSequence is idempotent on duplicate from/to with same id',
        () async {
      await insertCard(id: 'a');
      await insertCard(id: 'b');
      await db.canvasCardsDao.addSequence(
        id: 's1', projectId: 'p1', fromCardId: 'a', toCardId: 'b');
      await db.canvasCardsDao.addSequence(
        id: 's1', projectId: 'p1', fromCardId: 'a', toCardId: 'b');
      final seqs = await db.select(db.canvasSequences).get();
      expect(seqs.length, 1);
    });

    test('addSequence ignores self-loops', () async {
      await insertCard(id: 'a');
      await db.canvasCardsDao.addSequence(
        id: 's1', projectId: 'p1', fromCardId: 'a', toCardId: 'a');
      final seqs = await db.select(db.canvasSequences).get();
      expect(seqs, isEmpty);
    });

    test('findCardLinkedTo returns the linked card or null', () async {
      await insertCard(id: 'c1', linkedType: 'action', linkedId: 'AC1');
      final hit = await db.canvasCardsDao.findCardLinkedTo(
        projectId: 'p1', itemType: 'action', itemId: 'AC1');
      final miss = await db.canvasCardsDao.findCardLinkedTo(
        projectId: 'p1', itemType: 'action', itemId: 'AC99');
      expect(hit!.id, 'c1');
      expect(miss, isNull);
    });
  });

  group('PromotionService', () {
    test('promotes a card to an Action and marks the card promoted',
        () async {
      final card = await insertCard(
        id: 'c1',
        title: 'Ask Andrew about Jira',
        body: 'He owns admin',
      );
      final service = PromotionService(db);
      final newId =
          await service.promote(card: card, targetType: CanvasLinkType.action);
      expect(newId, isNotNull);

      final action = await db.actionsDao.getActionById(newId!);
      expect(action, isNotNull);
      expect(action!.description, contains('Ask Andrew about Jira'));
      expect(action.description, contains('He owns admin'));
      expect(action.source, 'canvas');

      final updated = await db.canvasCardsDao.getCardById('c1');
      expect(updated!.promotedAt, isNotNull);
      expect(updated.promotedToType, CanvasLinkType.action);
      expect(updated.promotedToId, newId);
    });

    test('promotes a card to a Risk', () async {
      final card = await insertCard(id: 'c1', title: 'M-POWER slip');
      final service = PromotionService(db);
      final newId =
          await service.promote(card: card, targetType: CanvasLinkType.risk);
      expect(newId, isNotNull);
      final risks = await db.raidDao.getRisksForProject('p1');
      expect(risks.length, 1);
      expect(risks.first.description, contains('M-POWER slip'));
      expect(risks.first.source, 'canvas');
    });

    test('promotes a card to a Milestone with today\'s date', () async {
      final card = await insertCard(id: 'c1', title: 'Budget board');
      final service = PromotionService(db);
      final newId = await service.promote(
          card: card, targetType: CanvasLinkType.milestone);
      expect(newId, isNotNull);
      final milestones = await db.milestonesDao.getForProject('p1');
      expect(milestones.length, 1);
      expect(milestones.first.name, 'Budget board');
      final today =
          DateTime.now().toIso8601String().substring(0, 10);
      expect(milestones.first.date, today);
    });

    test('activity promotion returns null when no workstream exists',
        () async {
      final card = await insertCard(id: 'c1', title: 'Some activity');
      final service = PromotionService(db);
      final newId = await service.promote(
          card: card, targetType: CanvasLinkType.activity);
      expect(newId, isNull);
      final reloaded = await db.canvasCardsDao.getCardById('c1');
      expect(reloaded!.promotedAt, isNull);
    });

    test('promotes to Assumption / Issue / Dependency / Decision', () async {
      final service = PromotionService(db);

      final cAss = await insertCard(id: 'a1', title: 'Vendor will renew');
      final cIss = await insertCard(id: 'i1', title: 'Test env broken');
      final cDep = await insertCard(id: 'd1', title: 'AWS quota uplift');
      final cDec = await insertCard(id: 'k1', title: 'Pick CI tool');

      final assId = await service.promote(
          card: cAss, targetType: CanvasLinkType.assumption);
      final issId = await service.promote(
          card: cIss, targetType: CanvasLinkType.issue);
      final depId = await service.promote(
          card: cDep, targetType: CanvasLinkType.dependency);
      final decId = await service.promote(
          card: cDec, targetType: CanvasLinkType.decision);

      expect(assId, isNotNull);
      expect(issId, isNotNull);
      expect(depId, isNotNull);
      expect(decId, isNotNull);

      final assumptions =
          await db.raidDao.getAssumptionsForProject('p1');
      final issues = await db.raidDao.getIssuesForProject('p1');
      final deps = await db.raidDao.getDependenciesForProject('p1');
      final decisions =
          await db.decisionsDao.getDecisionsForProject('p1');

      expect(assumptions.single.description, contains('Vendor will renew'));
      expect(assumptions.single.source, 'canvas');
      expect(issues.single.description, contains('Test env broken'));
      expect(deps.single.description, contains('AWS quota uplift'));
      expect(decisions.single.description, contains('Pick CI tool'));
    });

    test('activity promotion succeeds when a workstream exists', () async {
      await db.workstreamsDao.upsert(WorkstreamsCompanion.insert(
        id: 'ws1', projectId: 'p1', name: 'Build',
      ));
      final card = await insertCard(
          id: 'c1', title: 'Wire up CI', body: 'First pipeline');
      final service = PromotionService(db);
      final newId = await service.promote(
          card: card, targetType: CanvasLinkType.activity);
      expect(newId, isNotNull);

      final acts = await db.workstreamActivitiesDao.getForProject('p1');
      expect(acts.single.workstreamId, 'ws1');
      expect(acts.single.name, 'Wire up CI');
      expect(acts.single.notes, 'First pipeline');

      final updated = await db.canvasCardsDao.getCardById('c1');
      expect(updated!.promotedAt, isNotNull);
      expect(updated.promotedToType, CanvasLinkType.activity);
    });

    test('description format: "title\\n\\nbody" with body, title-only without',
        () async {
      final service = PromotionService(db);

      final withBody = await insertCard(
          id: 'a', title: 'Headline', body: 'More detail');
      final noBody = await insertCard(id: 'b', title: 'Just a title');

      final id1 = await service.promote(
          card: withBody, targetType: CanvasLinkType.action);
      final id2 = await service.promote(
          card: noBody, targetType: CanvasLinkType.action);

      final a1 = await db.actionsDao.getActionById(id1!);
      final a2 = await db.actionsDao.getActionById(id2!);
      expect(a1!.description, 'Headline\n\nMore detail');
      expect(a2!.description, 'Just a title');
    });

    test('blank-body card with whitespace-only body still title-only',
        () async {
      final card =
          await insertCard(id: 'a', title: 'T', body: '   \n  ');
      final service = PromotionService(db);
      final id = await service.promote(
          card: card, targetType: CanvasLinkType.action);
      final action = await db.actionsDao.getActionById(id!);
      expect(action!.description, 'T');
    });

    test('unknown target type returns null and does not mark promoted',
        () async {
      final card = await insertCard(id: 'a', title: 'Unknown target');
      final service = PromotionService(db);
      final id =
          await service.promote(card: card, targetType: 'not_a_real_type');
      expect(id, isNull);
      final reloaded = await db.canvasCardsDao.getCardById('a');
      expect(reloaded!.promotedAt, isNull);
      expect(reloaded.promotedToType, isNull);
    });
  });

  group('PromotionService.revert', () {
    test('clears promotion fields and leaves the action by default',
        () async {
      final card = await insertCard(id: 'c1', title: 'A move');
      final service = PromotionService(db);
      final actionId = await service.promote(
          card: card, targetType: CanvasLinkType.action);
      expect(actionId, isNotNull);

      final promoted = await db.canvasCardsDao.getCardById('c1');
      final ok = await service.revert(promoted!);
      expect(ok, isTrue);

      final reloaded = await db.canvasCardsDao.getCardById('c1');
      expect(reloaded!.promotedAt, isNull);
      expect(reloaded.promotedToType, isNull);
      expect(reloaded.promotedToId, isNull);

      // Action should still exist — unlink-only doesn't delete it.
      final action = await db.actionsDao.getActionById(actionId!);
      expect(action, isNotNull);
    });

    test(
        'with deletePromotedItem true: clears promotion fields and deletes '
        'the formal item', () async {
      final card = await insertCard(id: 'c1', title: 'Premature action');
      final service = PromotionService(db);
      final actionId = await service.promote(
          card: card, targetType: CanvasLinkType.action);
      expect(actionId, isNotNull);

      final promoted = await db.canvasCardsDao.getCardById('c1');
      final ok =
          await service.revert(promoted!, deletePromotedItem: true);
      expect(ok, isTrue);

      // Action is gone.
      final action = await db.actionsDao.getActionById(actionId!);
      expect(action, isNull);

      // And the card is back to a clean un-promoted state.
      final reloaded = await db.canvasCardsDao.getCardById('c1');
      expect(reloaded!.promotedAt, isNull);
      expect(reloaded.promotedToType, isNull);
      expect(reloaded.promotedToId, isNull);
    });

    test('deletes the right formal item across all promotable types',
        () async {
      final service = PromotionService(db);
      // Workstream needed for activity promotion.
      await db.workstreamsDao.upsert(WorkstreamsCompanion.insert(
        id: 'ws1', projectId: 'p1', name: 'Build',
      ));

      Future<void> promoteAndRevertDeleting(
        String id,
        String type,
      ) async {
        final card = await insertCard(id: id, title: 'card $id');
        final newId =
            await service.promote(card: card, targetType: type);
        expect(newId, isNotNull, reason: 'promotion to $type');
        final promoted = await db.canvasCardsDao.getCardById(id);
        final ok = await service.revert(promoted!, deletePromotedItem: true);
        expect(ok, isTrue, reason: 'revert($type)');
      }

      await promoteAndRevertDeleting('a1', CanvasLinkType.action);
      await promoteAndRevertDeleting('a2', CanvasLinkType.decision);
      await promoteAndRevertDeleting('a3', CanvasLinkType.risk);
      await promoteAndRevertDeleting('a4', CanvasLinkType.assumption);
      await promoteAndRevertDeleting('a5', CanvasLinkType.issue);
      await promoteAndRevertDeleting('a6', CanvasLinkType.dependency);
      await promoteAndRevertDeleting('a7', CanvasLinkType.milestone);
      await promoteAndRevertDeleting('a8', CanvasLinkType.activity);

      // No formal items left across the project.
      expect(
          (await db.actionsDao.getActionsForProject('p1')), isEmpty);
      expect(
          (await db.decisionsDao.getDecisionsForProject('p1')), isEmpty);
      expect((await db.raidDao.getRisksForProject('p1')), isEmpty);
      expect(
          (await db.raidDao.getAssumptionsForProject('p1')), isEmpty);
      expect((await db.raidDao.getIssuesForProject('p1')), isEmpty);
      expect(
          (await db.raidDao.getDependenciesForProject('p1')), isEmpty);
      expect((await db.milestonesDao.getForProject('p1')), isEmpty);
      expect(
          (await db.workstreamActivitiesDao.getForProject('p1')),
          isEmpty);
    });

    test('reverting an un-promoted card is a no-op', () async {
      final card = await insertCard(id: 'c1', title: 'never promoted');
      final service = PromotionService(db);
      final ok = await service.revert(card, deletePromotedItem: true);
      expect(ok, isFalse);
      final reloaded = await db.canvasCardsDao.getCardById('c1');
      expect(reloaded!.promotedAt, isNull);
    });

    test('a reverted card can be re-promoted', () async {
      final card = await insertCard(id: 'c1', title: 'redo');
      final service = PromotionService(db);
      await service.promote(card: card, targetType: CanvasLinkType.action);
      final firstPromoted = await db.canvasCardsDao.getCardById('c1');
      await service.revert(firstPromoted!, deletePromotedItem: true);

      final cleared = await db.canvasCardsDao.getCardById('c1');
      final secondId = await service.promote(
          card: cleared!, targetType: CanvasLinkType.risk);
      expect(secondId, isNotNull);
      final risks = await db.raidDao.getRisksForProject('p1');
      expect(risks.length, 1);
    });
  });

  group('CanvasCardsDao streams + isolation', () {
    test('watchCardsForProject is project-scoped', () async {
      await db.projectDao.insertProject(
        ProjectsCompanion.insert(id: 'p2', name: 'P2'),
      );
      await insertCard(id: 'a');
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'b', projectId: 'p2', title: 'other',
      ));
      final p1 = await db.canvasCardsDao.watchCardsForProject('p1').first;
      final p2 = await db.canvasCardsDao.watchCardsForProject('p2').first;
      expect(p1.map((c) => c.id), ['a']);
      expect(p2.map((c) => c.id), ['b']);
    });

    test('watchCardsForBand emits only the requested band', () async {
      await insertCard(id: 'tw', band: CanvasBands.thisWeek);
      await insertCard(id: 'hz', band: CanvasBands.horizon);
      final hz = await db.canvasCardsDao
          .watchCardsForBand('p1', CanvasBands.horizon)
          .first;
      expect(hz.map((c) => c.id), ['hz']);
    });

    test('watchCardLinkedTo emits null first, then a card after linking',
        () async {
      final stream = db.canvasCardsDao.watchCardLinkedTo(
        projectId: 'p1', itemType: 'action', itemId: 'AC42',
      );
      final emissions = <CanvasCard?>[];
      final sub = stream.listen(emissions.add);
      // Initially no linked card.
      await Future.delayed(const Duration(milliseconds: 50));
      await insertCard(id: 'c1', linkedType: 'action', linkedId: 'AC42');
      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(emissions.first, isNull);
      expect(emissions.last?.id, 'c1');
    });
  });

  group('CanvasCardsDao sequence deletion', () {
    test('deleteSequence removes only the given sequence by id', () async {
      await insertCard(id: 'a');
      await insertCard(id: 'b');
      await db.canvasCardsDao.addSequence(
          id: 's1', projectId: 'p1', fromCardId: 'a', toCardId: 'b');
      await db.canvasCardsDao.addSequence(
          id: 's2', projectId: 'p1', fromCardId: 'b', toCardId: 'a');
      await db.canvasCardsDao.deleteSequence('s1');
      final remaining = await db.select(db.canvasSequences).get();
      expect(remaining.single.id, 's2');
    });

    test('deleteSequenceBetween scopes by direction', () async {
      await insertCard(id: 'a');
      await insertCard(id: 'b');
      await db.canvasCardsDao.addSequence(
          id: 's1', projectId: 'p1', fromCardId: 'a', toCardId: 'b');
      await db.canvasCardsDao.addSequence(
          id: 's2', projectId: 'p1', fromCardId: 'b', toCardId: 'a');
      await db.canvasCardsDao.deleteSequenceBetween('a', 'b');
      final remaining = await db.select(db.canvasSequences).get();
      expect(remaining.single.id, 's2');
    });
  });

  group('patchCard nullable clearing', () {
    test('clears linkedItemType/Id when patched with Value(null)',
        () async {
      await insertCard(
          id: 'c1', linkedType: 'action', linkedId: 'AC1');
      await db.canvasCardsDao.patchCard(
        'c1',
        const CanvasCardsCompanion(
          linkedItemType: Value(null),
          linkedItemId: Value(null),
        ),
      );
      final after = await db.canvasCardsDao.getCardById('c1');
      expect(after!.linkedItemType, isNull);
      expect(after.linkedItemId, isNull);
    });
  });

  group('date columns', () {
    test('round-trips startDate/endDate', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c1',
        projectId: 'p1',
        title: 'Range card',
        startDate: const Value('2026-07-01'),
        endDate: const Value('2026-07-05'),
      ));
      final c = await db.canvasCardsDao.getCardById('c1');
      expect(c!.startDate, '2026-07-01');
      expect(c.endDate, '2026-07-05');
    });

    test('patchCard can clear dates with Value(null)', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c1',
        projectId: 'p1',
        title: 'tmp',
        startDate: const Value('2026-07-01'),
        endDate: const Value('2026-07-05'),
      ));
      await db.canvasCardsDao.patchCard(
        'c1',
        const CanvasCardsCompanion(
          startDate: Value(null),
          endDate: Value(null),
        ),
      );
      final c = await db.canvasCardsDao.getCardById('c1');
      expect(c!.startDate, isNull);
      expect(c.endDate, isNull);
    });

    test('dates default to null when not supplied', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c1', projectId: 'p1', title: 'no dates',
      ));
      final c = await db.canvasCardsDao.getCardById('c1');
      expect(c!.startDate, isNull);
      expect(c.endDate, isNull);
    });

    test('round-trips effortDays', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c1',
        projectId: 'p1',
        title: 'Two-week task',
        effortDays: const Value(14),
      ));
      final c = await db.canvasCardsDao.getCardById('c1');
      expect(c!.effortDays, 14);
    });

    test('patchCard can clear effortDays', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c1',
        projectId: 'p1',
        title: 'tmp',
        effortDays: const Value(14),
      ));
      await db.canvasCardsDao.patchCard(
        'c1',
        const CanvasCardsCompanion(effortDays: Value(null)),
      );
      final c = await db.canvasCardsDao.getCardById('c1');
      expect(c!.effortDays, isNull);
    });

    test('effortDays defaults to null when not supplied', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c1', projectId: 'p1', title: 'no effort',
      ));
      final c = await db.canvasCardsDao.getCardById('c1');
      expect(c!.effortDays, isNull);
    });

    test('round-trips the tags column as JSON', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c1',
        projectId: 'p1',
        title: 'tagged',
        tags: const Value('["cutover","risk"]'),
      ));
      final c = await db.canvasCardsDao.getCardById('c1');
      expect(c!.tags, '["cutover","risk"]');
    });

    test('tags defaults to null when not supplied', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c1', projectId: 'p1', title: 'untagged',
      ));
      final c = await db.canvasCardsDao.getCardById('c1');
      expect(c!.tags, isNull);
    });
  });

  group('CanvasCardsDao.getTagCountsForProject', () {
    test('returns empty when no cards have tags', () async {
      await insertCard(id: 'a');
      await insertCard(id: 'b');
      final counts = await db.canvasCardsDao.getTagCountsForProject('p1');
      expect(counts, isEmpty);
    });

    test('aggregates tag occurrences across cards', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'a', projectId: 'p1', title: 'a',
        tags: const Value('["cutover","risk"]'),
      ));
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'b', projectId: 'p1', title: 'b',
        tags: const Value('["risk","stakeholder"]'),
      ));
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c', projectId: 'p1', title: 'c',
        tags: const Value('["risk"]'),
      ));
      final counts = await db.canvasCardsDao.getTagCountsForProject('p1');
      expect(counts, {
        'cutover': 1,
        'risk': 3,
        'stakeholder': 1,
      });
    });

    test('is project-scoped', () async {
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'p2', name: 'P2'));
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'a', projectId: 'p1', title: 'a',
        tags: const Value('["cutover"]'),
      ));
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'b', projectId: 'p2', title: 'b',
        tags: const Value('["risk"]'),
      ));
      expect(await db.canvasCardsDao.getTagCountsForProject('p1'),
          {'cutover': 1});
      expect(await db.canvasCardsDao.getTagCountsForProject('p2'),
          {'risk': 1});
    });

    test('returns keys sorted alphabetically', () async {
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'a', projectId: 'p1', title: 'a',
        tags: const Value('["zeta","alpha","mu"]'),
      ));
      final counts = await db.canvasCardsDao.getTagCountsForProject('p1');
      expect(counts.keys.toList(), ['alpha', 'mu', 'zeta']);
    });
  });

  group('deleteProjectCascade', () {
    test('removes canvas cards and sequences for the project', () async {
      await db.projectDao.insertProject(
        ProjectsCompanion.insert(id: 'p2', name: 'P2'),
      );
      await insertCard(id: 'a');
      await insertCard(id: 'b');
      await db.canvasCardsDao.addSequence(
          id: 's1', projectId: 'p1', fromCardId: 'a', toCardId: 'b');
      // p2 card untouched by p1 cascade.
      await db.canvasCardsDao.insertCard(CanvasCardsCompanion.insert(
        id: 'c', projectId: 'p2', title: 'survivor',
      ));

      await db.deleteProjectCascade('p1');

      final p1Cards =
          await db.canvasCardsDao.getCardsForProject('p1');
      final p2Cards =
          await db.canvasCardsDao.getCardsForProject('p2');
      final seqs = await db.select(db.canvasSequences).get();
      expect(p1Cards, isEmpty);
      expect(p2Cards.single.id, 'c');
      expect(seqs, isEmpty);
    });
  });
}
