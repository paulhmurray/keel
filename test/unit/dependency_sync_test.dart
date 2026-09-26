import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/import/json_importer.dart';
import 'package:keel/core/raid/dependency_plan_link.dart';

/// The sync blob is hand-serialised, so a column added to an existing
/// table silently drops on every round-trip unless both the exporter
/// and importer know it. This pins the v59 dependency fields.
void main() {
  late AppDatabase src;
  late AppDatabase dst;

  setUp(() async {
    src = AppDatabase.memory();
    dst = AppDatabase.memory();
    await src.into(src.projects).insert(
        ProjectsCompanion.insert(id: 'p1', name: 'Sync deps'));
  });

  tearDown(() async {
    await src.close();
    await dst.close();
  });

  test('why / impact / counterparty / plan link survive export → import',
      () async {
    await src.raidDao.upsertDependency(const ProgramDependenciesCompanion(
      id: Value('dep1'),
      projectId: Value('p1'),
      ref: Value('D1'),
      description: Value('Vendor delivers API keys'),
      dependencyType: Value('inbound'),
      counterparty: Value('Acme Vendor'),
      rationale: Value('Integration can\'t start without keys'),
      impactStatement: Value('Integration slips two weeks per week late'),
      planActivityId: Value('act-int'),
      dueDate: Value('2026-11-01'),
      owner: Value('Sam'),
    ));

    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);

    final dep = (await dst.raidDao.getDependencyById('dep1'))!;
    expect(dep.counterparty, 'Acme Vendor');
    expect(dep.rationale, 'Integration can\'t start without keys');
    expect(dep.impactStatement, 'Integration slips two weeks per week late');
    expect(dep.planActivityId, 'act-int');
    expect(dep.dueDate, '2026-11-01');
    expect(dep.owner, 'Sam');
  });

  test('the show-on-plan marker survives the round-trip', () async {
    await src.programmeGanttDao.upsertWorkPackage(const TimelineWorkPackagesCompanion(
      id: Value('wp1'),
      projectId: Value('p1'),
      name: Value('WP1'),
      sortOrder: Value(0),
    ));
    await src.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('act1'),
      workPackageId: Value('wp1'),
      projectId: Value('p1'),
      name: Value('Build'),
      sortOrder: Value(0),
    ));
    await src.raidDao.upsertDependency(const ProgramDependenciesCompanion(
      id: Value('dep1'),
      projectId: Value('p1'),
      ref: Value('D1'),
      description: Value('Keys'),
      planActivityId: Value('act1'),
    ));
    await DependencyPlanLink.sync(src,
        projectId: 'p1',
        dependencyId: 'dep1',
        ref: 'D1',
        description: 'Keys',
        dependencyType: 'inbound',
        activityId: 'act1',
        show: true);

    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);

    final row = await DependencyPlanLink.find(dst, 'p1', 'dep1');
    expect(row, isNotNull);
    expect(row!.toActivityId, 'act1');
    expect(row.externalLabel, 'D1 · Keys');
  });

  test('closed-on and the risk closure note survive export → import',
      () async {
    await src.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r1'),
      projectId: Value('p1'),
      description: Value('Old risk'),
      status: Value('accepted'),
      closedAt: Value('2026-09-01'),
      closureNote: Value('Accepted: cheaper than mitigating'),
    ));
    await src.raidDao.upsertIssue(const IssuesCompanion(
      id: Value('i1'),
      projectId: Value('p1'),
      description: Value('Old issue'),
      status: Value('closed'),
      closedAt: Value('2026-09-02'),
    ));
    await src.raidDao.upsertAssumption(const AssumptionsCompanion(
      id: Value('a1'),
      projectId: Value('p1'),
      description: Value('Old assumption'),
      status: Value('validated'),
      closedAt: Value('2026-09-03'),
    ));
    await src.raidDao.upsertDependency(const ProgramDependenciesCompanion(
      id: Value('d1'),
      projectId: Value('p1'),
      description: Value('Old dependency'),
      status: Value('closed'),
      closedAt: Value('2026-09-04'),
    ));

    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);

    final r = (await dst.raidDao.getRiskById('r1'))!;
    expect(r.closedAt, '2026-09-01');
    expect(r.closureNote, 'Accepted: cheaper than mitigating');
    expect((await dst.raidDao.getIssueById('i1'))!.closedAt, '2026-09-02');
    expect(
        (await dst.raidDao.getAssumptionById('a1'))!.closedAt, '2026-09-03');
    expect(
        (await dst.raidDao.getDependencyById('d1'))!.closedAt, '2026-09-04');
  });

  test('Planview risk fields survive export → import', () async {
    await src.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r-pv'),
      projectId: Value('p1'),
      ref: Value('R19'),
      title: Value('AWS connections land late'),
      description: Value('Both gateways land in March.'),
      likelihood: Value('possible'),
      impact: Value('major'),
      likelihoodTarget: Value('possible'),
      impactTarget: Value('moderate'),
      strategy: Value('transfer'),
      owner: Value('Bart Fine'),
      assignee: Value('Paul Murray'),
      steerco: Value(true),
      enterpriseRiskLink: Value('Strategic Delivery'),
      dueDate: Value('2026-09-30'),
      lastReviewedAt: Value('2026-09-09'),
      nextReviewAt: Value('2026-09-23'),
      statusNote: Value('Awaiting AWS date.'),
    ));
    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);
    final r = (await dst.raidDao.getRiskById('r-pv'))!;
    expect(r.title, 'AWS connections land late');
    expect(r.likelihood, 'possible');
    expect(r.impact, 'major');
    expect(r.likelihoodTarget, 'possible');
    expect(r.impactTarget, 'moderate');
    expect(r.strategy, 'transfer');
    expect(r.assignee, 'Paul Murray');
    expect(r.steerco, isTrue);
    expect(r.enterpriseRiskLink, 'Strategic Delivery');
    expect(r.dueDate, '2026-09-30');
    expect(r.nextReviewAt, '2026-09-23');
    expect(r.statusNote, 'Awaiting AWS date.');
  });

  test('legacy low/medium/high in an old blob is mapped on import', () async {
    await src.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r-old'),
      projectId: Value('p1'),
      description: Value('old words'),
      likelihood: Value('possible'),
      impact: Value('moderate'),
    ));
    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    final legacy = blob
        .replaceAll('"likelihood": "possible"', '"likelihood": "high"')
        .replaceAll('"impact": "moderate"', '"impact": "low"');
    await JsonImporter.importFromString(legacy, dst);
    final r = (await dst.raidDao.getRiskById('r-old'))!;
    expect(r.likelihood, 'likely');
    expect(r.impact, 'minor');
  });

  test('the plan header hard-deadline date survives export → import', () async {
    await src.programmeGanttDao.upsertHeader(const ProgrammeHeadersCompanion(
      id: Value('h1'),
      projectId: Value('p1'),
      hardDeadline: Value('Integrations in production by Aug 27'),
      hardDeadlineDate: Value('2027-08-31'),
    ));
    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);
    final h = (await dst.programmeGanttDao.getHeader('p1'))!;
    expect(h.hardDeadline, 'Integrations in production by Aug 27');
    expect(h.hardDeadlineDate, '2027-08-31');
  });

  test('blobs from before v59 still import with the new fields null',
      () async {
    await src.raidDao.upsertDependency(const ProgramDependenciesCompanion(
      id: Value('dep-old'),
      projectId: Value('p1'),
      description: Value('Legacy dependency'),
    ));
    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    // Strip the new keys to mimic an older exporter.
    final stripped = blob
        .replaceAll(RegExp(r'\s*"counterparty": null,'), '')
        .replaceAll(RegExp(r'\s*"rationale": null,'), '')
        .replaceAll(RegExp(r'\s*"impact_statement": null,'), '')
        .replaceAll(RegExp(r'\s*"plan_activity_id": null,'), '');
    expect(stripped, isNot(contains('"counterparty"')));
    await JsonImporter.importFromString(stripped, dst);
    final dep = (await dst.raidDao.getDependencyById('dep-old'))!;
    expect(dep.description, 'Legacy dependency');
    expect(dep.counterparty, isNull);
    expect(dep.planActivityId, isNull);
  });
}
