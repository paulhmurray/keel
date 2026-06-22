import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/templates/instances/retrospective/retro_model.dart';
import 'package:keel/features/canvas/templates/instances/retrospective/retro_view.dart';
import 'package:provider/provider.dart';

Future<void> runRetroTest(
  WidgetTester tester,
  AppDatabase db,
  CanvasTemplate template,
  Future<void> Function() body,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 900);
  await tester.pumpWidget(
    Provider<AppDatabase>.value(
      value: db,
      child: MaterialApp(
        home: Scaffold(body: RetroView(template: template)),
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
        templateType: 'retrospective',
        name: 'Sprint 14 Retro',
        content: content,
      ),
    );
    return (await db.canvasTemplatesDao.getTemplateById('t1'))!;
  }

  testWidgets('renders all four column headers + subtitles', (tester) async {
    final t = await insertTemplate('{}');
    await runRetroTest(tester, db, t, () async {
      expect(find.text('START'), findsOneWidget);
      expect(find.text('STOP'), findsOneWidget);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(find.text('LEARN'), findsOneWidget);
      expect(find.text("what's not happening yet"), findsOneWidget);
      expect(find.text("what's not working"), findsOneWidget);
      expect(find.text("what's working"), findsOneWidget);
      expect(find.text('insights to carry forward'), findsOneWidget);
      // Four Add buttons, one per column.
      expect(find.text('Add'), findsNWidgets(4));
    });
  });

  testWidgets(
      'adding an item in Start persists title + notes via the controllers',
      (tester) async {
    final t = await insertTemplate('{}');
    await runRetroTest(tester, db, t, () async {
      // Tap the Start column's Add (first one).
      await tester.tap(find.text('Add').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The new card surfaces a Title and Notes input.
      final titleField = find.byWidgetPredicate((w) =>
          w is TextField && (w.decoration?.hintText ?? '') == 'Title');
      final notesField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '') == 'Notes (optional)');
      expect(titleField, findsOneWidget);
      expect(notesField, findsOneWidget);

      await tester.enterText(titleField, 'Weekly sponsor catch-up');
      await tester.enterText(notesField, 'pre-board confidence');
      await tester.pump();

      final reloaded =
          await db.canvasTemplatesDao.getTemplateById('t1');
      final content = RetroContent.decode(reloaded!.content);
      expect(content.start, hasLength(1));
      expect(content.start.first.title, 'Weekly sponsor catch-up');
      expect(content.start.first.notes, 'pre-board confidence');
    });
  });

  testWidgets(
      'voting increments the count and re-sorts the column by votes',
      (tester) async {
    final t = await insertTemplate(RetroContent(start: const [
      RetroItem(id: 'a', title: 'A', votes: 0, sortOrder: 0),
      RetroItem(id: 'b', title: 'B', votes: 0, sortOrder: 1),
    ]).encode());
    await runRetroTest(tester, db, t, () async {
      // Two thumb-up buttons (one per item). Identify by icon.
      final voteButtons = find.byIcon(Icons.thumb_up_outlined);
      expect(voteButtons, findsNWidgets(2));

      // Tap the second item's vote button twice — that's B in initial
      // order. The thumb_up icon for B is at index 1 since items are
      // sorted by votes desc + sortOrder; with equal votes the
      // sortOrder breaks the tie so [A, B] order holds.
      await tester.tap(voteButtons.at(1));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.thumb_up_outlined).at(0));
      // After the first vote, B has 1 vote and re-sorts to position 0.
      // So the second tap (at index 0) hits B again. Now B has 2 votes.
      await tester.pump();

      final reloaded =
          await db.canvasTemplatesDao.getTemplateById('t1');
      final content = RetroContent.decode(reloaded!.content);
      // B now has 2 votes and is first; A still has 0.
      expect(content.start.first.id, 'b');
      expect(content.start.first.votes, 2);
      expect(content.start.last.votes, 0);
    });
  });

  testWidgets(
      'Promote to Action is offered on Start but NOT on Stop/Continue/Learn',
      (tester) async {
    final t = await insertTemplate(RetroContent(start: const [
      RetroItem(id: 's1', title: 'Sponsor catch-up'),
    ], stop: const [
      RetroItem(id: 'st1', title: 'Update sprawl'),
    ], continueItems: const [
      RetroItem(id: 'c1', title: 'Retros'),
    ], learn: const [
      RetroItem(id: 'l1', title: 'Need more time'),
    ]).encode());
    await runRetroTest(tester, db, t, () async {
      final menus = find.byTooltip('Item actions');
      expect(menus, findsNWidgets(4));

      // Item 0 is the Start item (column order: Start, Stop, Continue,
      // Learn; single item each).
      await tester.tap(menus.at(0));
      await tester.pumpAndSettle();
      expect(find.text('Promote to Action'), findsOneWidget);
      // Dismiss.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Stop, Continue, Learn shouldn't offer promotion.
      for (final idx in [1, 2, 3]) {
        await tester.tap(menus.at(idx));
        await tester.pumpAndSettle();
        expect(find.text('Promote to Action'), findsNothing,
            reason: 'menu $idx should not show Promote to Action');
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    });
  });

  testWidgets(
      'Promoting a Start item creates the Action with source=retrospective '
      'and stamps the item', (tester) async {
    final t = await insertTemplate(RetroContent(start: const [
      RetroItem(
        id: 's1',
        title: 'Weekly sponsor catch-up',
        notes: 'pre-board confidence',
      ),
    ]).encode());
    await runRetroTest(tester, db, t, () async {
      await tester.tap(find.byTooltip('Item actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote to Action'));
      await tester.pumpAndSettle();

      final actions = await db.actionsDao.getActionsForProject('p1');
      expect(actions, hasLength(1));
      expect(actions.first.description,
          contains('Weekly sponsor catch-up'));
      expect(actions.first.description,
          contains('pre-board confidence'));
      expect(actions.first.source, 'retrospective');
      expect(actions.first.sourceNote,
          contains('Retro: Sprint 14 Retro (Start)'));

      final content = RetroContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.start.first.promotedToActionId, actions.first.id);
    });
  });

  testWidgets('Empty-title items cannot be promoted', (tester) async {
    final t = await insertTemplate(RetroContent(start: const [
      RetroItem(id: 's1', title: ''),
    ]).encode());
    await runRetroTest(tester, db, t, () async {
      await tester.tap(find.byTooltip('Item actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote to Action'));
      await tester.pumpAndSettle();

      expect(await db.actionsDao.getActionsForProject('p1'), isEmpty);
      final content = RetroContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.start.first.promotedToActionId, isNull);
    });
  });

  testWidgets('Deleting an item removes it and renumbers sortOrder',
      (tester) async {
    final t = await insertTemplate(RetroContent(start: const [
      RetroItem(id: 'a', title: 'a', sortOrder: 0),
      RetroItem(id: 'b', title: 'b', sortOrder: 1),
    ]).encode());
    await runRetroTest(tester, db, t, () async {
      await tester.tap(find.byTooltip('Item actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      final content = RetroContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.start, hasLength(1));
      expect(content.start.single.sortOrder, 0);
    });
  });
}
