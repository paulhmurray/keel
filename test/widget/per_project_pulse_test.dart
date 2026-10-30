import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/programme/overview/per_project_pulse.dart';
import 'package:keel/providers/project_provider.dart';
import 'package:provider/provider.dart';

/// The programme overview's per-project rows: a same-machine project opens
/// from its row (the portfolio → programme → project drill-down); a project
/// that only exists on another machine stays a plain row.
Future<AppDatabase> _seed() async {
  final db = AppDatabase.memory();
  await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: 'prog', name: 'Big Programme', kind: const Value('programme')));
  await db.projectDao.insertProject(
      ProjectsCompanion.insert(id: 'proj-local', name: 'Local Project'));
  final code = await db.programmeLinksDao
      .generateCodeForEntity(ownerEntityId: 'prog', ownerKind: 'programme');
  await db.programmeLinksDao.redeemCode(
      code: code, ownerEntityId: 'proj-local', ownerKind: 'project');
  return db;
}

TimelineWorkPackage _wp(String id, String src) => TimelineWorkPackage(
      id: id,
      projectId: 'prog',
      name: id,
      colourTheme: 'wp1',
      sortOrder: 0,
      ragStatus: 'amber',
      sourceProjectId: src,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a local project row opens the project; a remote one does not',
      (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    late ProjectProvider pp;
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<ProjectProvider>(
            create: (_) => pp = ProjectProvider(db)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PerProjectPulse(
              programmeId: 'prog',
              db: db,
              workPackages: [
                _wp('wp-a', 'proj-local'),
                _wp('wp-b', 'proj-remote'),
              ],
            ),
          ),
        ),
      ),
    ));
    await _settle(tester);
    pp.selectProjectById('prog');
    await _settle(tester);

    expect(find.text('Local Project'), findsOneWidget);
    expect(find.text('Linked project'), findsOneWidget); // remote fallback
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);

    await tester.tap(find.text('Linked project'));
    await _settle(tester);
    expect(pp.currentProjectId, 'prog', reason: 'remote row is inert');

    await tester.tap(find.text('Local Project'));
    await _settle(tester);
    expect(pp.currentProjectId, 'proj-local');
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });
}
