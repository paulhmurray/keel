import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/helm/week_ritual.dart';
import 'package:keel/features/helm/week_ritual_dialog.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// The four-step ritual on an in-memory database: carry one rock from
/// last week, pick one from the plate, allocate two days, commit — then
/// the week holds the objectives, their allocations, the drafted
/// missions and the charted stamp; last week holds the review.
void main() {
  late AppDatabase db;
  // The week under test is fixed; "last week" is the one before it.
  final monday = DateTime(2026, 10, 12);
  const lastMondayIso = '2026-10-05';

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.insertProject(
      ProjectsCompanion.insert(id: 'p1', name: 'TAC'),
    );
    // Last week: one met, one not.
    final last = await db.weekPlanDao.getOrCreatePlanForWeek(lastMondayIso);
    await db.weekPlanDao.insertObjective(
      planId: last.id,
      label: 'Finish the adapter',
      targetBlocks: 4,
    );
    final metId = await db.weekPlanDao.insertObjective(
      planId: last.id,
      label: 'Status pack',
      targetBlocks: 1,
    );
    await db.weekPlanDao.setObjectiveDone(last.id, metId, true);
    // Something dated in the week under test, so the plate has an item.
    await db.actionsDao.upsertAction(
      const ProjectActionsCompanion(
        id: Value('a1'),
        projectId: Value('p1'),
        ref: Value('AC1'),
        description: Value('Chase the keys'),
        dueDate: Value('2026-10-14'),
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showWeekRitual(context, db: db, date: monday),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // A bounded settle: a load that never finishes fails fast and loudly
    // instead of spinning for the framework's ten-minute default.
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 30));
  }

  testWidgets('look back, pick, allocate, commit', (tester) async {
    await open(tester);

    // Step 1: the unmet rock defaults to Carry, the met one to Drop.
    expect(find.text('Finish the adapter'), findsOneWidget);
    expect(find.text('Status pack'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'What did last week teach you?'),
      'Tuesdays are meeting-heavy.',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2: the carried rock is already listed; pick the dated action.
    expect(find.text('THIS WEEK\'S ROCKS · 1'), findsOneWidget);
    await tester.tap(find.text('AC1 Chase the keys'));
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK\'S ROCKS · 2'), findsOneWidget);
    // And one typed by hand.
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a rock of your own'),
      'Write the SIT plan',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK\'S ROCKS · 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 3: tap Mon twice and Wed once on the first rock.
    final monCells = find.byWidgetPredicate(
      (w) =>
          w is InkWell &&
          w.child is Container &&
          (w.child as Container).child is Text,
    );
    expect(monCells, findsWidgets);
    // The grid has 3 rocks × 7 days of cells in row order; first row, Mon = index 0.
    await tester.tap(monCells.at(0));
    await tester.pumpAndSettle();
    await tester.tap(monCells.at(0));
    await tester.pumpAndSettle();
    await tester.tap(monCells.at(2));
    await tester.pumpAndSettle();
    // Monday and Wednesday missions were drafted from the allocations.
    expect(
        find.byWidgetPredicate((w) =>
            w is TextField && w.controller?.text == 'Finish the adapter'),
        findsNWidgets(2));
    await tester.tap(find.text('Review and commit'));
    await tester.pumpAndSettle();

    // Step 4.
    expect(find.textContaining('Mon 2 · Wed 1'), findsOneWidget);
    expect(find.textContaining('rocks have no day'), findsOneWidget);
    await tester.tap(find.text('Commit the week'));
    await tester.pumpAndSettle();

    final week = (await db.weekPlanDao.getPlanForWeek('2026-10-12'))!;
    expect(week.chartedAt, isNotNull);
    final objs = await db.weekPlanDao.getObjectivesForPlan(week.id);
    expect(objs.map((o) => o.label).toSet(), {
      'Finish the adapter',
      'AC1 Chase the keys',
      'Write the SIT plan',
    });
    final carried = objs.firstWhere((o) => o.label == 'Finish the adapter');
    expect(carried.carriedFromId, isNotNull);
    expect(parseDayAllocations(carried.dayAllocationsJson), {0: 2, 2: 1});
    expect(carried.targetBlocks, 3, reason: 'target follows the allocation');
    final picked = objs.firstWhere((o) => o.label == 'AC1 Chase the keys');
    expect(picked.linkedActionId, 'a1');
    expect(picked.projectId, 'p1');
    final missions = week.dayMissionsJson;
    expect(missions, contains('"0":"Finish the adapter"'));
    expect(missions, contains('"2":"Finish the adapter"'));
    final last = (await db.weekPlanDao.getPlanForWeek(lastMondayIso))!;
    expect(last.reviewedAt, isNotNull);
    expect(last.reviewNote, 'Tuesdays are meeting-heavy.');

    // Reopening edits rather than duplicates, and offers no re-carry.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('already carried'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK\'S ROCKS · 3'), findsOneWidget);
  });

  testWidgets('cancel at any step writes nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AC1 Chase the keys'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip('Cancel — nothing is written until Commit'),
    );
    await tester.pumpAndSettle();
    expect(await db.weekPlanDao.getPlanForWeek('2026-10-12'), isNull);
    final last = (await db.weekPlanDao.getPlanForWeek(lastMondayIso))!;
    expect(last.reviewedAt, isNull);
  });

  testWidgets('the morning prefill places allocated rocks as draft blocks', (
    tester,
  ) async {
    final week = await db.weekPlanDao.getOrCreatePlanForWeek('2026-10-12');
    final id = await db.weekPlanDao.insertObjective(
      planId: week.id,
      label: 'Finish the adapter',
      dayAllocationsJson: '{"0":3}',
      projectId: 'p1',
    );
    final blocks = prefillBlocks(
      objectives: await db.weekPlanDao.getObjectivesForPlan(week.id),
      weekday: 0,
      dayStart: 420,
      dayEnd: 1200,
    );
    expect(blocks.single.objectiveId, id);
    expect((blocks.single.startMinute, blocks.single.endMinute), (420, 510));
  });
}
