import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/templates/instances/stakeholder_map/stakeholder_map_model.dart';
import 'package:keel/features/canvas/templates/instances/stakeholder_map/stakeholder_map_view.dart';
import 'package:provider/provider.dart';

Future<void> runStakeholderMapTest(
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
        home: Scaffold(body: StakeholderMapView(template: template)),
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

  Future<void> insertPerson(String id, String name, {String? role}) {
    return db.peopleDao.insertPerson(PersonsCompanion.insert(
      id: id,
      projectId: 'p1',
      name: name,
      role: Value(role),
    ));
  }

  Future<CanvasTemplate> insertTemplate(String content) async {
    await db.canvasTemplatesDao.insertTemplate(
      CanvasTemplatesCompanion.insert(
        id: 't1',
        projectId: 'p1',
        templateType: 'stakeholder_map',
        name: 'Map',
        content: content,
      ),
    );
    return (await db.canvasTemplatesDao.getTemplateById('t1'))!;
  }

  testWidgets(
      'renders axis labels and the four quadrant labels in faint text',
      (tester) async {
    final t = await insertTemplate('{}');
    await runStakeholderMapTest(tester, db, t, () async {
      expect(find.text('LOW INTEREST'), findsOneWidget);
      expect(find.text('HIGH INTEREST'), findsOneWidget);
      expect(find.text('MANAGE CLOSELY'), findsOneWidget);
      expect(find.text('KEEP SATISFIED'), findsOneWidget);
      expect(find.text('KEEP INFORMED'), findsOneWidget);
      expect(find.text('MONITOR'), findsOneWidget);
      // Add button visible.
      expect(find.text('Add stakeholder'), findsOneWidget);
    });
  });

  testWidgets(
      'Add stakeholder dropdown lists project Persons not yet on the map; '
      'tapping one places it at the centre by default', (tester) async {
    await insertPerson('person-a', 'Sarah Chen', role: 'CDO');
    await insertPerson('person-b', 'Jen Rebeiro',
        role: 'Programme Sponsor');
    final t = await insertTemplate('{}');
    await runStakeholderMapTest(tester, db, t, () async {
      // Open the Add menu.
      await tester.tap(find.text('Add stakeholder'));
      await tester.pumpAndSettle();
      expect(find.text('Sarah Chen'), findsOneWidget);
      expect(find.text('Jen Rebeiro'), findsOneWidget);

      // Pick Sarah Chen.
      await tester.tap(find.text('Sarah Chen'));
      await tester.pumpAndSettle();

      final content = StakeholderMapContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.stakeholders, hasLength(1));
      expect(content.stakeholders.single.personId, 'person-a');
      expect(content.stakeholders.single.positionX, 0.5);
      expect(content.stakeholders.single.positionY, 0.5);

      // After placing, the Add menu should no longer offer Sarah.
      await tester.tap(find.text('Add stakeholder'));
      await tester.pumpAndSettle();
      expect(find.text('Jen Rebeiro'), findsOneWidget);
      // No "Sarah Chen" inside the popup (the dot label is also rendered
      // on the grid, so we just assert the popup menu doesn't contain
      // her by checking the count of "Sarah Chen" Text widgets — should
      // be exactly the on-grid one, not two).
      expect(find.text('Sarah Chen'), findsOneWidget);
    });
  });

  testWidgets('tapping a dot opens the side panel with name + role',
      (tester) async {
    await insertPerson('person-a', 'Sarah Chen', role: 'CDO');
    final t = await insertTemplate(StakeholderMapContent(stakeholders: [
      const StakeholderDot(
        id: 'd1',
        personId: 'person-a',
        positionX: 0.85,
        positionY: 0.85,
        notes: 'first note',
      ),
    ]).encode());
    await runStakeholderMapTest(tester, db, t, () async {
      // Tap the dot label. (The label text is the only finder we know is
      // exactly the person's name and sits inside the dot widget.)
      await tester.tap(find.text('Sarah Chen').first);
      await tester.pumpAndSettle();
      // Side panel header appears.
      expect(find.text('STAKEHOLDER'), findsOneWidget);
      // Role appears in the panel.
      expect(find.text('CDO'), findsOneWidget);
      // Quadrant label reflects the dot position.
      expect(find.textContaining('Keep Informed'), findsOneWidget);
      // Notes pre-populated.
      expect(find.text('first note'), findsOneWidget);
    });
  });

  testWidgets(
      'editing notes in the side panel persists to the dot JSON',
      (tester) async {
    await insertPerson('p1', 'Anna');
    final t = await insertTemplate(StakeholderMapContent(stakeholders: [
      const StakeholderDot(id: 'd1', personId: 'p1'),
    ]).encode());
    await runStakeholderMapTest(tester, db, t, () async {
      await tester.tap(find.text('Anna').first);
      await tester.pumpAndSettle();

      final notes = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').contains('Engagement strategy'));
      expect(notes, findsOneWidget);
      await tester.enterText(notes, 'Follow up after legal review');
      await tester.pump();

      final content = StakeholderMapContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.stakeholders.single.notes,
          'Follow up after legal review');
    });
  });

  testWidgets(
      '"Remove from map" deletes the dot and closes the side panel',
      (tester) async {
    await insertPerson('p1', 'Anna');
    final t = await insertTemplate(StakeholderMapContent(stakeholders: [
      const StakeholderDot(id: 'd1', personId: 'p1'),
    ]).encode());
    await runStakeholderMapTest(tester, db, t, () async {
      await tester.tap(find.text('Anna').first);
      await tester.pumpAndSettle();
      expect(find.text('STAKEHOLDER'), findsOneWidget);

      await tester.tap(find.text('Remove from map'));
      await tester.pumpAndSettle();

      // Dot gone from DB.
      final content = StakeholderMapContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.stakeholders, isEmpty);
      // Side panel header no longer present.
      expect(find.text('STAKEHOLDER'), findsNothing);
    });
  });
}
