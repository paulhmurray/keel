// Runs the register screens on the REAL desktop embedder with semantics
// forced on, to catch framework assertions (`!semantics.parentDataDirty`)
// that headless widget tests never hit.
//
//   flutter test integration_test/screens_semantics_test.dart -d linux
//
// Uses an in-memory database seeded here — never the user's keel.db.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/actions/actions_view.dart';
import 'package:keel/features/decisions/decisions_view.dart';
import 'package:keel/features/raid/raid_view.dart';
import 'package:keel/features/raid/risk_form.dart';
import 'package:keel/features/reports/reports_view.dart';
import 'package:keel/providers/analytics_provider.dart';
import 'package:keel/providers/project_provider.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:keel/providers/update_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pid = 'p-int';

Future<void> _seed(AppDatabase db) async {
  await db.projectDao
      .insertProject(ProjectsCompanion.insert(id: _pid, name: 'Integration'));
  await db.programmeGanttDao.upsertWorkPackage(const TimelineWorkPackagesCompanion(
    id: Value('wp1'), projectId: Value(_pid), name: Value('WP1'), sortOrder: Value(0),
  ));
  await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
    id: Value('act1'), workPackageId: Value('wp1'), projectId: Value(_pid),
    name: Value('Build'), startDate: Value('2026-11-02'),
    endDate: Value('2027-01-15'), sortOrder: Value(0),
  ));
  await db.programmeGanttDao.upsertHeader(const ProgrammeHeadersCompanion(
    id: Value('hdr'), projectId: Value(_pid), month0Date: Value('2026-09-01'),
  ));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r1'), projectId: Value(_pid), ref: Value('R1'),
    title: Value('Steerco risk'), description: Value('Body of the risk'),
    likelihood: Value('likely'), impact: Value('major'), steerco: Value(true),
    nextReviewAt: Value('2026-01-01'), mitigation: Value('- Do a thing'),
    likelihoodRationale: Value('Because'), statusNote: Value('Open.'),
  ));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r2'), projectId: Value(_pid), ref: Value('R2'),
    description: Value('Plain risk'), likelihood: Value('rare'), impact: Value('minimal'),
  ));
  await db.raidDao.upsertIssue(const IssuesCompanion(
    id: Value('i1'), projectId: Value(_pid), ref: Value('I1'),
    title: Value('An issue'), description: Value('Issue body'),
    escalationRequired: Value(true),
  ));
  await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
    id: Value('d1'), projectId: Value(_pid), ref: Value('D1'),
    description: Value('A dependency'), counterparty: Value('Acme'),
    planActivityId: Value('act1'), dueDate: Value('2026-10-15'),
  ));
  await db.decisionsDao.upsertDecision(const DecisionsCompanion(
    id: Value('dc1'), projectId: Value(_pid), ref: Value('DC1'),
    description: Value('A pending decision'), status: Value('pending'),
    planActivityId: Value('act1'), dueDate: Value('2026-10-20'),
  ));
  await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
    id: 'parent', projectId: _pid, description: 'Parent action',
    ref: const Value('AC1'), isParent: const Value(true),
  ));
  await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
    id: 'child', projectId: _pid, description: 'Child action',
    ref: const Value('AC2'), parentActionId: const Value('parent'),
  ));
}

Widget _host(AppDatabase db, Widget view) => MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<ProjectProvider>(create: (_) => ProjectProvider(db)),
        ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
        ChangeNotifierProvider<AnalyticsProvider>(
            create: (ctx) => AnalyticsProvider(ctx.read<SettingsProvider>())),
        ChangeNotifierProvider<UpdateProvider>(create: (_) => UpdateProvider()),
      ],
      child: MaterialApp(home: Scaffold(body: view)),
    );

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void _noException(WidgetTester tester) {
  final e = tester.takeException();
  if (e != null) fail('Unexpected exception:\n$e');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.memory();
    await _seed(db);
  });
  tearDown(() => db.close());

  testWidgets('RAID log, risk dialog, decisions and actions on the real embedder',
      (tester) async {
    final handle = SemanticsBinding.instance.ensureSemantics();

    await tester.pumpWidget(_host(db, const RaidView()));
    await _settle(tester);
    expect(find.text('Steerco risk'), findsOneWidget);
    _noException(tester);

    // Hover the badge and a rating dot like a mouse user.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('▲ STEERCO')));
    await _settle(tester, 20);
    _noException(tester);
    await gesture.moveTo(tester.getCenter(find.text('4').first));
    await _settle(tester, 20);
    _noException(tester);

    // Open the risk dialog (view mode), then switch to edit.
    await tester.tap(find.text('Steerco risk'));
    await _settle(tester, 15);
    expect(find.byType(RiskFormDialog), findsOneWidget);
    _noException(tester);
    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await _settle(tester, 15);
    _noException(tester);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await _settle(tester);
    _noException(tester);

    for (final tab in ['Assumptions', 'Issues', 'Dependencies']) {
      await tester.tap(find.text(tab));
      await _settle(tester);
      _noException(tester);
    }

    // Dependency dialog from the register row.
    await tester.tap(find.text('A dependency'));
    await _settle(tester, 15);
    _noException(tester);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await _settle(tester);

    await tester.pumpWidget(_host(db, const DecisionsView()));
    await _settle(tester);
    expect(find.text('A pending decision'), findsOneWidget);
    _noException(tester);
    await tester.tap(find.text('A pending decision'));
    await _settle(tester, 15);
    _noException(tester);
    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await _settle(tester, 15);
    _noException(tester);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await _settle(tester);

    await tester.pumpWidget(_host(db, const ActionsView()));
    await _settle(tester);
    expect(find.text('Parent action'), findsOneWidget);
    _noException(tester);
    await tester.tap(find.text('Parent action').first);
    await _settle(tester, 15);
    _noException(tester);
    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await _settle(tester, 15);
    _noException(tester);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Close'));
    await tester.tap(find.text('Close'));
    await _settle(tester);

    // Reports: the two export tabs with the include-closed checkbox.
    await tester.pumpWidget(_host(db, const ReportsView()));
    await _settle(tester);
    _noException(tester);
    for (final tab in ['RAID Export', 'Programme Workbook', 'Handover Pack']) {
      await tester.tap(find.text(tab));
      await _settle(tester);
      _noException(tester);
    }
    await tester.tap(find.text('RAID Export'));
    await _settle(tester);
    await tester.tap(find.textContaining('Include closed items'));
    await _settle(tester);
    _noException(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester, 3);
    handle.dispose();
  });
}
