import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/search/project_search.dart';
import 'package:keel/core/shell/landing.dart';

/// Project-wide find: one word predicate for everything, intent-tiered
/// ranking (ref, then title prefix, then anywhere), sections as hits,
/// and strict scoping to the current project.
void main() {
  group('matching', () {
    test('every word must appear; empty query matches all', () {
      expect(matchesAllWords('sam patel claims pm', 'PATEL claims'), isTrue);
      expect(matchesAllWords('sam patel claims pm', 'sam jones'), isFalse);
      expect(matchesAllWords('anything', ''), isTrue);
      expect(matchesAllWords('anything', '   '), isTrue);
    });
  });

  group('ranking', () {
    SearchHit hit(String title, {String? ref, String? extra}) => SearchHit(
          kind: SearchKind.risk,
          id: title,
          ref: ref,
          title: title,
          haystack: [ref, title, extra]
              .whereType<String>()
              .join(' ')
              .toLowerCase(),
          navIndex: 2,
        );

    test('exact ref outranks a title that merely contains the ref', () {
      final r1 = hit('Vendor slips', ref: 'R1');
      final r12 = hit('Something about R1 in the title', ref: 'R12');
      final ranked = rankHits([r12, r1], 'R1');
      expect(ranked.map((h) => h.ref), ['R1', 'R12']);
    });

    test('title prefix outranks title contains, which outranks body only',
        () {
      final prefix = hit('Vendor contract late');
      final contains = hit('Late vendor contract');
      final body = hit('Procurement', extra: 'the vendor is slow');
      final ranked = rankHits([body, contains, prefix], 'vendor');
      expect(ranked.map((h) => h.title),
          ['Vendor contract late', 'Late vendor contract', 'Procurement']);
    });

    test('non-matching candidates are dropped; ties sort by title', () {
      final b = hit('Beta vendor');
      final a = hit('Alpha vendor');
      final x = hit('Unrelated');
      expect(rankHits([b, x, a], 'vendor').map((h) => h.title),
          ['Alpha vendor', 'Beta vendor']);
    });

    test('groups follow kind display order', () {
      final person = SearchHit(
          kind: SearchKind.person, id: 'p', title: 'Sam',
          haystack: 'sam', navIndex: 4);
      final risk = hit('Sam risk');
      final grouped = groupHits([risk, person]);
      expect(grouped.keys.toList(), [SearchKind.person, SearchKind.risk]);
    });
  });

  group('sections', () {
    test('Overview is only offered for programmes', () {
      final proj = ProjectSearchIndex.sectionHits(isProgramme: false);
      final prog = ProjectSearchIndex.sectionHits(isProgramme: true);
      expect(proj.any((h) => h.navIndex == kNavOverview), isFalse);
      expect(prog.any((h) => h.navIndex == kNavOverview), isTrue);
      expect(proj.any((h) => h.navIndex == kNavHelm), isTrue);
    });

    test('aliases reach a section: "risks" finds RAID, "budget" Finance', () {
      final ix = ProjectSearchIndex.build(isProgramme: false);
      expect(ix.search('risks').single.title, 'RAID');
      expect(ix.search('budget').single.title, 'Finance');
    });

    test('empty query lists sections only', () {
      final ix = ProjectSearchIndex.build(
        isProgramme: false,
        persons: [_person('x', 'Sam Patel')],
      );
      expect(ix.search('').every((h) => h.kind == SearchKind.section), isTrue);
      expect(ix.search(''), isNotEmpty);
    });
  });

  group('index from the database', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.memory();
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'proj', name: 'TAC'));
      await db.projectDao
          .insertProject(ProjectsCompanion.insert(id: 'other', name: 'Other'));
      await db.peopleDao.insertPerson(const PersonsCompanion(
        id: Value('sam'), projectId: Value('proj'), name: Value('Sam Patel'),
        role: Value('Project Manager'), organisation: Value('Claims'),
      ));
      await db.peopleDao.insertPerson(const PersonsCompanion(
        id: Value('sam2'), projectId: Value('other'), name: Value('Sam Patel'),
      ));
      await db.raidDao.upsertRisk(const RisksCompanion(
        id: Value('r1'), projectId: Value('proj'), ref: Value('R1'),
        title: Value('Vendor slips'), description: Value('Vendor may slip'),
        owner: Value('Sam Patel'),
      ));
      await db.raidDao.upsertIssue(const IssuesCompanion(
        id: Value('i1'), projectId: Value('proj'), ref: Value('I1'),
        description: Value('UAT environment down'),
      ));
      await db.actionsDao.upsertAction(const ProjectActionsCompanion(
        id: Value('a1'), projectId: Value('proj'), ref: Value('AC1'),
        description: Value('Chase the vendor contract'),
        owner: Value('Sam Patel'),
      ));
      await db.decisionsDao.upsertDecision(const DecisionsCompanion(
        id: Value('dc1'), projectId: Value('proj'), ref: Value('DC1'),
        description: Value('Pick the vendor'),
      ));
      await db.milestonesDao.upsert(const MilestonesCompanion(
        id: Value('m1'), projectId: Value('proj'), name: Value('Go-live'),
        date: Value('2027-01-10'),
      ));
      await db.glossaryDao.upsert(const GlossaryEntriesCompanion(
        id: Value('g1'), projectId: Value('proj'), name: Value('Service Level Agreement'),
        acronym: Value('SLA'), description: Value('Contractual uptime promise'),
      ));
    });
    tearDown(() => db.close());

    test('every table is indexed and scoped to the project', () async {
      final ix = await ProjectSearchIndex.load(db, 'proj', isProgramme: false);
      final kinds = ix.hits.map((h) => h.kind).toSet();
      expect(kinds, containsAll([
        SearchKind.section, SearchKind.person, SearchKind.risk,
        SearchKind.issue, SearchKind.action, SearchKind.decision,
        SearchKind.milestone, SearchKind.glossary,
      ]));
      expect(ix.hits.where((h) => h.kind == SearchKind.person).length, 1,
          reason: 'the other project\'s Sam must not leak in');
    });

    test('"vendor" reaches risk, action and decision; the owner is a hint',
        () async {
      final ix = await ProjectSearchIndex.load(db, 'proj', isProgramme: false);
      final hits = ix.search('vendor');
      // People's "vendors" alias also matches — a section hit, fine.
      expect(
          hits
              .where((h) => h.kind != SearchKind.section)
              .map((h) => h.kind)
              .toSet(),
          {SearchKind.risk, SearchKind.action, SearchKind.decision});
      expect(hits.first.title, 'Vendor slips', reason: 'title prefix wins');
      expect(hits.firstWhere((h) => h.kind == SearchKind.risk).subtitle,
          contains('Sam Patel'));
    });

    test('typing a ref puts that item first, above people and sections',
        () async {
      final ix = await ProjectSearchIndex.load(db, 'proj', isProgramme: false);
      expect(ix.search('AC1').first.id, 'a1');
      expect(ix.search('r1').first.id, 'r1');
    });

    test('acronyms and section aliases are searchable', () async {
      final ix = await ProjectSearchIndex.load(db, 'proj', isProgramme: false);
      expect(ix.search('sla').first.id, 'g1');
      expect(ix.search('people').first.kind, SearchKind.section);
    });

    test('payload carries the typed row for the shell to open', () async {
      final ix = await ProjectSearchIndex.load(db, 'proj', isProgramme: false);
      final sam = ix.search('sam patel').first;
      expect(sam.kind, SearchKind.person);
      expect(sam.payload, isA<Person>());
      expect((sam.payload as Person).id, 'sam');
    });
  });
}

Person _person(String id, String name) => Person(
      id: id,
      projectId: 'proj',
      name: name,
      personType: 'colleague',
      isStakeholder: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
