import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/search/project_search.dart';
import 'package:keel/features/shell/search_palette.dart';

/// The find palette: type, see grouped hits, Enter opens the best one.
/// The palette returns the chosen hit; dispatch is the shell's job.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'proj', name: 'TAC'));
    await db.peopleDao.insertPerson(const PersonsCompanion(
      id: Value('sam'), projectId: Value('proj'), name: Value('Sam Patel'),
      role: Value('Project Manager'),
    ));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('r1'), projectId: Value('proj'), ref: Value('R1'),
      title: Value('Vendor slips'), description: Value('Vendor may slip'),
      owner: Value('Sam Patel'),
    ));
    for (var i = 0; i < 10; i++) {
      await db.actionsDao.upsertAction(ProjectActionsCompanion(
        id: Value('a$i'), projectId: const Value('proj'),
        ref: Value('AC$i'), description: Value('Routine action $i'),
        owner: const Value('Sam Patel'),
      ));
    }
  });
  tearDown(() => db.close());

  /// Hosts a button that opens the palette and records what it returned.
  Future<SearchHit? Function()> pumpHost(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SearchHit? result;
    var popped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showSearchPalette(context,
                    db: db, projectId: 'proj', isProgramme: false);
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => popped ? result : throw StateError('palette still open');
  }

  testWidgets('empty query shows sections only; typing a name finds the person',
      (tester) async {
    await pumpHost(tester);
    expect(find.text('GO TO  ·  16'), findsOneWidget);
    expect(find.text('Sam Patel'), findsNothing);

    await tester.enterText(find.byType(TextField), 'sam');
    await tester.pumpAndSettle();
    expect(find.text('Sam Patel'), findsOneWidget);
    expect(find.text('PEOPLE  ·  1'), findsOneWidget);
    // Sam owns the risk and every action, so those groups show too.
    expect(find.text('RISKS  ·  1'), findsOneWidget);
    expect(find.text('ACTIONS  ·  10'), findsOneWidget);
    // The "+N more" row sits below the fold; scroll the list to it.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.textContaining('+4 more'), findsOneWidget,
        reason: 'default cap is 6 per group');
  });

  testWidgets('Enter returns the best hit: the person for a name, the risk for a ref',
      (tester) async {
    final result = await pumpHost(tester);
    await tester.enterText(find.byType(TextField), 'sam patel');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final hit = result();
    expect(hit, isNotNull);
    expect(hit!.kind, SearchKind.person);
    expect((hit.payload as Person).id, 'sam');
  });

  testWidgets('a typed ref selects that item even though people rank above risks',
      (tester) async {
    final result = await pumpHost(tester);
    await tester.enterText(find.byType(TextField), 'r1');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final hit = result();
    expect(hit!.kind, SearchKind.risk);
    expect(hit.id, 'r1');
  });

  testWidgets('the best hit stays visible and selected when its group is capped',
      (tester) async {
    final result = await pumpHost(tester);
    // AC9 is the tenth action; the group shows six. It must still be
    // the row Enter opens.
    await tester.enterText(find.byType(TextField), 'AC9');
    await tester.pumpAndSettle();
    expect(find.text('Routine action 9'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result()!.id, 'a9');
  });

  testWidgets('arrow down moves the selection; Escape dismisses with null',
      (tester) async {
    final result = await pumpHost(tester);
    await tester.enterText(find.byType(TextField), 'routine');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result()!.id, 'a1', reason: 'second-ranked action after one step');

    // Reopen and dismiss.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result(), isNull);
  });

  testWidgets('no match says so', (tester) async {
    await pumpHost(tester);
    await tester.enterText(find.byType(TextField), 'zzqx');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing in this project matches'),
        findsOneWidget);
  });
}
