import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/raid_conversion_service.dart' show RaidKind;
import 'package:keel/core/raid/raid_duplicates.dart';

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'p', name: 'P'));
  });
  tearDown(() => db.close());

  Future<List<DuplicateItem>> collect() async => collectDuplicateItems(
        risks: await db.raidDao.getRisksForProject('p'),
        assumptions: await db.raidDao.getAssumptionsForProject('p'),
        issues: await db.raidDao.getIssuesForProject('p'),
        dependencies: await db.raidDao.getDependenciesForProject('p'),
      );

  Future<void> seed() async {
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r1'), projectId: Value('p'), ref: Value('R1'),
      title: Value('Vendor slips'), owner: Value('Paul'),
      description: Value('If the vendor slips, SIT starts late.'),
    ));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r2'), projectId: Value('p'), ref: Value('R2'),
      description: Value('Vendor build late means SIT delayed.'),
    ));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r-closed'), projectId: Value('p'), ref: Value('R3'),
      status: Value('closed'), description: Value('Old and closed.'),
    ));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r-copy'), projectId: Value('p'), ref: Value('R4'),
      sourceProjectId: Value('other'), description: Value('Cascaded copy.'),
    ));
    await db.raidDao.upsertAssumption(const AssumptionsCompanion(
      id: Value('a1'), projectId: Value('p'), ref: Value('A1'),
      description: Value('We assume Salesforce sign the order form by 3 Oct.'),
    ));
    await db.raidDao.upsertIssue(const IssuesCompanion(
      id: Value('i1'), projectId: Value('p'), ref: Value('I1'),
      description: Value('Environment is down.'), dueDate: Value('2026-11-02'),
    ));
    await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
      id: Value('d1'), projectId: Value('p'), ref: Value('D1'),
      dependencyType: Value('inbound'), counterparty: Value('Salesforce'),
      description: Value('Salesforce must deliver the signed order form by 3 Oct.'),
    ));
  }

  test('collects open native items across the four registers, in order', () async {
    await seed();
    final items = await collect();
    expect(items.map((i) => i.id), ['r1', 'r2', 'a1', 'i1', 'd1']);
    expect(items.first.label, 'Risk R1');
    expect(items.first.headline, 'Vendor slips');
    expect(items[1].headline, 'Vendor build late means SIT delayed.');
    expect(items.first.context.map((c) => c.$1), containsAll(['Owner', 'Status']));
    expect(items.last.context.map((c) => c.$1), contains('Counterparty'));
  });

  test('prompt numbers every item and carries ref, owner, status and due', () async {
    await seed();
    final items = await collect();
    final p = duplicatesPrompt(items, projectContext: 'Project P context');
    expect(p.system, startsWith('Project P context'));
    expect(p.system, contains('"groups"'));
    expect(p.system, contains('If [cause], then [event]'));
    expect(p.user, contains('[1] Risk R1: Vendor slips — If the vendor slips'));
    expect(p.user, contains('owner: Paul; status: open'));
    expect(p.user, contains('[4] Issue I1: Environment is down. (status: open; due: 2026-11-02)'));
    expect(p.user, contains('[5] Dependency D1:'));
  });

  group('parsing the answer', () {
    late List<DuplicateItem> items;
    setUp(() async {
      await seed();
      items = await collect();
    });

    test('plain JSON: members by number, register honoured', () {
      final groups = parseDuplicateGroups(
        '{"groups":[{"items":[1,2],"register":"risk","reason":"same slip","merged":"If the vendor slips, then SIT may start late, resulting in delay."}]}',
        items,
      );
      expect(groups, hasLength(1));
      expect(groups.single.members.map((m) => m.id), ['r1', 'r2']);
      expect(groups.single.register, RaidKind.risk);
      expect(groups.single.reason, 'same slip');
      expect(groups.single.crossesRegisters, isFalse);
    });

    test('fenced JSON with prose around it, refs accepted, cross-register', () {
      final groups = parseDuplicateGroups(
        'Here you go:\n```json\n{"groups":[{"items":["A1","D1"],"register":"Dependency","reason":"same promise","merged":"Salesforce must deliver the signed order form by 3 Oct so that build can start; if late, [impact to confirm]."}]}\n```\nThanks.',
        items,
      );
      expect(groups.single.members.map((m) => m.id), ['a1', 'd1']);
      expect(groups.single.register, RaidKind.dependency);
      expect(groups.single.crossesRegisters, isTrue);
      expect(groups.single.kinds, [RaidKind.assumption, RaidKind.dependency]);
    });

    test('unknown members dropped, singletons dropped, items in one group only', () {
      final groups = parseDuplicateGroups(
        '{"groups":['
        '{"items":[1,99,"Z9"],"register":"risk","reason":"","merged":""},'
        '{"items":[1,2],"register":"risk","reason":"a","merged":""},'
        '{"items":[2,3],"register":"risk","reason":"b","merged":""},'
        '{"items":[3,3],"register":"assumption","reason":"c","merged":""}'
        ']}',
        items,
      );
      expect(groups, hasLength(1));
      expect(groups.single.reason, 'a');
    });

    test('register that no member has falls back to the first member', () {
      final groups = parseDuplicateGroups(
        '{"groups":[{"items":[3,5],"register":"issue","reason":"","merged":""}]}',
        items,
      );
      expect(groups.single.register, RaidKind.assumption);
    });

    test('empty groups and missing groups mean nothing found', () {
      expect(parseDuplicateGroups('{"groups":[]}', items), isEmpty);
      expect(parseDuplicateGroups('{"result":"none"}', items), isEmpty);
    });

    test('a thinking block with a brace in it is ignored', () {
      final groups = parseDuplicateGroups(
        '<think>Let me weigh {1,2} against the rest…</think>\n'
        '{"groups":[{"items":[1,2],"register":"risk","reason":"x","merged":""}]}',
        items,
      );
      expect(groups.single.members.map((m) => m.id), ['r1', 'r2']);
    });

    test('no JSON at all is a format error, not an empty result', () {
      expect(() => parseDuplicateGroups('I found no duplicates.', items),
          throwsFormatException);
    });
  });

  test('notes name the other side and keep prior wording', () {
    final when = DateTime(2026, 10, 26);
    expect(
      mergeSurvivorNote(
        existingSourceNote: null,
        absorbedLabels: ['Assumption A1'],
        previousDescription: 'Old words',
        when: when,
      ),
      'Merged in Assumption A1 2026-10-26. Was: "Old words"',
    );
    expect(
      mergeSurvivorNote(
        existingSourceNote: 'Imported 2026-09-01',
        absorbedLabels: ['Risk R2', 'Risk R5'],
        previousDescription: null,
        when: when,
      ),
      'Imported 2026-09-01\nMerged in Risk R2, Risk R5 2026-10-26.',
    );
    expect(
      mergeClosedNote(existingSourceNote: '  ', survivorLabel: 'Risk R1', when: when),
      'Merged into Risk R1 2026-10-26.',
    );
  });

  group('refreshGroups', () {
    DuplicateItem item(RaidKind k, String id, String ref) => DuplicateItem(
          kind: k, id: id, ref: ref, title: null, description: 'x',
          status: 'open', owner: null, dueDate: null, context: const [],
        );
    final a1 = item(RaidKind.assumption, 'a1', 'A1');
    final d1 = item(RaidKind.dependency, 'd1', 'D1');
    final r1 = item(RaidKind.risk, 'r1', 'R1');
    final g = DuplicateGroup(
      members: [a1, d1], register: RaidKind.dependency, reason: 'same promise',
      merged: 'merged words',
    );

    test('a converted member comes back in its new register with its new ref', () {
      final a1AsRisk = item(RaidKind.risk, 'a1', 'R7');
      final out = refreshGroups([g], [a1AsRisk, d1, r1]);
      expect(out, hasLength(1));
      expect(out.first.members.map((m) => m.label), ['Risk R7', 'Dependency D1']);
      expect(out.first.register, RaidKind.dependency, reason: 'D1 still lives there');
      expect(out.first.reason, 'same promise');
      expect(out.first.merged, 'merged words');
      expect(out.first.crossesRegisters, isTrue);
    });

    test('a closed member drops out and the group is kept, short', () {
      final out = refreshGroups([g], [d1, r1]);
      expect(out.first.members.map((m) => m.id), ['d1']);
    });

    test('register follows the first remaining member when nobody lives there', () {
      final d1AsIssue = item(RaidKind.issue, 'd1', 'I2');
      final out = refreshGroups([g], [a1, d1AsIssue]);
      expect(out.first.register, RaidKind.assumption);
    });

    test('a refreshed group keeps its place in the list', () {
      final g2 = DuplicateGroup(
        members: [r1, item(RaidKind.risk, 'r2', 'R2')],
        register: RaidKind.risk, reason: '', merged: '',
      );
      final out = refreshGroups([g, g2], [a1, d1, r1]);
      expect(out, hasLength(2));
      expect(out[1].members.map((m) => m.id), ['r1']);
    });
  });
}
