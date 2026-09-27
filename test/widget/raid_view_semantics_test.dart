import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/decisions/decisions_view.dart';
import 'package:keel/features/helm/helm_view.dart';
import 'package:keel/features/raid/raid_view.dart';
import 'package:keel/providers/project_provider.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps the RAID log and the Decisions list with semantics ENABLED, the
/// way the desktop app runs. Flutter's debug build asserts on dirty
/// semantics parent data (`!semantics.parentDataDirty`) for some widget
/// shapes, and a plain widget test never exercises that path.
const _pid = 'p-sem';

Future<void> _seed(AppDatabase db) async {
  await db.projectDao
      .insertProject(ProjectsCompanion.insert(id: _pid, name: 'Semantics'));
  await db.programmeGanttDao.upsertWorkPackage(const TimelineWorkPackagesCompanion(
    id: Value('wp1'),
    projectId: Value(_pid),
    name: Value('WP1'),
    sortOrder: Value(0),
  ));
  await db.programmeGanttDao.upsertActivity(const TimelineActivitiesCompanion(
    id: Value('act1'),
    workPackageId: Value('wp1'),
    projectId: Value(_pid),
    name: Value('Build'),
    startDate: Value('2026-11-02'),
    endDate: Value('2027-01-15'),
    sortOrder: Value(0),
  ));
  await db.programmeGanttDao.upsertHeader(const ProgrammeHeadersCompanion(
    id: Value('hdr'),
    projectId: Value(_pid),
    month0Date: Value('2026-09-01'),
  ));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r1'),
    projectId: Value(_pid),
    ref: Value('R1'),
    title: Value('Steerco risk with everything set'),
    description: Value('Body of the risk'),
    likelihood: Value('likely'),
    impact: Value('major'),
    steerco: Value(true),
    nextReviewAt: Value('2026-01-01'), // overdue
    sourceNote: Value('note'),
    escalatedAt: Value(null),
  ));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r2'),
    projectId: Value(_pid),
    ref: Value('R2'),
    description: Value('Plain risk'),
    likelihood: Value('rare'),
    impact: Value('minimal'),
  ));
  await db.raidDao.upsertRisk(const RisksCompanion(
    id: Value('r3'),
    projectId: Value(_pid),
    ref: Value('R3'),
    description: Value('Old closed risk'),
    status: Value('closed'),
    closedAt: Value('2026-01-01'),
  ));
  await db.raidDao.upsertAssumption(const AssumptionsCompanion(
    id: Value('a1'),
    projectId: Value(_pid),
    ref: Value('A1'),
    description: Value('An assumption'),
  ));
  await db.raidDao.upsertIssue(const IssuesCompanion(
    id: Value('i1'),
    projectId: Value(_pid),
    ref: Value('I1'),
    title: Value('An issue'),
    description: Value('Issue body'),
    escalationRequired: Value(true),
  ));
  await db.raidDao.upsertDependency(const ProgramDependenciesCompanion(
    id: Value('d1'),
    projectId: Value(_pid),
    ref: Value('D1'),
    description: Value('A dependency'),
    counterparty: Value('Acme'),
    planActivityId: Value('act1'),
    dueDate: Value('2026-10-15'),
  ));
  await db.decisionsDao.upsertDecision(const DecisionsCompanion(
    id: Value('dc1'),
    projectId: Value(_pid),
    ref: Value('DC1'),
    description: Value('A pending decision'),
    status: Value('pending'),
    planActivityId: Value('act1'),
    dueDate: Value('2026-10-20'),
    rationale: Value('Because'),
  ));
}

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget view) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 900);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<ProjectProvider>(
            create: (_) => ProjectProvider(db)),
        ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(home: Scaffold(body: view)),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void _noException(WidgetTester tester) {
  final e = tester.takeException();
  if (e != null) fail('Unexpected exception:\n$e');
}

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.memory();
    await _seed(db);
  });

  tearDown(() => db.close());

  testWidgets('RAID log renders every tab with semantics enabled',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, db, const RaidView());
    expect(find.text('Steerco risk with everything set'), findsOneWidget);
    expect(find.text('▲ ESCALATED'), findsOneWidget);
    expect(find.textContaining('Review overdue'), findsOneWidget);
    _noException(tester);

    for (final tab in ['Assumptions', 'Issues', 'Dependencies']) {
      await tester.tap(find.text(tab));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      _noException(tester);
    }
    expect(find.text('A dependency'), findsOneWidget);
    expect(find.textContaining('slack'), findsOneWidget);

    // Hover the tooltips with a mouse, as a desktop user would — the
    // tooltip overlay is a semantics change on its own.
    await tester.tap(find.text('Risks'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    for (final target in [
      find.text('▲ ESCALATED'),
      find.text('4').first, // likelihood rank dot
      find.text('Hiding closed'),
    ]) {
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 100));
      _noException(tester);
    }
    await gesture.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 300));

    // Toggle closed on and off.
    await tester.tap(find.text('Hiding closed'));
    await tester.pump(const Duration(milliseconds: 100));
    _noException(tester);
    handle.dispose();
    await _teardown(tester);
  });

  testWidgets('Helm rail shows the planning horizon across registers',
      (tester) async {
    // Date the seed relative to now so the buckets fire whatever day the
    // suite runs on.
    final now = DateTime.now();
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
      id: 'a-today', projectId: _pid, description: 'Send the brief',
      ref: const Value('AC7'), dueDate: Value(iso(now)),
    ));
    await db.actionsDao.insertAction(ProjectActionsCompanion.insert(
      id: 'a-late', projectId: _pid, description: 'Chase the contract',
      ref: const Value('AC8'), dueDate: Value(iso(now.subtract(const Duration(days: 3)))),
    ));
    await db.decisionsDao.upsertDecision(DecisionsCompanion(
      id: const Value('dc-soon'), projectId: const Value(_pid),
      ref: const Value('DC9'), description: const Value('Pick the gateway'),
      status: const Value('pending'),
      dueDate: Value(iso(now.add(const Duration(days: 9)))), // next week-ish
    ));
    await db.raidDao.upsertRisk(RisksCompanion(
      id: const Value('r-review'), projectId: const Value(_pid),
      ref: const Value('R7'), title: const Value('Vendor slips'),
      description: const Value('d'), nextReviewAt: Value(iso(now)),
    ));

    final handle = tester.ensureSemantics();
    await _pump(tester, db, const HelmView());
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('AC7 Send the brief'), findsOneWidget);
    expect(find.text('R7 Vendor slips'), findsOneWidget);
    expect(find.text('BEHIND'), findsOneWidget);
    expect(find.text('AC8 Chase the contract'), findsOneWidget);
    expect(find.textContaining('Risk review'), findsWidgets);
    _noException(tester);
    handle.dispose();
    await _teardown(tester);
  });

  testWidgets('Decisions list renders with semantics enabled', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, db, const DecisionsView());
    expect(find.text('A pending decision'), findsOneWidget);
    expect(find.textContaining('Waiting: Build'), findsOneWidget);
    _noException(tester);
    handle.dispose();
    await _teardown(tester);
  });
}
