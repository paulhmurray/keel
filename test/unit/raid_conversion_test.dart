import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/raid_conversion_service.dart';

const _projectId = 'p-test';

void main() {
  late AppDatabase db;
  late RaidConversionService svc;

  setUp(() async {
    db = AppDatabase.memory();
    svc = RaidConversionService(db);
    await db.into(db.projects).insert(ProjectsCompanion.insert(
          id: _projectId,
          name: 'Test Project',
        ));
  });

  tearDown(() => db.close());

  Future<void> seedRisk({
    String id = 'r-1',
    String ref = 'R3',
    String status = 'open',
    String? mitigation,
    String? sourceNote,
    String? sourceProjectId,
  }) async {
    await db.raidDao.insertRisk(RisksCompanion(
      id: Value(id),
      projectId: const Value(_projectId),
      ref: Value(ref),
      description: const Value('supplier may slip'),
      owner: const Value('Dana'),
      status: Value(status),
      mitigation: Value(mitigation),
      sourceNote: Value(sourceNote),
      sourceProjectId: Value(sourceProjectId),
      createdAt: Value(DateTime(2026, 3, 1)),
      updatedAt: Value(DateTime(2026, 3, 1)),
    ));
  }

  group('risk → issue', () {
    test('moves the row keeping id, carries fields, folds mitigation',
        () async {
      await seedRisk(mitigation: 'dual-source the part');

      final newRef =
          await svc.convert(id: 'r-1', from: RaidKind.risk, to: RaidKind.issue);

      expect(newRef, 'I1');
      expect(await db.raidDao.getRiskById('r-1'), isNull);
      final issue = await db.raidDao.getIssueById('r-1');
      expect(issue, isNotNull);
      expect(issue!.ref, 'I1');
      expect(issue.description, 'supplier may slip');
      expect(issue.owner, 'Dana');
      expect(issue.status, 'open');
      expect(issue.createdAt, DateTime(2026, 3, 1));
      expect(issue.sourceNote, contains('Converted from risk R3'));
      expect(issue.sourceNote, contains('Mitigation: dual-source the part'));
    });

    test('new ref continues the target sequence', () async {
      await db.raidDao.insertIssue(IssuesCompanion(
        id: const Value('i-existing'),
        projectId: const Value(_projectId),
        ref: const Value('I5'),
        description: const Value('existing'),
      ));
      await seedRisk();
      final newRef =
          await svc.convert(id: 'r-1', from: RaidKind.risk, to: RaidKind.issue);
      expect(newRef, 'I6');
    });

    test('closed stays closed; unknown statuses fall back to default',
        () async {
      await seedRisk(id: 'r-closed', ref: 'R1', status: 'closed');
      await seedRisk(id: 'r-accepted', ref: 'R2', status: 'accepted');

      await svc.convert(
          id: 'r-closed', from: RaidKind.risk, to: RaidKind.issue);
      await svc.convert(
          id: 'r-accepted', from: RaidKind.risk, to: RaidKind.issue);

      expect((await db.raidDao.getIssueById('r-closed'))!.status, 'closed');
      // 'accepted' doesn't exist on issues → default open.
      expect((await db.raidDao.getIssueById('r-accepted'))!.status, 'open');
    });
  });

  group('risk → decision', () {
    test('owner becomes decision maker; open becomes pending', () async {
      await seedRisk();
      final newRef = await svc.convert(
          id: 'r-1', from: RaidKind.risk, to: RaidKind.decision);
      expect(newRef, 'DC1');
      final d = await db.decisionsDao.getDecisionById('r-1');
      expect(d!.decisionMaker, 'Dana');
      expect(d.status, 'pending');
      expect(await db.raidDao.getRiskById('r-1'), isNull);
    });
  });

  group('issue → dependency', () {
    test('due date and shared statuses carry over', () async {
      await db.raidDao.insertIssue(IssuesCompanion(
        id: const Value('i-1'),
        projectId: const Value(_projectId),
        ref: const Value('I2'),
        description: const Value('waiting on infra'),
        dueDate: const Value('2026-09-15'),
        status: const Value('in progress'),
      ));
      await svc.convert(
          id: 'i-1', from: RaidKind.issue, to: RaidKind.dependency);
      final dep = await db.raidDao.getDependencyById('i-1');
      expect(dep!.dueDate, '2026-09-15');
      expect(dep.status, 'in progress');
      expect(dep.ref, 'D1');
    });
  });

  group('assumption → risk', () {
    test('basic conversion works', () async {
      await db.raidDao.insertAssumption(AssumptionsCompanion(
        id: const Value('a-1'),
        projectId: const Value(_projectId),
        ref: const Value('A4'),
        description: const Value('vendor API is stable'),
        status: const Value('invalidated'),
      ));
      await svc.convert(
          id: 'a-1', from: RaidKind.assumption, to: RaidKind.risk);
      final r = await db.raidDao.getRiskById('a-1');
      expect(r!.ref, 'R1');
      // 'invalidated' has no risk equivalent → default open.
      expect(r.status, 'open');
      expect(r.sourceNote, contains('Converted from assumption A4'));
    });
  });

  group('cross-references', () {
    test('canvas, journal and inbox links follow the type change',
        () async {
      await seedRisk();
      await db.into(db.canvasCards).insert(CanvasCardsCompanion.insert(
            id: 'card-1',
            projectId: _projectId,
            title: 'watch supplier',
            linkedItemType: const Value('risk'),
            linkedItemId: const Value('r-1'),
            promotedToType: const Value('risk'),
            promotedToId: const Value('r-1'),
          ));
      await db.into(db.journalEntries).insert(JournalEntriesCompanion.insert(
            id: 'j-1',
            projectId: _projectId,
            body: 'raised supplier risk',
            entryDate: '2026-08-01',
          ));
      await db
          .into(db.journalEntryLinks)
          .insert(JournalEntryLinksCompanion.insert(
            id: 'jl-1',
            entryId: 'j-1',
            itemType: 'risk',
            itemId: 'r-1',
          ));
      await db.into(db.inboxItems).insert(InboxItemsCompanion.insert(
            id: 'in-1',
            projectId: _projectId,
            content: 'supplier note',
            linkedItemType: const Value('risk'),
            linkedItemId: const Value('r-1'),
          ));

      await svc.convert(id: 'r-1', from: RaidKind.risk, to: RaidKind.issue);

      final card = await (db.select(db.canvasCards)
            ..where((t) => t.id.equals('card-1')))
          .getSingle();
      expect(card.linkedItemType, 'issue');
      expect(card.linkedItemId, 'r-1');
      expect(card.promotedToType, 'issue');
      expect(card.promotedToId, 'r-1');

      final link = await (db.select(db.journalEntryLinks)
            ..where((t) => t.id.equals('jl-1')))
          .getSingle();
      expect(link.itemType, 'issue');
      expect(link.itemId, 'r-1');

      final inbox = await (db.select(db.inboxItems)
            ..where((t) => t.id.equals('in-1')))
          .getSingle();
      expect(inbox.linkedItemType, 'issue');
      expect(inbox.linkedItemId, 'r-1');
    });
  });

  group('issue-specific fields', () {
    test('title and impact statement fold into the note on conversion',
        () async {
      await db.raidDao.insertIssue(IssuesCompanion(
        id: const Value('i-rich'),
        projectId: const Value(_projectId),
        ref: const Value('I3'),
        title: const Value('No data stewardship'),
        description: const Value('nobody owns data quality'),
        impactStatement: const Value('integration design blocked'),
      ));
      await svc.convert(
          id: 'i-rich', from: RaidKind.issue, to: RaidKind.risk);
      final r = await db.raidDao.getRiskById('i-rich');
      expect(r!.sourceNote, contains('Title: No data stewardship'));
      expect(r.sourceNote, contains('Impact: integration design blocked'));
    });

    test('raid item links follow the converted item to its new type',
        () async {
      await seedRisk();
      await db.raidDao.insertDependency(ProgramDependenciesCompanion(
        id: const Value('dep-1'),
        projectId: const Value(_projectId),
        description: const Value('upstream confirmation'),
      ));
      await db.raidDao.insertItemLink(RaidItemLinksCompanion(
        id: const Value('l-1'),
        projectId: const Value(_projectId),
        fromType: const Value('risk'),
        fromId: const Value('r-1'),
        toType: const Value('dependency'),
        toId: const Value('dep-1'),
      ));

      await svc.convert(id: 'r-1', from: RaidKind.risk, to: RaidKind.issue);

      final links = await db.raidDao.getLinksForItem('r-1');
      expect(links.single.fromType, 'issue');
      expect(links.single.toType, 'dependency');
    });
  });

  group('guards', () {
    test('cascaded items refuse to convert and stay untouched', () async {
      await seedRisk(sourceProjectId: 'other-project');
      expect(
        () => svc.convert(id: 'r-1', from: RaidKind.risk, to: RaidKind.issue),
        throwsStateError,
      );
      expect(await db.raidDao.getRiskById('r-1'), isNotNull);
      expect(await db.raidDao.getIssueById('r-1'), isNull);
    });

    test('missing source throws and creates nothing', () async {
      expect(
        () => svc.convert(
            id: 'nope', from: RaidKind.risk, to: RaidKind.decision),
        throwsStateError,
      );
      expect(await db.decisionsDao.getDecisionById('nope'), isNull);
    });
  });
}
