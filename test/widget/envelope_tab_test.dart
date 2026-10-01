import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/finance/contingency_movement_dialog.dart';
import 'package:keel/features/finance/envelope_tab.dart';
import 'package:keel/providers/project_provider.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:keel/providers/sync_provider.dart';
import 'package:provider/provider.dart';

/// Smoke tests for the envelope: the tab lays out at two widths with a
/// populated ledger, and the movement dialog enforces its rules.
Future<AppDatabase> _seed() async {
  final db = AppDatabase.memory();
  await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'proj', name: 'TAC Integration'));
  await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: 'prog', name: 'Digital Toolkit', kind: const Value('programme')));
  final share = await db.programmeLinksDao
      .generateCodeForEntity(ownerEntityId: 'prog', ownerKind: 'programme');
  await db.programmeLinksDao.redeemCode(code: share, ownerEntityId: 'proj', ownerKind: 'project');
  await db.decisionsDao.upsertDecision(const DecisionsCompanion(
    id: Value('dc1'), projectId: Value('prog'), ref: Value('DC1'),
    description: Value('Release contingency'), status: Value('decided'),
  ));
  await db.financeDao.upsertFunding(
      id: 'f1', programmeId: 'prog', name: 'FY27 business case', amountMinor: 120000000,
      approvedOn: '2026-07-01', approvedBy: 'CFO');
  await db.financeDao.upsertFunding(
      id: 'f2', programmeId: 'prog', name: 'Tranche 2', amountMinor: 30000000, approvedOn: '2026-09-01');
  await db.financeDao.recordMovement(
      id: 'a1', programmeId: 'prog', kind: 'allocate', amountMinor: 90000000,
      linkedProjectId: 'proj', movedOn: '2026-07-15', reason: 'Initial envelope');
  await db.financeDao.recordMovement(
      id: 'd1', programmeId: 'prog', kind: 'draw', amountMinor: 20000000,
      linkedProjectId: 'proj', decisionId: 'dc1', movedOn: '2026-08-10', reason: 'Licence dispute');
  return db;
}

Widget _host(AppDatabase db, Widget child) => MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
        ChangeNotifierProvider<SyncProvider>(create: (_) => SyncProvider()),
        ChangeNotifierProvider<ProjectProvider>(create: (_) => ProjectProvider(db)),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

/// Bounded settle: a stream-backed widget may keep scheduling frames, so
/// never wait on pumpAndSettle's 10-minute ceiling.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmount the tree before the test ends: Drift schedules a zero-length
/// timer when the project provider's stream closes on dispose, and the
/// framework asserts on pending timers otherwise.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  for (final width in [1280.0, 900.0]) {
    testWidgets('envelope tab renders a populated ledger at $width', (tester) async {
      final db = await _seed();
      addTearDown(db.close);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(_host(db, EnvelopeTab(db: db, programmeId: 'prog')));
      await _settle(tester);
      expect(find.text('FUNDING ENVELOPE'), findsOneWidget);
      expect(find.text('FY27 business case'), findsOneWidget);
      expect(find.text('Contingency draw'), findsOneWidget);
      expect(find.textContaining('Warn below'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _teardown(tester);
    });
  }

  testWidgets('movement dialog: a draw insists on a decision', (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1100, 800);
    await tester.pumpWidget(_host(
      db,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => ContingencyMovementDialog(
                  db: db, programmeId: 'prog', initialKind: 'draw', initialProjectId: 'proj'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('Contingency draw'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount *'), '50k');
    await tester.tap(find.text('Record'));
    await _settle(tester);
    // Still open, with the validation message — no decision picked.
    expect(find.textContaining('needs the decision behind it'), findsOneWidget);
    expect(await db.financeDao.getMovements('prog'), hasLength(2));
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });
}
