import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/templates/instances/user_story_map/usm_model.dart';
import 'package:keel/features/canvas/templates/instances/user_story_map/usm_view.dart';
import 'package:provider/provider.dart';

Future<void> runUsmTest(
  WidgetTester tester,
  AppDatabase db,
  CanvasTemplate template,
  Future<void> Function() body,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1800, 1000);
  await tester.pumpWidget(
    Provider<AppDatabase>.value(
      value: db,
      child: MaterialApp(
        home: Scaffold(body: UsmView(template: template)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  try {
    await body();
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P1'));
  });

  tearDown(() async => db.close());

  Future<CanvasTemplate> insertTemplate(String content) async {
    await db.canvasTemplatesDao.insertTemplate(
      CanvasTemplatesCompanion.insert(
        id: 't1',
        projectId: 'p1',
        templateType: 'user_story_map',
        name: 'TAC USM',
        content: content,
      ),
    );
    return (await db.canvasTemplatesDao.getTemplateById('t1'))!;
  }

  testWidgets('empty map shows the start-mapping empty state',
      (tester) async {
    final t = await insertTemplate('{}');
    await runUsmTest(tester, db, t, () async {
      expect(find.text('Start mapping the user journey'), findsOneWidget);
      // Both Add buttons present (toolbar + empty-state row).
      expect(find.text('Add activity'), findsNWidgets(2));
      expect(find.text('Add release'), findsNWidgets(2));
    });
  });

  testWidgets(
      'adding activity → task → release → story persists each step',
      (tester) async {
    final t = await insertTemplate('{}');
    await runUsmTest(tester, db, t, () async {
      // Add an activity from the toolbar.
      await tester.tap(find.text('Add activity').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Type the activity name into the new field.
      final activityField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '') == 'Activity');
      expect(activityField, findsOneWidget);
      await tester.enterText(activityField, 'Discover');
      await tester.pump();

      // Add a task via the "+" inside the activity header.
      await tester.tap(find.byTooltip('Add task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final taskField = find.byWidgetPredicate((w) =>
          w is TextField && (w.decoration?.hintText ?? '') == 'Task');
      expect(taskField, findsOneWidget);
      await tester.enterText(taskField, 'Search destinations');
      await tester.pump();

      // Add a release from the toolbar.
      await tester.tap(find.text('Add release').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Add a story in the (task, release) cell.
      await tester.tap(find.text('Add story'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The story side panel appears — type a title.
      final titleField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '') == 'What is the story?');
      expect(titleField, findsOneWidget);
      await tester.enterText(titleField, 'Search by city');
      await tester.pump();

      // Verify persisted shape.
      final content = UsmContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.activities.single.name, 'Discover');
      expect(content.activities.single.tasks.single.name,
          'Search destinations');
      expect(content.releases.single.name, isNotEmpty);
      expect(content.stories, hasLength(1));
      expect(content.stories.single.title, 'Search by city');
    });
  });

  testWidgets(
      'story side panel persists description, estimate and tags',
      (tester) async {
    final t = await insertTemplate(UsmContent(
      activities: const [
        UsmActivity(id: 'a1', name: 'A', tasks: [
          UsmTask(id: 't1', name: 'T'),
        ]),
      ],
      releases: const [UsmRelease(id: 'r1', name: 'MVP')],
      stories: const [
        UsmStory(
          id: 's1',
          taskId: 't1',
          releaseId: 'r1',
          title: 'Story',
        ),
      ],
    ).encode());
    await runUsmTest(tester, db, t, () async {
      // Click the story card to open the side panel.
      await tester.tap(find.text('Story'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Description.
      final descField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '') == 'Free-form context');
      expect(descField, findsOneWidget);
      await tester.enterText(descField, 'a meaningful goal');
      await tester.pump();

      // Estimate.
      final estField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '')
              .contains('S / M / L'));
      expect(estField, findsOneWidget);
      await tester.enterText(estField, 'M');
      await tester.pump();

      // Tags — type "search,frontend" — comma auto-commits.
      final tagsField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').contains('Add tag'));
      expect(tagsField, findsOneWidget);
      await tester.enterText(tagsField, 'search,frontend,');
      await tester.pump();

      final content = UsmContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      final story = content.stories.single;
      expect(story.description, 'a meaningful goal');
      expect(story.estimate, 'M');
      expect(story.tags, ['search', 'frontend']);
    });
  });

  testWidgets(
      'acceptance criteria splits on newlines and ignores blank lines',
      (tester) async {
    final t = await insertTemplate(UsmContent(
      activities: const [
        UsmActivity(id: 'a1', name: 'A', tasks: [
          UsmTask(id: 't1', name: 'T'),
        ]),
      ],
      releases: const [UsmRelease(id: 'r1', name: 'MVP')],
      stories: const [
        UsmStory(
          id: 's1',
          taskId: 't1',
          releaseId: 'r1',
          title: 'Story',
        ),
      ],
    ).encode());
    await runUsmTest(tester, db, t, () async {
      await tester.tap(find.text('Story'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final acField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '') ==
              'One acceptance criterion per line');
      expect(acField, findsOneWidget);
      await tester.enterText(
        acField,
        'Results within 2 seconds\n\nEmpty state shown\n   \n',
      );
      await tester.pump();

      final content = UsmContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.stories.single.acceptanceCriteria, [
        'Results within 2 seconds',
        'Empty state shown',
      ]);
    });
  });

  testWidgets(
      'deleting an activity also drops its tasks and stories',
      (tester) async {
    final t = await insertTemplate(UsmContent(
      activities: const [
        UsmActivity(id: 'a1', name: 'Activity 1', tasks: [
          UsmTask(id: 't1', name: 'T1'),
        ]),
        UsmActivity(id: 'a2', name: 'Activity 2', sortOrder: 1, tasks: [
          UsmTask(id: 't2', name: 'T2'),
        ]),
      ],
      releases: const [UsmRelease(id: 'r1', name: 'MVP')],
      stories: const [
        UsmStory(
            id: 's1', taskId: 't1', releaseId: 'r1', title: 'kept-not'),
        UsmStory(
            id: 's2', taskId: 't2', releaseId: 'r1', title: 'kept-yes'),
      ],
    ).encode());
    await runUsmTest(tester, db, t, () async {
      // Delete the first activity.
      await tester.tap(find.byTooltip('Delete activity').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final content = UsmContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.activities.map((a) => a.id), ['a2']);
      expect(content.activities.single.tasks.map((tt) => tt.id), ['t2']);
      // Story s1 was in the deleted activity's task — gone too.
      expect(content.stories.map((s) => s.id), ['s2']);
    });
  });

  testWidgets(
      'deleting a release drops stories in that release',
      (tester) async {
    final t = await insertTemplate(UsmContent(
      activities: const [
        UsmActivity(id: 'a1', name: 'A', tasks: [
          UsmTask(id: 't1', name: 'T'),
        ]),
      ],
      releases: const [
        UsmRelease(id: 'r1', name: 'MVP'),
        UsmRelease(id: 'r2', name: 'Release 2', sortOrder: 1),
      ],
      stories: const [
        UsmStory(id: 's1', taskId: 't1', releaseId: 'r1', title: 'mvp'),
        UsmStory(
            id: 's2', taskId: 't1', releaseId: 'r2', title: 'release2'),
      ],
    ).encode());
    await runUsmTest(tester, db, t, () async {
      // Delete the first release (MVP).
      await tester.tap(find.byTooltip('Delete release').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final content = UsmContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.releases.map((r) => r.id), ['r2']);
      expect(content.stories.map((s) => s.id), ['s2']);
    });
  });
}
