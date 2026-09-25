import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/export/json_exporter.dart';
import 'package:keel/core/import/json_importer.dart';
import 'package:keel/core/raid/dependency_plan_link.dart';

/// Pins the v60 decision fields through the hand-serialised sync blob,
/// plus the decision→plan arrow marker.
void main() {
  late AppDatabase src;
  late AppDatabase dst;

  setUp(() async {
    src = AppDatabase.memory();
    dst = AppDatabase.memory();
    await src.into(src.projects).insert(
        ProjectsCompanion.insert(id: 'p1', name: 'Sync decisions'));
  });

  tearDown(() async {
    await src.close();
    await dst.close();
  });

  test('options / impact / plan link / decided-on survive export → import',
      () async {
    await src.decisionsDao.upsertDecision(const DecisionsCompanion(
      id: Value('dc1'),
      projectId: Value('p1'),
      ref: Value('DC1'),
      description: Value('Which payments gateway?'),
      status: Value('decided'),
      optionsConsidered: Value('- Stripe\n- Adyen\n- Defer'),
      impactStatement: Value('Checkout build blocked'),
      planActivityId: Value('act-checkout'),
      decidedAt: Value('2026-09-20'),
      dueDate: Value('2026-09-30'),
    ));

    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);

    final d = (await dst.decisionsDao.getDecisionById('dc1'))!;
    expect(d.optionsConsidered, '- Stripe\n- Adyen\n- Defer');
    expect(d.impactStatement, 'Checkout build blocked');
    expect(d.planActivityId, 'act-checkout');
    expect(d.decidedAt, '2026-09-20');
    expect(d.status, 'decided');
  });

  test('decision plan-arrow marker survives and stays distinct from '
      'dependency markers', () async {
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
    await src.decisionsDao.upsertDecision(const DecisionsCompanion(
      id: Value('dc1'),
      projectId: Value('p1'),
      ref: Value('DC1'),
      description: Value('Gateway'),
      planActivityId: Value('act1'),
    ));
    await DependencyPlanLink.sync(src,
        projectId: 'p1',
        dependencyId: 'dc1',
        ref: 'DC1',
        description: 'Gateway',
        dependencyType: 'inbound',
        activityId: 'act1',
        show: true,
        kind: PlanLinkKind.decision);

    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    await JsonImporter.importFromString(blob, dst);

    final asDecision = await DependencyPlanLink.find(dst, 'p1', 'dc1',
        kind: PlanLinkKind.decision);
    expect(asDecision, isNotNull);
    expect(asDecision!.externalLabel, 'DC1 · Gateway');
    // The same id looked up as a dependency marker must not match.
    expect(await DependencyPlanLink.find(dst, 'p1', 'dc1'), isNull);
  });

  test('blobs from before v60 import with the new fields null', () async {
    await src.decisionsDao.upsertDecision(const DecisionsCompanion(
      id: Value('dc-old'),
      projectId: Value('p1'),
      description: Value('Legacy decision'),
    ));
    final blob =
        await JsonExporter.exportProjectToString(projectId: 'p1', db: src);
    final stripped = blob
        .replaceAll(RegExp(r'\s*"options_considered": null,'), '')
        .replaceAll(RegExp(r'\s*"impact_statement": null,'), '')
        .replaceAll(RegExp(r'\s*"plan_activity_id": null,'), '')
        .replaceAll(RegExp(r'\s*"decided_at": null,'), '');
    expect(stripped, isNot(contains('"decided_at"')));
    await JsonImporter.importFromString(stripped, dst);
    final d = (await dst.decisionsDao.getDecisionById('dc-old'))!;
    expect(d.description, 'Legacy decision');
    expect(d.optionsConsidered, isNull);
    expect(d.decidedAt, isNull);
  });
}
