import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/shell/left_panel.dart';
import 'package:keel/providers/project_provider.dart';
import 'package:keel/providers/update_provider.dart';
import 'package:provider/provider.dart';

/// Mounts the LeftPanel in a minimal Provider scope. Mirrors
/// canvas_view_test.dart's harness — uses a desktop-sized viewport so
/// nothing overflows, and cleans up Drift's deferred stream-close timer
/// before the framework's pending-timer check fires.
Future<void> runLeftPanelTest(
  WidgetTester tester,
  AppDatabase db,
  Future<void> Function() body, {
  void Function(Risk)? onOpenRisk,
  void Function(Decision)? onOpenDecision,
  void Function(ProjectAction)? onOpenAction,
  void Function(JournalEntry)? onOpenJournal,
  void Function(String)? onOpenPlaybookStage,
  VoidCallback? onNavigateToRaid,
  VoidCallback? onNavigateToDecisions,
  VoidCallback? onNavigateToActions,
  VoidCallback? onNavigateToJournal,
  VoidCallback? onNavigateToPlaybook,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 900);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<ProjectProvider>(
          create: (_) => ProjectProvider(db),
        ),
        // StandardUpdateNotice at the bottom of LeftPanel watches this.
        ChangeNotifierProvider<UpdateProvider>(
          create: (_) => UpdateProvider(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LeftPanel(
            onOpenRisk: onOpenRisk,
            onOpenDecision: onOpenDecision,
            onOpenAction: onOpenAction,
            onOpenJournal: onOpenJournal,
            onOpenPlaybookStage: onOpenPlaybookStage,
            onNavigateToRaid: onNavigateToRaid,
            onNavigateToDecisions: onNavigateToDecisions,
            onNavigateToActions: onNavigateToActions,
            onNavigateToJournal: onNavigateToJournal,
            onNavigateToPlaybook: onNavigateToPlaybook,
          ),
        ),
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

  testWidgets('tapping a risk row invokes onOpenRisk with that risk',
      (tester) async {
    await db.raidDao.insertRisk(RisksCompanion.insert(
      id: 'r1',
      projectId: 'p1',
      description: 'Supplier delay',
      ref: const Value('R1'),
      likelihood: const Value('high'),
      impact: const Value('high'),
    ));

    Risk? captured;
    var navCalls = 0;
    await runLeftPanelTest(
      tester,
      db,
      onOpenRisk: (r) => captured = r,
      onNavigateToRaid: () => navCalls++,
      () async {
        await tester.tap(find.textContaining('Supplier delay'));
        await tester.pump();
        expect(captured, isNotNull);
        expect(captured!.id, 'r1');
        expect(captured!.description, 'Supplier delay');
        // Item-aware opener takes precedence over the section-level
        // navigation callback when an item is tapped.
        expect(navCalls, 0);
      },
    );
  });

  testWidgets(
      'with no onOpenRisk wired, taps fall back to the section navigator',
      (tester) async {
    await db.raidDao.insertRisk(RisksCompanion.insert(
      id: 'r1',
      projectId: 'p1',
      description: 'Vendor risk',
      ref: const Value('R1'),
    ));
    var navCalls = 0;
    await runLeftPanelTest(
      tester,
      db,
      onNavigateToRaid: () => navCalls++,
      () async {
        await tester.tap(find.textContaining('Vendor risk'));
        await tester.pump();
        expect(navCalls, 1);
      },
    );
  });

  testWidgets(
      'tapping a decision row invokes onOpenDecision with that decision',
      (tester) async {
    await db.decisionsDao.insertDecision(DecisionsCompanion.insert(
      id: 'd1',
      projectId: 'p1',
      description: 'Pick CI provider',
      ref: const Value('D1'),
      status: const Value('pending'),
    ));
    Decision? captured;
    await runLeftPanelTest(
      tester,
      db,
      onOpenDecision: (d) => captured = d,
      () async {
        await tester.tap(find.textContaining('Pick CI provider'));
        await tester.pump();
        expect(captured!.id, 'd1');
      },
    );
  });

  testWidgets(
      'tapping an overdue action row invokes onOpenAction with that action',
      (tester) async {
    // Action must be open + due in the past to land in the overdue list.
    await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
      id: 'a1',
      projectId: 'p1',
      description: 'Chase Andrew on Jira',
      ref: const Value('AC1'),
      dueDate: const Value('2024-01-01'),
      status: const Value('open'),
    ));
    ProjectAction? captured;
    await runLeftPanelTest(
      tester,
      db,
      onOpenAction: (a) => captured = a,
      () async {
        await tester.tap(find.textContaining('Chase Andrew'));
        await tester.pump();
        expect(captured!.id, 'a1');
      },
    );
  });

  testWidgets(
      'tapping a journal entry invokes onOpenJournal with that entry',
      (tester) async {
    await db.journalDao.insertEntry(JournalEntriesCompanion.insert(
      id: 'j1',
      projectId: 'p1',
      body: 'Talked to Anna about the BAU handover',
      entryDate: '2026-06-13',
      title: const Value('Anna 1-1'),
    ));
    JournalEntry? captured;
    await runLeftPanelTest(
      tester,
      db,
      onOpenJournal: (e) => captured = e,
      () async {
        await tester.tap(find.textContaining('Anna 1-1'));
        await tester.pump();
        expect(captured!.id, 'j1');
      },
    );
  });
}
