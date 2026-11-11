import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/helm/day_plan_logic.dart';
import 'package:keel/features/helm/helm_view.dart';
import 'package:keel/providers/project_provider.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Starting a day no longer drops the week's rocks onto the grid. They
/// wait in the Today column's PLANNED FOR TODAY panel until dragged onto
/// an hour or placed — one at a time, or all at once.
const _pid = 'p-rocks';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 900);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<ProjectProvider>(create: (_) => ProjectProvider(db)),
        ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
      ],
      child: const MaterialApp(home: Scaffold(body: HelmView())),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  late AppDatabase db;
  late DateTime now;
  late String todayIso;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: _pid, name: 'Rocks'));
    now = DateTime.now();
    todayIso = _iso(now);
    final week = await db.weekPlanDao.getOrCreatePlanForWeek(_iso(mondayOf(now)));
    final wd = now.weekday - 1;
    await db.weekPlanDao.insertObjective(
      planId: week.id,
      label: 'Finish the adapter',
      dayAllocationsJson: '{"$wd":3}',
      projectId: _pid,
    );
    await db.weekPlanDao.insertObjective(
      planId: week.id,
      label: 'Write the status pack',
      dayAllocationsJson: '{"$wd":1}',
      projectId: _pid,
    );
  });

  tearDown(() => db.close());

  testWidgets('starting the day leaves the rocks waiting, and Place all puts them down',
      (tester) async {
    await _pump(tester, db);
    expect(find.text('Chart your day'), findsOneWidget);
    expect(find.text('PLANNED FOR TODAY'), findsNothing,
        reason: 'no plan yet, so no panel');

    await tester.tap(find.text("Start today's plan"));
    await _settle(tester);

    final plan = (await db.dayPlanDao.getPlanForDate(todayIso))!;
    expect(await db.dayPlanDao.getBlocksForPlan(plan.id), isEmpty,
        reason: 'charting no longer pre-places rocks');
    expect(find.text('PLANNED FOR TODAY'), findsOneWidget);
    expect(find.text('Finish the adapter'), findsOneWidget);
    expect(find.text('Write the status pack'), findsOneWidget);
    expect(find.text('90 min'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('Place'), findsNWidgets(2));
    expect(find.text('Place all'), findsOneWidget);
    expect(find.textContaining('2 waiting'), findsOneWidget);

    await tester.tap(find.text('Place all'));
    await _settle(tester);

    final blocks = await db.dayPlanDao.getBlocksForPlan(plan.id)
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    expect(blocks.map((b) => b.label), ['Finish the adapter', 'Write the status pack'],
        reason: 'biggest first from the start of the day');
    expect(blocks[0].endMinute - blocks[0].startMinute, 90);
    expect(blocks[1].endMinute - blocks[1].startMinute, 30);
    expect(blocks[1].startMinute, blocks[0].endMinute);
    expect(blocks.every((b) => b.objectiveId != null), isTrue);
    expect(find.text('Place all'), findsNothing);
    expect(find.text('Place'), findsNothing);
    expect(find.text('4/4 blocks'), findsNothing);
    expect(find.text('0/4 blocks'), findsOneWidget, reason: 'placed, not yet done');
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('Place puts one rock down and leaves the other waiting', (tester) async {
    await db.dayPlanDao.getOrCreatePlanForDate(todayIso);
    await _pump(tester, db);

    final placeButtons = find.text('Place');
    expect(placeButtons, findsNWidgets(2));
    // The 90-minute rock's row comes first (objective order).
    await tester.tap(placeButtons.first);
    await _settle(tester);

    final plan = (await db.dayPlanDao.getPlanForDate(todayIso))!;
    final blocks = await db.dayPlanDao.getBlocksForPlan(plan.id);
    expect(blocks.single.label, 'Finish the adapter');
    expect(blocks.single.endMinute - blocks.single.startMinute, 90);
    expect(find.text('Place'), findsOneWidget);
    expect(find.text('Place all'), findsOneWidget);
    expect(find.text('Drag it onto the hour you want, or Place.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('a rock dragged onto the grid becomes a block of its full length',
      (tester) async {
    await db.dayPlanDao.getOrCreatePlanForDate(todayIso);
    await _pump(tester, db);

    // Drag the 90-minute rock onto a grid slot a few rows down.
    final row = find.text('Finish the adapter');
    final targets = find.byWidgetPredicate(
        (w) => w is DragTarget<Object>, skipOffstage: false);
    expect(targets, findsWidgets);
    final target = tester.getCenter(targets.at(6));
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await _settle(tester);

    final plan = (await db.dayPlanDao.getPlanForDate(todayIso))!;
    final blocks = await db.dayPlanDao.getBlocksForPlan(plan.id);
    expect(blocks, hasLength(1));
    expect(blocks.single.label, 'Finish the adapter');
    expect(blocks.single.endMinute - blocks.single.startMinute, 90);
    expect(blocks.single.objectiveId, isNotNull);
    expect(blocks.single.kind, 'focus');
    expect(find.text('Place'), findsOneWidget, reason: 'the 30-minute rock still waits');
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });
}
