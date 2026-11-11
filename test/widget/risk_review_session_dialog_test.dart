import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/risk_review.dart';
import 'package:keel/features/raid/risk_review_session_dialog.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:keel/providers/sync_provider.dart';
import 'package:provider/provider.dart';

final _today = DateTime(2026, 10, 26);

Future<AppDatabase> _seed() async {
  final db = AppDatabase.memory();
  await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'p', name: 'P'));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r1'), projectId: Value('p'), ref: Value('R1'), owner: Value('Paul'),
    title: Value('Vendor slips'), likelihood: Value('possible'), impact: Value('moderate'),
    description: Value('If the vendor slips, SIT starts late.'),
    mitigation: Value('Weekly vendor checkpoint'),
    lastReviewedAt: Value('2026-09-09'), nextReviewAt: Value('2026-09-23'),
    statusNote: Value('Vendor confirmed dates in August.'),
  ));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r2'), projectId: Value('p'), ref: Value('R2'),
    description: Value('Key SME on leave during UAT.'),
    nextReviewAt: Value('2026-10-12'),
  ));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r3'), projectId: Value('p'), ref: Value('R3'),
    description: Value('Reviewed last week.'),
    nextReviewAt: Value('2026-11-05'),
  ));
  return db;
}

Future<void> _open(WidgetTester tester, AppDatabase db,
    {ReviewScope scope = ReviewScope.overdue}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1300, 900);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
      ChangeNotifierProvider<SyncProvider>(create: (_) => SyncProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => RiskReviewSessionDialog(
                  db: db, projectId: 'p', initialScope: scope, today: _today,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('scope step counts overdue and open risks', (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    await _open(tester, db);
    expect(find.text('Review risks'), findsOneWidget);
    expect(find.text('Reviews overdue  ·  2'), findsOneWidget);
    expect(find.text('Every open risk  ·  3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviewed stamps the dates and saves edits; skip leaves the risk alone',
      (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    await _open(tester, db);
    await tester.tap(find.text('Start the session'));
    await tester.pumpAndSettle();

    // Oldest missed review first.
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Vendor slips'), findsOneWidget);
    expect(find.text('If the vendor slips, SIT starts late.'), findsOneWidget);
    expect(find.textContaining('Previously: Vendor confirmed dates'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Treatment'), 'Weekly checkpoint plus escalation path');
    await tester.enterText(
        find.widgetWithText(TextField, 'What changed since the last review'),
        'Vendor missed the October checkpoint.');
    await tester.tap(find.text('Reviewed'));
    await tester.pumpAndSettle();

    final r1 = (await db.raidDao.getRiskById('r1'))!;
    expect(r1.lastReviewedAt, '2026-10-26');
    expect(r1.nextReviewAt, '2026-11-09');
    expect(r1.mitigation, 'Weekly checkpoint plus escalation path');
    expect(r1.statusNote, 'Vendor missed the October checkpoint.');
    expect(r1.owner, 'Paul', reason: 'untouched fields survive the partial upsert');
    expect(r1.title, 'Vendor slips');
    expect(r1.status, 'open');

    expect(find.text('2 of 2'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    final r2 = (await db.raidDao.getRiskById('r2'))!;
    expect(r2.nextReviewAt, '2026-10-12');
    expect(r2.lastReviewedAt, isNull);

    expect(find.text('Reviewed 1 · skipped 1'), findsOneWidget);
    expect(find.textContaining('fall due again on 09-11-2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
