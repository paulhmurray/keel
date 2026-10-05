import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/llm/llm_client.dart';
import 'package:keel/core/plan/variance_links.dart';
import 'package:keel/core/raid/dependency_plan_link.dart';
import 'package:keel/features/timeline/gantt/plan_gaps_dialog.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// The pull-in dialog: counts the forgotten register items, proposes a
/// home for each, and on Link writes the link Keel already understands.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P'));
    await db.programmeGanttDao.upsertHeader(const ProgrammeHeadersCompanion(
      id: Value('h'), projectId: Value('p1'), month0Date: Value('2026-06-01'),
    ));
    await db.programmeGanttDao
        .upsertWorkPackage(const TimelineWorkPackagesCompanion(
      id: Value('wp'), projectId: Value('p1'), name: Value('Build'),
      sortOrder: Value(0),
    ));
    // Sep–Nov 2026 (months 3–5).
    await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('cover'), workPackageId: Value('wp'), projectId: Value('p1'),
      name: Value('Build adapter'), startMonth: Value(3), endMonth: Value(5),
      sortOrder: Value(0),
    ));
    await db.actionsDao.upsertAction(const ProjectActionsCompanion(
      id: Value('a1'), projectId: Value('p1'), ref: Value('AC1'),
      description: Value('Chase the keys'), dueDate: Value('2026-10-10'),
    ));
    await db.decisionsDao.upsertDecision(const DecisionsCompanion(
      id: Value('d1'), projectId: Value('p1'), ref: Value('DC1'),
      description: Value('Pick the vendor'), dueDate: Value('2026-10-01'),
    ));
    await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
      id: Value('p1dep'), projectId: Value('p1'), ref: Value('D1'),
      description: Value('Vendor keys'), dueDate: Value('2026-10-20'),
    ));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r1'), projectId: Value('p1'), ref: Value('R1'),
      description: Value('Vendor slips'), dueDate: Value('2026-10-30'),
    ));
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, {LLMClient? client}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) =>
                      PlanGapsDialog(db: db, projectId: 'p1', client: client),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('scope counts each kind; Link writes every kind of link',
      (tester) async {
    await open(tester);
    expect(find.text('1 action not on the plan'), findsOneWidget);
    expect(find.text('1 decision not on the plan'), findsOneWidget);
    expect(find.text('1 dependency not on the plan'), findsOneWidget);
    expect(find.text('1 risk not on the plan'), findsOneWidget);

    await tester.tap(find.text('Review 4 items'));
    await tester.pumpAndSettle();
    // Every card proposes the covering activity; Link each.
    for (var i = 0; i < 4; i++) {
      expect(find.text('ENGINE GUESS'), findsOneWidget);
      expect(find.textContaining('covers when this is due'), findsOneWidget);
      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
    }
    expect(find.text('4 of 4 linked.'), findsOneWidget);

    final a = (await db.actionsDao.getActionById('a1'))!;
    expect(a.planActivityId, 'cover');
    final d = (await db.decisionsDao.getDecisionById('d1'))!;
    expect(d.planActivityId, 'cover');
    final arrow = await DependencyPlanLink.find(db, 'p1', 'd1',
        kind: PlanLinkKind.decision);
    expect(arrow, isNotNull, reason: 'a decision gates its activity');
    expect(arrow!.toActivityId, 'cover');
    final dep = (await db.raidDao.getDependencyById('p1dep'))!;
    expect(dep.planActivityId, 'cover');
    expect(await DependencyPlanLink.find(db, 'p1', 'p1dep'), isNotNull);
    final act = (await db.programmeGanttDao.getActivityById('cover'))!;
    expect(parseVarianceLinks(act.varianceRaidLinksJson),
        [(type: 'risk', id: 'r1')]);
    expect(act.varianceRaidId, 'r1', reason: 'legacy mirror of the first link');

    // Reopen: nothing left.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing is missing'), findsOneWidget);
  });

  testWidgets('with AI: a new row is created where the model says, and linked',
      (tester) async {
    await open(tester, client: _FakeClient());
    await tester.tap(find.text('Ask AI where each belongs'));
    await tester.pumpAndSettle();
    // First card is the action: the fake proposes a new activity, so the
    // new-row fields are open and a type can be chosen.
    expect(find.text('AI PLACED'), findsOneWidget);
    expect(find.textContaining('A new activity in Nov 2026.'), findsOneWidget);
    expect(find.text('Create activity and link'), findsOneWidget);
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'As a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Milestone').last);
    await tester.pumpAndSettle();
    expect(find.text('Create milestone and link'), findsOneWidget);
    await tester.tap(find.text('Create milestone and link'));
    await tester.pumpAndSettle();

    final a = (await db.actionsDao.getActionById('a1'))!;
    final created = (await db.programmeGanttDao.getActivityById(a.planActivityId!))!;
    expect(created.name, 'Key handover');
    expect(created.activityType, 'milestone');
    expect(created.workPackageId, 'wp');
    expect(created.startMonth, 5);
    expect(created.notes, contains('Added from the action register'));

    // The remaining cards got the existing activity from the fake, with
    // the new-row fields folded away.
    expect(find.text('AI PLACED'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
    expect(find.text('or a new row instead…'), findsOneWidget);
    expect(find.text('In work package'), findsNothing);
  });

  testWidgets('the target can be changed by hand and Skip writes nothing',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Review 4 items'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect((await db.actionsDao.getActionById('a1'))!.planActivityId, isNull);
    expect(find.text('2 of 4'), findsOneWidget);
  });
}

/// Puts the action on a new row, everything else on the existing one.
class _FakeClient implements LLMClient {
  @override
  Future<String> complete({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1000,
  }) async {
    if (userMessage.contains('Item: Action:')) {
      return '{"activity_id": null, "new_activity": {"work_package_id": "wp", '
          '"name": "Key handover", "month": "2026-11"}, '
          '"rationale": "Nothing on the plan is about the keys."}';
    }
    return '{"activity_id": "cover", "new_activity": null, '
        '"rationale": "Same piece of work."}';
  }

  @override
  Stream<String> stream(
          {required String systemPrompt, required String userMessage}) =>
      Stream.value('');
}
