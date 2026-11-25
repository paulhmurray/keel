import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/helm/helm_view.dart';
import 'package:keel/providers/project_provider.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Helm header sits in the centre pane, which gets narrow with both
/// side panels open. It must shed parts rather than overflow (a 474 px
/// header row once overflowed by 69 px).
void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.memory();
    await db.projectDao.insertProject(
      ProjectsCompanion.insert(
        id: 'p1',
        name: 'A project with a long name that fills the lens chip',
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<List<String>> overflowsAt(WidgetTester tester, double width) async {
    final errors = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    tester.view.devicePixelRatio = 1.0;
    // Header row = pane width minus its 20 px side padding.
    tester.view.physicalSize = Size(width + 40, 900);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<ProjectProvider>(
            create: (_) => ProjectProvider(db),
          ),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HelmView())),
      ),
    );
    await settle(tester);
    for (final scale in ['Day', 'Week', 'Quarter']) {
      await tester.tap(find.text(scale).first);
      await settle(tester);
      // Step away from today so the Today / This week button shows.
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await settle(tester);
    }
    FlutterError.onError = old;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    return errors.where((e) => e.contains('overflowed')).toList();
  }

  for (final width in [
    474.0,
    520.0,
    600.0,
    700.0,
    860.0,
    880.0,
    900.0,
    1100.0,
    1240.0,
    1500.0,
  ]) {
    testWidgets('no header overflow at ${width.toInt()} px', (tester) async {
      expect(await overflowsAt(tester, width), isEmpty);
    });
  }
}
