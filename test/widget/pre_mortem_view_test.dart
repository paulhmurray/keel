import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/templates/instances/pre_mortem/pre_mortem_model.dart';
import 'package:keel/features/canvas/templates/instances/pre_mortem/pre_mortem_view.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:keel/shared/widgets/person_picker_field.dart';
import 'package:provider/provider.dart';

/// Pumps a PreMortemView with the minimum provider scope it needs.
/// Drives Drift's deferred stream-close timer to fire inside the test
/// body via the same trick used by the other canvas widget tests.
Future<void> runPreMortemTest(
  WidgetTester tester,
  AppDatabase db,
  CanvasTemplate template,
  Future<void> Function() body,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1400, 900);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        // PersonPickerField (used by the Owner field) reads
        // SettingsProvider.myName for the "Me" shortcut.
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: PreMortemView(template: template)),
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
        templateType: 'pre_mortem',
        name: 'Test pre-mortem',
        content: content,
      ),
    );
    return (await db.canvasTemplatesDao.getTemplateById('t1'))!;
  }

  testWidgets(
      'renders empty state when content has no causes; typing the goal '
      'persists', (tester) async {
    final t = await insertTemplate('{}');
    await runPreMortemTest(tester, db, t, () async {
      expect(find.textContaining('No causes yet'), findsOneWidget);

      // Type into the Goal field. Find by hint text.
      final goalField = find.byWidgetPredicate(
          (w) => w is TextField && w.maxLines == null);
      await tester.enterText(goalField.first, 'TAC failed Sep 2026');
      await tester.pump();

      final reloaded =
          await db.canvasTemplatesDao.getTemplateById('t1');
      final content = PreMortemContent.decode(reloaded!.content);
      expect(content.goal, 'TAC failed Sep 2026');
    });
  });

  testWidgets(
      'add cause creates a new cause block; typing its description '
      'persists', (tester) async {
    final t = await insertTemplate('{}');
    await runPreMortemTest(tester, db, t, () async {
      await tester.tap(find.text('Add cause'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // A new cause card appears with a Likelihood/Impact row.
      expect(find.text('Likelihood'), findsOneWidget);
      expect(find.text('Impact'), findsOneWidget);

      // Type the cause description (find by hint).
      final causeField = find.byWidgetPredicate((w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').contains('How might this'));
      expect(causeField, findsOneWidget);
      await tester.enterText(causeField, 'M-POWER slipped');
      await tester.pump();

      final reloaded =
          await db.canvasTemplatesDao.getTemplateById('t1');
      final content = PreMortemContent.decode(reloaded!.content);
      expect(content.causes, hasLength(1));
      expect(content.causes.first.description, 'M-POWER slipped');
    });
  });

  testWidgets(
      'promoting a cause to a Risk creates the Risk row and stamps the '
      'cause as promoted', (tester) async {
    final initial = const PreMortemContent(
      goal: 'Test',
      causes: [
        PreMortemCause(
          id: 'c1',
          description: 'M-POWER slip',
          likelihood: 'high',
          impact: 'high',
        ),
      ],
    ).encode();
    final t = await insertTemplate(initial);

    await runPreMortemTest(tester, db, t, () async {
      // Sanity — the cause is rendered.
      expect(find.text('M-POWER slip'), findsOneWidget);

      // Open the cause action menu and pick "Promote to Risk".
      final causeMenu = find.byTooltip('Cause actions');
      expect(causeMenu, findsOneWidget);
      await tester.tap(causeMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote to Risk'));
      await tester.pumpAndSettle();

      // A Risk now exists in RAID for this project.
      final risks = await db.raidDao.getRisksForProject('p1');
      expect(risks, hasLength(1));
      expect(risks.first.description, 'M-POWER slip');
      expect(risks.first.likelihood, 'high');
      expect(risks.first.impact, 'high');
      expect(risks.first.source, 'pre_mortem');
      expect(risks.first.sourceNote,
          contains('Pre-mortem: Test pre-mortem'));

      // The cause is marked promoted in the template JSON.
      final reloaded =
          await db.canvasTemplatesDao.getTemplateById('t1');
      final content = PreMortemContent.decode(reloaded!.content);
      expect(content.causes.first.promotedToRiskId, risks.first.id);

      // The "Promoted to Risk" pill now shows on the cause.
      expect(find.text('Promoted to Risk'), findsOneWidget);
    });
  });

  testWidgets(
      'promoting a mitigation to an Action creates the Action with owner '
      'and source=pre_mortem', (tester) async {
    final initial = const PreMortemContent(
      causes: [
        PreMortemCause(id: 'c1', description: 'Some cause', mitigations: [
          PreMortemMitigation(
            id: 'm1',
            description: 'Weekly escalation',
            owner: 'Paul',
          ),
        ]),
      ],
    ).encode();
    final t = await insertTemplate(initial);

    await runPreMortemTest(tester, db, t, () async {
      // Open the mitigation actions menu.
      final mitMenu = find.byTooltip('Mitigation actions');
      expect(mitMenu, findsOneWidget);
      await tester.tap(mitMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote to Action'));
      await tester.pumpAndSettle();

      final actions = await db.actionsDao.getActionsForProject('p1');
      expect(actions, hasLength(1));
      expect(actions.first.description, 'Weekly escalation');
      expect(actions.first.owner, 'Paul');
      expect(actions.first.source, 'pre_mortem');

      // Template JSON now has the promoted_to_action_id stamped.
      final reloaded =
          await db.canvasTemplatesDao.getTemplateById('t1');
      final content = PreMortemContent.decode(reloaded!.content);
      expect(
        content.causes.first.mitigations.first.promotedToActionId,
        actions.first.id,
      );
    });
  });

  testWidgets(
      'mitigation Owner field is a PersonPickerField wired to the '
      'project Persons (not a free-text TextField)', (tester) async {
    // Seed an existing project person so the picker has something to
    // autocomplete against.
    await db.peopleDao.insertPerson(PersonsCompanion.insert(
      id: 'paul-id',
      projectId: 'p1',
      name: 'Paul',
    ));
    final initial = const PreMortemContent(
      causes: [
        PreMortemCause(id: 'c1', description: 'Some cause', mitigations: [
          PreMortemMitigation(id: 'm1', description: 'A mitigation'),
        ]),
      ],
    ).encode();
    final t = await insertTemplate(initial);

    await runPreMortemTest(tester, db, t, () async {
      // A PersonPickerField is mounted for the mitigation's owner.
      final picker =
          find.byKey(const ValueKey('owner-m1'));
      expect(picker, findsOneWidget);
      expect(
        tester.widget(picker),
        isA<PersonPickerField>(),
      );

      // The picker exposes a TextFormField labelled "Owner" — type into
      // it and confirm the change persists to the mitigation owner via
      // the controller listener.
      final ownerField = find.descendant(
        of: picker,
        matching: find.byType(TextFormField),
      );
      expect(ownerField, findsOneWidget);
      await tester.enterText(ownerField, 'Paul');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final content = PreMortemContent.decode(
          (await db.canvasTemplatesDao.getTemplateById('t1'))!.content);
      expect(content.causes.single.mitigations.single.owner, 'Paul');
    });
  });

  testWidgets('promoting an empty-description cause is rejected',
      (tester) async {
    final initial = const PreMortemContent(causes: [
      PreMortemCause(id: 'c1', description: ''),
    ]).encode();
    final t = await insertTemplate(initial);
    await runPreMortemTest(tester, db, t, () async {
      await tester.tap(find.byTooltip('Cause actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Promote to Risk'));
      await tester.pumpAndSettle();

      // No risk row was created.
      expect(await db.raidDao.getRisksForProject('p1'), isEmpty);
      // The cause is NOT marked promoted.
      final reloaded =
          await db.canvasTemplatesDao.getTemplateById('t1');
      final content = PreMortemContent.decode(reloaded!.content);
      expect(content.causes.first.promotedToRiskId, isNull);
    });
  });
}
