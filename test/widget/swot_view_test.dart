import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/templates/instances/swot/swot_model.dart';
import 'package:keel/features/canvas/templates/instances/swot/swot_view.dart';
import 'package:provider/provider.dart';

/// Mounts SwotView in a minimal provider scope and cleans up the Drift
/// deferred timer the same way the other canvas widget tests do.
Future<void> runSwotTest(
  WidgetTester tester,
  AppDatabase db,
  CanvasTemplate template,
  Future<void> Function() body,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1400, 900);
  await tester.pumpWidget(
    Provider<AppDatabase>.value(
      value: db,
      child: MaterialApp(
        home: Scaffold(body: SwotView(template: template)),
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
        templateType: 'swot',
        name: 'Q3 SWOT',
        content: content,
      ),
    );
    return (await db.canvasTemplatesDao.getTemplateById('t1'))!;
  }

  testWidgets('renders all four quadrant headers', (tester) async {
    final t = await insertTemplate('{}');
    await runSwotTest(tester, db, t, () async {
      expect(find.text('STRENGTHS'), findsOneWidget);
      expect(find.text('WEAKNESSES'), findsOneWidget);
      expect(find.text('OPPORTUNITIES'), findsOneWidget);
      expect(find.text('THREATS'), findsOneWidget);
      expect(find.text('INTERNAL'), findsOneWidget);
      expect(find.text('EXTERNAL'), findsOneWidget);
    });
  });

  testWidgets(
      'tapping Add in a quadrant inserts an item and typing into it '
      'persists', (tester) async {
    final t = await insertTemplate('{}');
    await runSwotTest(tester, db, t, () async {
      // Four "Add" buttons, one per quadrant. Tap the first one
      // (which is Strengths in the top-left).
      expect(find.text('Add'), findsNWidgets(4));
      await tester.tap(find.text('Add').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final field = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '') == 'Add an item');
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Experienced PM team');
      await tester.pump();

      final reloaded =
          await db.canvasTemplatesDao.getTemplateById('t1');
      final content = SwotContent.decode(reloaded!.content);
      expect(content.strengths, hasLength(1));
      expect(content.strengths.first.text, 'Experienced PM team');
    });
  });

  testWidgets(
      'promote-to-Risk is offered on Threats and creates a Risk row '
      'with source=swot', (tester) async {
    final t = await insertTemplate(SwotContent(threats: const [
      SwotItem(id: 't1', text: 'Vendor delivery risk'),
    ]).encode());
    await runSwotTest(tester, db, t, () async {
      await tester.tap(find.byTooltip('Item actions'));
      await tester.pumpAndSettle();
      // Both promote options are offered for threats.
      expect(find.text('Promote to Risk'), findsOneWidget);
      expect(find.text('Promote to Action'), findsOneWidget);

      await tester.tap(find.text('Promote to Risk'));
      await tester.pumpAndSettle();

      final risks = await db.raidDao.getRisksForProject('p1');
      expect(risks, hasLength(1));
      expect(risks.first.description, 'Vendor delivery risk');
      expect(risks.first.source, 'swot');
      expect(risks.first.sourceNote,
          contains('SWOT: Q3 SWOT (Threats)'));

      // The item is now stamped promoted in the template JSON.
      final content = SwotContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.threats.first.promotedToType, 'risk');
      expect(content.threats.first.promotedToId, risks.first.id);
    });
  });

  testWidgets(
      'promote-to-Risk is NOT offered on Opportunities; only Action is',
      (tester) async {
    final t = await insertTemplate(SwotContent(opportunities: const [
      SwotItem(id: 'o1', text: 'Government funding'),
    ]).encode());
    await runSwotTest(tester, db, t, () async {
      await tester.tap(find.byTooltip('Item actions'));
      await tester.pumpAndSettle();
      expect(find.text('Promote to Risk'), findsNothing);
      expect(find.text('Promote to Action'), findsOneWidget);

      await tester.tap(find.text('Promote to Action'));
      await tester.pumpAndSettle();

      final actions = await db.actionsDao.getActionsForProject('p1');
      expect(actions, hasLength(1));
      expect(actions.first.description, 'Government funding');
      expect(actions.first.source, 'swot');
      expect(actions.first.sourceNote,
          contains('SWOT: Q3 SWOT (Opportunities)'));
    });
  });

  testWidgets(
      'deleting an item removes it from its quadrant in the JSON',
      (tester) async {
    final t = await insertTemplate(SwotContent(strengths: const [
      SwotItem(id: 's1', text: 'one'),
      SwotItem(id: 's2', text: 'two', sortOrder: 1),
    ]).encode());
    await runSwotTest(tester, db, t, () async {
      // Two item-action menus, one per item.
      final menus = find.byTooltip('Item actions');
      expect(menus, findsNWidgets(2));
      await tester.tap(menus.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      final content = SwotContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.strengths, hasLength(1));
      expect(content.strengths.single.id, 's2');
      expect(content.strengths.single.sortOrder, 0,
          reason: 'remaining items should be renumbered from 0');
    });
  });

  testWidgets(
      'empty-text items cannot be promoted (no DB write, no stamp)',
      (tester) async {
    final t = await insertTemplate(SwotContent(threats: const [
      SwotItem(id: 't1', text: ''),
    ]).encode());
    await runSwotTest(tester, db, t, () async {
      await tester.tap(find.byTooltip('Item actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote to Risk'));
      await tester.pumpAndSettle();

      expect(await db.raidDao.getRisksForProject('p1'), isEmpty);
      final content = SwotContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.threats.first.promotedToType, isNull);
    });
  });
}
