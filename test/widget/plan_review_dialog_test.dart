import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/llm/llm_client.dart';
import 'package:keel/features/timeline/gantt/plan_review_dialog.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// The review dialog: graph findings up front, then the model's cards.
/// Accepting a reorder adds an arrow; accepting a missing step or a
/// milestone creates the row with its arrows.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P'));
    await db.programmeGanttDao.upsertHeader(const ProgrammeHeadersCompanion(
      id: Value('h'), projectId: Value('p1'), month0Date: Value('2026-06-01'),
    ));
    await db.programmeGanttDao.upsertWorkPackage(const TimelineWorkPackagesCompanion(
      id: Value('wp'), projectId: Value('p1'), name: Value('Build'), sortOrder: Value(0),
    ));
    // Build (Sep–Nov) wrongly arrowed to wait on Test (Dec).
    await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('build'), workPackageId: Value('wp'), projectId: Value('p1'),
      name: Value('Build'), startMonth: Value(3), endMonth: Value(5), sortOrder: Value(0),
    ));
    // Sort orders with a gap: the row after Build sits at 7, not 1. A
    // slot computed from sortOrder values would index past the list.
    await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
      id: Value('test'), workPackageId: Value('wp'), projectId: Value('p1'),
      name: Value('Test'), startMonth: Value(6), endMonth: Value(6), sortOrder: Value(7),
    ));
    await db.programmeGanttDao.upsertDependency(const TimelineDependenciesCompanion(
      id: Value('d1'), projectId: Value('p1'),
      fromActivityId: Value('test'), toActivityId: Value('build'),
      dependencyType: Value('finish_to_start'),
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
                      PlanReviewDialog(db: db, projectId: 'p1', client: client),
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

  testWidgets('findings are listed without AI', (tester) async {
    await open(tester);
    expect(find.textContaining('Build (Sep 2026–Nov 2026) starts before Test'),
        findsOneWidget);
    expect(find.textContaining('no milestone or gate'), findsOneWidget);
    expect(find.text('Ask AI to review the whole plan'), findsNothing,
        reason: 'no key, no client');
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('with AI: a reorder adds an arrow, a missing step and a gate '
      'are created with arrows', (tester) async {
    await open(tester, client: _FakeClient());
    await tester.tap(find.text('Ask AI to review the whole plan'));
    await tester.pumpAndSettle();

    // Card 1: reorder.
    expect(find.text('ORDER'), findsOneWidget);
    expect(find.text('Build should finish before Test starts'), findsOneWidget);
    expect(find.textContaining('replacing the arrow that currently points the other way'),
        findsOneWidget);
    await tester.tap(find.text('Add the arrow'));
    await tester.pumpAndSettle();

    // Card 2: missing step after Build.
    expect(find.text('MISSING STEP'), findsOneWidget);
    expect(find.text('Data migration dry run'), findsOneWidget);
    expect(find.textContaining('in Nov 2026, after Build, before Test'), findsOneWidget);
    await tester.tap(find.text('Add the activity'));
    await tester.pumpAndSettle();

    // Card 3: gate after Test.
    expect(find.text('MILESTONE'), findsOneWidget);
    await tester.tap(find.text('Add the gate'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 applied.'), findsOneWidget);

    final deps = await db.programmeGanttDao.getDependencies('p1');
    expect(deps.any((d) => d.fromActivityId == 'build' && d.toActivityId == 'test'),
        isTrue, reason: 'the reorder arrow');
    expect(deps.any((d) => d.fromActivityId == 'test' && d.toActivityId == 'build'),
        isFalse, reason: 'the backwards arrow is gone, so no cycle');
    final acts = await db.programmeGanttDao.getActivitiesForProject('p1');
    final dryRun = acts.firstWhere((a) => a.name == 'Data migration dry run');
    expect(dryRun.activityType, 'activity');
    expect(dryRun.startMonth, 5, reason: 'lands when Build ends');
    expect(dryRun.notes, contains('Added on plan review'));
    expect(deps.any((d) => d.fromActivityId == 'build' && d.toActivityId == dryRun.id), isTrue);
    expect(deps.any((d) => d.fromActivityId == dryRun.id && d.toActivityId == 'test'), isTrue);
    final build = acts.firstWhere((a) => a.id == 'build');
    final test = acts.firstWhere((a) => a.id == 'test');
    expect(dryRun.sortOrder, greaterThan(build.sortOrder));
    expect(dryRun.sortOrder, lessThan(test.sortOrder), reason: 'slotted after Build');
    final gate = acts.firstWhere((a) => a.name == 'Go/no-go');
    expect(gate.activityType, 'gate');
    expect(gate.startMonth, 6);
    expect(deps.any((d) => d.fromActivityId == 'test' && d.toActivityId == gate.id), isTrue);
  });
}

class _FakeClient implements LLMClient {
  @override
  Future<String> complete({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1000,
  }) async =>
      '''
      {"suggestions": [
        {"kind": "reorder", "first_id": "build", "then_id": "test", "message": "Testing follows building."},
        {"kind": "missing", "work_package_id": "wp", "name": "Data migration dry run", "after_id": "build", "before_id": "test", "message": "Nothing rehearses the cut-over."},
        {"kind": "point", "work_package_id": "wp", "name": "Go/no-go", "type": "gate", "after_id": "test", "message": "No decision point before go-live."}
      ]}
      ''';

  @override
  Stream<String> stream({required String systemPrompt, required String userMessage}) =>
      Stream.value('');
}
