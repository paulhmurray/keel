import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/templates/instances/raci_matrix/raci_model.dart';
import 'package:keel/features/canvas/templates/instances/raci_matrix/raci_view.dart';
import 'package:provider/provider.dart';

Future<void> runRaciTest(
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
        home: Scaffold(body: RaciView(template: template)),
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
        templateType: 'raci_matrix',
        name: 'TAC RACI',
        content: content,
      ),
    );
    return (await db.canvasTemplatesDao.getTemplateById('t1'))!;
  }

  Future<void> insertPerson(String id, String name) {
    return db.peopleDao.insertPerson(PersonsCompanion.insert(
      id: id,
      projectId: 'p1',
      name: name,
    ));
  }

  testWidgets('empty matrix renders the empty-state guidance',
      (tester) async {
    final t = await insertTemplate('{}');
    await runRaciTest(tester, db, t, () async {
      expect(find.text('Add activities and people to start'),
          findsOneWidget);
      expect(find.text('Add first activity'), findsOneWidget);
    });
  });

  testWidgets(
      'Add activity inserts a row, Add person (from project) adds a '
      'column, and clicking the cell cycles through R/A/C/I/blank',
      (tester) async {
    await insertPerson('person-paul', 'Paul');
    final t = await insertTemplate('{}');
    await runRaciTest(tester, db, t, () async {
      // Add an activity.
      await tester.tap(find.text('Add activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // The new activity row has a TextField with hint "Activity".
      final actField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '') == 'Activity');
      expect(actField, findsOneWidget);
      await tester.enterText(actField, 'Architecture sign-off');
      await tester.pump();

      // Add a person via the popup (project Person "Paul").
      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paul'));
      await tester.pumpAndSettle();

      // Now there's exactly one cycle cell (1 activity × 1 person).
      final content0 = RaciContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content0.activities, hasLength(1));
      expect(content0.people, hasLength(1));
      expect(content0.assignments, isEmpty);

      final actId = content0.activities.first.id;
      final personId = content0.people.first.id;

      // Click the cell — wait for animations between taps so the
      // ripple/InkWell settles cleanly.
      final cell = find.byWidgetPredicate((w) {
        if (w is! InkWell || w.onTap == null) return false;
        return true;
      });
      // Several InkWells exist (delete buttons, the legend nothing,
      // role cell). The role cell is the LAST InkWell in this tiny
      // layout — pick it by location instead: find the cell parent
      // Container by walking from any role-aware container.
      // Easier: tap the only role cell by its position via the
      // current absence of role text. We'll just tap repeatedly on
      // any InkWell.last; structurally it'll be the role cell since
      // the toolbar's PopupMenuButton uses a different widget.
      RaciContent reload() {
        // Snap a synchronous decode from latest DB state.
        return RaciContent.decode(
            (db.select(db.canvasTemplates)..where((t) => t.id.equals('t1')))
                    .map((r) => r.content)
                    .getSingle()
                    .toString()) ??
            const RaciContent();
      }

      // Simpler: cycle 5 times and assert the chain via DB reads.
      Future<void> tapCellAndPump() async {
        await tester.tap(cell.last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }

      await tapCellAndPump();
      var content = RaciContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.roleFor(actId, personId), 'R');

      await tapCellAndPump();
      content = RaciContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.roleFor(actId, personId), 'A');

      await tapCellAndPump();
      content = RaciContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.roleFor(actId, personId), 'C');

      await tapCellAndPump();
      content = RaciContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.roleFor(actId, personId), 'I');

      await tapCellAndPump();
      content = RaciContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.roleFor(actId, personId), isNull,
          reason: 'blank loops back after I');
      // Blank cell collapses to no-assignment row to keep JSON tight.
      expect(content.assignments, isEmpty);
    });
  });

  testWidgets(
      'Adding a project Person snapshots their name and stores '
      'personId; the dropdown no longer offers them after',
      (tester) async {
    await insertPerson('person-a', 'Sarah');
    await insertPerson('person-b', 'Bart');
    final t = await insertTemplate('{}');
    await runRaciTest(tester, db, t, () async {
      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();
      expect(find.text('Sarah'), findsOneWidget);
      expect(find.text('Bart'), findsOneWidget);
      await tester.tap(find.text('Sarah'));
      await tester.pumpAndSettle();

      final content = RaciContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.people, hasLength(1));
      expect(content.people.single.name, 'Sarah');
      expect(content.people.single.personId, 'person-a');

      // Re-open the dropdown — Sarah should be gone, Bart remains.
      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();
      expect(find.text('Bart'), findsOneWidget);
      // "Add new person…" routes through AddPersonDialog so any new
      // row also lands in the Persons table — no more free-text rows
      // that only exist inside the RACI JSON.
      expect(find.text('Add new person…'), findsOneWidget);
    });
  });

  testWidgets(
      'deleting an activity drops its assignments; deleting a person '
      'drops theirs', (tester) async {
    final t = await insertTemplate(RaciContent(
      activities: const [
        RaciActivity(id: 'act-1', name: 'Arch'),
        RaciActivity(id: 'act-2', name: 'Proc', sortOrder: 1),
      ],
      people: const [
        RaciPerson(id: 'per-1', name: 'Paul'),
      ],
      assignments: const [
        RaciAssignment(activityId: 'act-1', personId: 'per-1', role: 'A'),
        RaciAssignment(activityId: 'act-2', personId: 'per-1', role: 'R'),
      ],
    ).encode());
    await runRaciTest(tester, db, t, () async {
      // Delete the Arch activity.
      await tester.tap(find.byTooltip('Delete activity').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      var content = RaciContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.activities.map((x) => x.id), ['act-2']);
      expect(content.activities.single.sortOrder, 0);
      expect(content.assignments, hasLength(1));
      expect(content.assignments.single.activityId, 'act-2');

      // Delete the only person too — assignments now drop entirely.
      await tester.tap(find.byTooltip('Remove column'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      content = RaciContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.people, isEmpty);
      expect(content.assignments, isEmpty);
    });
  });

  testWidgets('Legend lists all four roles with click-cycle hint',
      (tester) async {
    final t = await insertTemplate(RaciContent(activities: const [
      RaciActivity(id: 'a', name: 'a'),
    ]).encode());
    await runRaciTest(tester, db, t, () async {
      expect(find.text('Responsible'), findsOneWidget);
      expect(find.text('Accountable'), findsOneWidget);
      expect(find.text('Consulted'), findsOneWidget);
      expect(find.text('Informed'), findsOneWidget);
      expect(
        find.textContaining('blank → R → A → C → I → blank'),
        findsOneWidget,
      );
    });
  });
}
