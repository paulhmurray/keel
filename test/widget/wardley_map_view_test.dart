import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/canvas/templates/instances/wardley_map/wardley_map_model.dart';
import 'package:keel/features/canvas/templates/instances/wardley_map/wardley_map_view.dart';
import 'package:provider/provider.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p1', name: 'P1'));
  });
  tearDown(() async => db.close());

  Future<CanvasTemplate> template(String id, String content) async {
    await db.canvasTemplatesDao.insertTemplate(CanvasTemplatesCompanion.insert(
      id: id,
      projectId: 'p1',
      templateType: 'wardley_map',
      name: 'Map $id',
      content: content,
    ));
    return (await db.canvasTemplatesDao.getTemplateById(id))!;
  }

  Future<void> pumpView(WidgetTester tester, CanvasTemplate t) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      Provider<AppDatabase>.value(
        value: db,
        child: MaterialApp(home: Scaffold(body: WardleyMapView(template: t))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
      'selecting a component then switching template does not crash '
      '(disposed-controller regression)', (tester) async {
    final a = await template('t-a',
        '{"components":[{"id":"c1","name":"Website","position_x":0.3,"position_y":0.3}]}');
    final b = await template('t-b',
        '{"components":[{"id":"c2","name":"Auth","position_x":0.4,"position_y":0.5}]}');

    await pumpView(tester, a);
    // Select the component → detail panel (with its TextField) opens.
    await tester.tap(find.text('Website'));
    await tester.pump();
    expect(find.text('COMPONENT'), findsOneWidget);

    // Switch the template on the SAME view → didUpdateWidget. Previously
    // this disposed the panel controllers while the old TextField was
    // still in the tree, throwing "used after being disposed".
    await tester.pumpWidget(
      Provider<AppDatabase>.value(
        value: db,
        child: MaterialApp(home: Scaffold(body: WardleyMapView(template: b))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    // Panel cleared on template switch; the new map's component is shown.
    expect(find.text('COMPONENT'), findsNothing);
    expect(find.text('Auth'), findsOneWidget);
  });

  testWidgets('components stay draggable in link mode (frozen-move regression)',
      (tester) async {
    final t = await template('t-d',
        '{"components":[{"id":"c1","name":"Website","position_x":0.3,"position_y":0.3}]}');
    await pumpView(tester, t);

    // Enter link mode, then drag the component — it must still move.
    await tester.tap(find.text('Link'));
    await tester.pump();
    await tester.drag(find.text('Website'), const Offset(160, 0));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    final saved = await db.canvasTemplatesDao.getTemplateById('t-d');
    final content = WardleyMapContent.decode(saved!.content);
    expect(content.components.single.positionX, greaterThan(0.3));
  });

  testWidgets('select → remove component closes the panel without error',
      (tester) async {
    final t = await template('t-c',
        '{"components":[{"id":"c1","name":"Website","position_x":0.3,"position_y":0.3}]}');
    await pumpView(tester, t);

    await tester.tap(find.text('Website'));
    await tester.pump();
    expect(find.text('COMPONENT'), findsOneWidget);

    await tester.tap(find.text('Remove component'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('COMPONENT'), findsNothing);
  });
}
