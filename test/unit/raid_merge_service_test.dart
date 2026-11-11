import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/raid_conversion_service.dart' show RaidKind;
import 'package:keel/core/raid/raid_duplicates.dart';
import 'package:keel/core/raid/raid_merge_service.dart';

void main() {
  late AppDatabase db;
  final when = DateTime(2026, 10, 26, 9);

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'p', name: 'P'));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r1'), projectId: Value('p'), ref: Value('R1'), owner: Value('Paul'),
      likelihood: Value('likely'), impact: Value('major'),
      description: Value('If the vendor slips, SIT starts late.'),
      sourceNote: Value('From the kickoff'),
    ));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r2'), projectId: Value('p'), ref: Value('R2'), owner: Value('Sam'),
      description: Value('Vendor build late means SIT delayed.'),
    ));
    await db.raidDao.upsertAssumption(const AssumptionsCompanion(
      id: Value('a1'), projectId: Value('p'), ref: Value('A1'),
      description: Value('We assume Salesforce sign the order form by 3 Oct.'),
    ));
    await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
      id: Value('d1'), projectId: Value('p'), ref: Value('D1'),
      dependencyType: Value('inbound'), counterparty: Value('Salesforce'),
      description: Value('Salesforce must deliver the signed order form by 3 Oct.'),
    ));
  });
  tearDown(() => db.close());

  Future<List<DuplicateItem>> items() async => collectDuplicateItems(
        risks: await db.raidDao.getRisksForProject('p'),
        assumptions: await db.raidDao.getAssumptionsForProject('p'),
        issues: const [],
        dependencies: await db.raidDao.getDependenciesForProject('p'),
      );

  test('same register: survivor reworded with history, other closed with pointer',
      () async {
    final all = await items();
    final group = DuplicateGroup(
      members: all.where((i) => i.kind == RaidKind.risk).toList(),
      register: RaidKind.risk,
      reason: 'same slip',
      merged: 'If the vendor slips again, then SIT may start late, resulting in a four-week delay.',
    );
    final out = await RaidMergeService(db).merge(
      group: group,
      survivor: group.members.first,
      keepAs: RaidKind.risk,
      mergedDescription: group.merged,
      now: when,
    );
    expect(out.survivorId, 'r1');
    expect(out.survivorRef, 'R1');
    expect(out.closed, [(RaidKind.risk, 'r2')]);

    final r1 = (await db.raidDao.getRiskById('r1'))!;
    expect(r1.description, group.merged);
    expect(r1.sourceNote,
        'From the kickoff\nMerged in Risk R2 2026-10-26. Was: "If the vendor slips, SIT starts late."');
    expect(r1.owner, 'Paul', reason: 'partial upsert keeps the other fields');
    expect(r1.likelihood, 'likely');
    expect(r1.status, 'open');

    final r2 = (await db.raidDao.getRiskById('r2'))!;
    expect(r2.status, 'closed');
    expect(r2.closedAt, '2026-10-26');
    expect(r2.sourceNote, 'Merged into Risk R1 2026-10-26.');
    expect(r2.description, 'Vendor build late means SIT delayed.',
        reason: 'the closed duplicate keeps its own words');
  });

  test('unchanged wording leaves the description alone and notes only the merge',
      () async {
    final all = await items();
    final group = DuplicateGroup(
      members: all.where((i) => i.kind == RaidKind.risk).toList(),
      register: RaidKind.risk, reason: '', merged: '',
    );
    await RaidMergeService(db).merge(
      group: group, survivor: group.members.first, keepAs: RaidKind.risk,
      mergedDescription: null, now: when,
    );
    final r1 = (await db.raidDao.getRiskById('r1'))!;
    expect(r1.description, 'If the vendor slips, SIT starts late.');
    expect(r1.sourceNote, 'From the kickoff\nMerged in Risk R2 2026-10-26.');
  });

  test('across registers: assumption kept as a dependency keeps its id, gets a D ref',
      () async {
    final all = await items();
    final a1 = all.firstWhere((i) => i.id == 'a1');
    final d1 = all.firstWhere((i) => i.id == 'd1');
    final group = DuplicateGroup(
      members: [a1, d1], register: RaidKind.dependency,
      reason: 'same promise',
      merged: 'Salesforce must deliver the signed order form by 3 Oct so that build can start; if late, [impact to confirm].',
    );
    final out = await RaidMergeService(db).merge(
      group: group, survivor: a1, keepAs: RaidKind.dependency,
      mergedDescription: group.merged, now: when,
    );
    expect(out.survivorKind, RaidKind.dependency);
    expect(out.survivorRef, 'D2', reason: 'next free dependency ref');
    expect(await db.raidDao.getAssumptionById('a1'), isNull);

    final moved = (await db.raidDao.getDependencyById('a1'))!;
    expect(moved.ref, 'D2');
    expect(moved.description, group.merged);
    expect(moved.sourceNote, contains('Converted from assumption A1'));
    expect(moved.sourceNote, contains('Merged in Dependency D1 2026-10-26. Was: "We assume Salesforce'));
    expect(moved.status, 'open');

    final old = (await db.raidDao.getDependencyById('d1'))!;
    expect(old.status, 'closed');
    expect(old.closedAt, '2026-10-26');
    expect(old.sourceNote, 'Merged into Dependency D2 2026-10-26.');
  });
}
