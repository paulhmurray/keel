import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/timeline/gantt/raid_picker_dialog.dart';

/// The "Link a RAID item" picker: search narrows a long list, typos are
/// forgiven, the keyboard picks, and already-linked items stay hidden.
void main() {
  Future<({AppDatabase db, List<Object?> picked})> open(
    WidgetTester tester, {
    Set<String> exclude = const {},
  }) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.projectDao
        .insertProject(ProjectsCompanion.insert(id: 'p', name: 'P'));
    for (var i = 1; i <= 30; i++) {
      await db.raidDao.upsertRisk(RisksCompanion(
        id: Value('filler$i'),
        projectId: const Value('p'),
        ref: Value('R${i + 100}'),
        description: Value('Generic delivery risk number $i'),
      ));
    }
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('supplier'),
      projectId: Value('p'),
      ref: Value('R19'),
      title: Value('Supplier capacity for SIT'),
      description: Value('The SIT supplier may not have testers in May.'),
      owner: Value('Priya'),
    ));
    await db.raidDao.upsertAssumption(const AssumptionsCompanion(
      id: Value('tenancy'),
      projectId: Value('p'),
      ref: Value('A3'),
      description: Value('Azure tenancy is available by July'),
    ));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('closed'),
      projectId: Value('p'),
      ref: Value('R2'),
      description: Value('Supplier insolvency'),
      status: Value('closed'),
    ));

    final picked = <Object?>[];
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => picked.add(await showDialog(
                context: context,
                builder: (_) => RaidPickerDialog(
                  db: db,
                  projectId: 'p',
                  excludeIds: exclude,
                  itemName: 'SIT exit gate',
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (db: db, picked: picked);
  }

  testWidgets('typing a misspelt word narrows to the right item and Enter '
      'links it', (tester) async {
    final r = await open(tester);
    expect(find.textContaining('“SIT exit gate”'), findsOneWidget);
    expect(find.text('All 32'), findsOneWidget); // closed one left out

    await tester.enterText(
        find.byKey(const ValueKey('raid-picker-search')), 'suplier');
    await tester.pumpAndSettle();
    expect(find.text('All 1'), findsOneWidget);
    expect(find.textContaining('capacity for SIT', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('insolvency', findRichText: true),
        findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(r.picked.single, (type: 'risk', id: 'supplier'));
  });

  testWidgets('arrow keys move the selection; type chips filter',
      (tester) async {
    final r = await open(tester);
    await tester.tap(find.text('Assumptions 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Azure tenancy', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Generic delivery', findRichText: true),
        findsNothing);

    await tester.tap(find.text('All 32'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('raid-picker-search')), 'tenancy supplier');
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing matches'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('raid-picker-search')), 'a');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // wraps to last
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(r.picked.single, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('already-linked items are hidden', (tester) async {
    await open(tester, exclude: {'supplier'});
    await tester.enterText(
        find.byKey(const ValueKey('raid-picker-search')), 'R19');
    await tester.pumpAndSettle();
    expect(find.textContaining('capacity for SIT', findRichText: true),
        findsNothing);
  });
}
