import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/portfolio/programme_pulse.dart';
import 'package:keel/features/portfolio/portfolio_view.dart';
import 'package:keel/features/portfolio/portfolio_widgets.dart';
import 'package:keel/providers/project_provider.dart';
import 'package:provider/provider.dart';

/// The portfolio overview renders one row per programme from its latest
/// pulse: computed beside reported RAG, the watermelon marker, and the
/// cross-portfolio totals. Seeds rows through the DAO (no stream `.first`).
Future<AppDatabase> _seed() async {
  final db = AppDatabase.memory();
  await db.projectDao.insertProject(ProjectsCompanion.insert(
      id: 'port', name: 'PMO Portfolio', kind: const Value('portfolio')));

  Map<String, dynamic> pulse(String id, String name, String computed,
      String? reported, int pastNeedBy) {
    final p = computeProgrammePulse(
      ProgrammePulseInputs(
        programme: Project(
          id: id,
          name: name,
          status: 'active',
          kind: 'programme',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
        workPackages: [
          TimelineWorkPackage(
            id: '$id-wp',
            projectId: id,
            name: 'WP',
            colourTheme: 'wp1',
            sortOrder: 0,
            ragStatus: computed,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        reports: [
          if (reported != null)
            StatusReport(
              id: '$id-rep',
              projectId: id,
              title: 'Weekly',
              overallRag: reported,
              reportDate: DateTime(2026, 10, 24),
              createdAt: DateTime(2026, 10, 24),
              updatedAt: DateTime(2026, 10, 24),
            ),
        ],
        decisions: [
          for (var i = 0; i < pastNeedBy; i++)
            Decision(
              id: '$id-d$i',
              projectId: id,
              description: 'd$i',
              status: 'pending',
              dueDate: '2026-10-01',
              source: 'manual',
              createdAt: DateTime(2026, 9, 1),
              updatedAt: DateTime(2026, 9, 1),
            ),
        ],
      ),
      now: DateTime(2026, 10, 30),
    );
    return p.toJson();
  }

  Future<void> add(String id, String name, String computed, String? reported,
      int pastNeedBy, String week) async {
    final json = pulse(id, name, computed, reported, pastNeedBy);
    final decoded = ProgrammePulse.fromJson(json);
    await db.portfolioPulsesDao.upsert(PortfolioPulsesCompanion.insert(
      id: 'pulse:$id:$week',
      portfolioId: 'port',
      sourceProgrammeId: id,
      sourceProgrammeName: Value(name),
      weekOf: week,
      capturedAt: DateTime.now(),
      computedRag: Value(decoded.health.computedRag),
      reportedRag: Value(decoded.health.reportedRag),
      completeness: Value(decoded.completeness.score),
      payload: jsonEncode(json),
    ));
  }

  // Watermelon: reported green, data red, two decisions past need-by.
  await add('prog-a', 'Digital Toolkit', 'red', 'green', 2, '2026-10-26');
  // Honest amber, no report.
  await add('prog-b', 'Asset Renewal', 'amber', null, 0, '2026-10-26');
  // An older week for prog-b must NOT produce a second row.
  await add('prog-b', 'Asset Renewal', 'green', null, 0, '2026-10-19');
  return db;
}

Widget _host(AppDatabase db) => MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<ProjectProvider>(
            create: (_) => ProjectProvider(db)),
      ],
      child: const MaterialApp(home: Scaffold(body: PortfolioView())),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  testWidgets('one heatmap row per programme from its latest pulse, with the '
      'watermelon marker, rule cells and totals', (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1500, 1400);
    await tester.pumpWidget(_host(db));
    await _settle(tester);

    // Names appear in every section; the heatmap is the first.
    expect(find.text('Digital Toolkit'), findsWidgets);
    expect(find.text('Asset Renewal'), findsWidgets);
    expect(find.textContaining('2 programmes reporting over 2 weeks'), findsOneWidget);
    // Two programmes × (overall + four dimensions) rule cells.
    expect(find.byType(RagCell), findsNWidgets(10));
    // Watermelon marker only on the programme that reported better than
    // its data.
    expect(
      find.byWidgetPredicate((w) =>
          w is Tooltip && (w.message ?? '').startsWith('Reported green while')),
      findsOneWidget,
    );
    for (final label in [
      'HEALTH BY RULES',
      'DECISION SYSTEM',
      'FLOW AND LOAD',
      'FINANCE',
      'TOP RISKS ACROSS THE PORTFOLIO',
      'DATA COMPLETENESS',
      'Watermelons',
      'Decisions past need-by',
    ]) {
      // 'FINANCE' is also a heatmap column header, so at-least-one.
      expect(find.text(label), findsAtLeastNWidgets(1), reason: label);
    }
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('renders without overflow at a 900px window', (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 1200);
    await tester.pumpWidget(_host(db));
    await _settle(tester);
    expect(find.text('HEALTH BY RULES'), findsOneWidget);
    expect(find.byType(RagCell), findsNWidgets(10));
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('clicking a same-machine programme row opens that programme',
      (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    // prog-a exists locally; prog-b is "remote" (no project row).
    await db.projectDao.insertProject(ProjectsCompanion.insert(
        id: 'prog-a', name: 'Digital Toolkit', kind: const Value('programme')));
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1500, 1400);
    late ProjectProvider pp;
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<ProjectProvider>(
            create: (_) => pp = ProjectProvider(db)),
      ],
      child: const MaterialApp(home: Scaffold(body: PortfolioView())),
    ));
    await _settle(tester);
    pp.selectProjectById('port');
    await _settle(tester);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget,
        reason: 'only the local programme is openable');

    await tester.tap(find.text('Digital Toolkit').first);
    await _settle(tester);
    expect(pp.currentProjectId, 'prog-a');
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });

  testWidgets('an empty portfolio explains how to link programmes',
      (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.projectDao.insertProject(ProjectsCompanion.insert(
        id: 'port', name: 'PMO Portfolio', kind: const Value('portfolio')));
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(_host(db));
    await _settle(tester);
    expect(find.text('No programme pulses yet.'), findsOneWidget);
    expect(find.textContaining('Portfolio Links'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _teardown(tester);
  });
}
