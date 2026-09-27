import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/raid/raid_tidy_dialog.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:keel/providers/sync_provider.dart';
import 'package:provider/provider.dart';

/// The scope step of the tidy queue: counts what is flagged, never calls
/// the LLM, and keeps the Draft button off when there is nothing to do.
void main() {
  testWidgets('scope step counts flagged vs open items', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.projectDao.insertProject(ProjectsCompanion.insert(id: 'p', name: 'P'));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('weak'),
      projectId: Value('p'),
      description: Value('Vendor build phase is running late and stretched.'),
      owner: Value('Paul'),
    ));
    await db.raidDao.upsertRisk(const RisksCompanion(
      id: Value('good'),
      projectId: Value('p'),
      description: Value('If the vendor slips again, then SIT may start late, '
          'resulting in a four-week delay to go-live.'),
      owner: Value('Paul'),
    ));

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 800);
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
                  builder: (_) => RaidTidyDialog(db: db, projectId: 'p'),
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

    expect(find.text('Tidy my register'), findsOneWidget);
    expect(find.textContaining('Items flagged IMPROVE  ·  1'), findsOneWidget);
    expect(find.textContaining('Every open item  ·  2'), findsOneWidget);
    // Draft button is live because one item needs work.
    final draft = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Draft them'));
    expect(draft.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
