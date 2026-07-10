import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/status/status_calculator.dart';
import 'package:keel/features/programme/overview/per_project_pulse.dart';

/// Pure per-project pulse aggregation over the programme's cascaded feeds.
void main() {
  TimelineWorkPackage wp(String id, String src, String rag) =>
      TimelineWorkPackage(
        id: id,
        projectId: 'prog',
        name: id,
        colourTheme: 'wp1',
        sortOrder: 0,
        ragStatus: rag,
        sourceProjectId: src,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  Risk risk(String id, String src, {String status = 'open'}) => Risk(
        id: id,
        projectId: 'prog',
        description: 'r',
        likelihood: 'medium',
        impact: 'medium',
        status: status,
        source: 'cascade',
        sourceProjectId: src,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  ProjectAction action(String id, String src) => ProjectAction(
        id: id,
        projectId: 'prog',
        description: 'a',
        status: 'open',
        priority: 'medium',
        source: 'cascade',
        sourceProjectId: src,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  StatusReport report(String id, String src, DateTime date) => StatusReport(
        id: id,
        projectId: 'prog',
        title: 't',
        overallRag: 'green',
        reportDate: date,
        sourceProjectId: src,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  test('one row per source project, RAG from that project\'s WPs', () {
    final rows = computePerProjectPulse(
      workPackages: [
        wp('a1', 'projA', 'red'),
        wp('a2', 'projA', 'green'),
        wp('b1', 'projB', 'green'),
      ],
      risks: const [],
      issues: const [],
      overdueActions: const [],
      overdueDecisions: const [],
      reports: const [],
    );
    expect(rows.map((r) => r.sourceId).toSet(), {'projA', 'projB'});
    // projA has a red WP → worst-wins red; projB all green.
    expect(rows.firstWhere((r) => r.sourceId == 'projA').rag, Rag.red);
    expect(rows.firstWhere((r) => r.sourceId == 'projB').rag, Rag.green);
  });

  test('counts open risks (not closed) and overdue items per project', () {
    final rows = computePerProjectPulse(
      workPackages: [wp('a1', 'projA', 'green')],
      risks: [
        risk('r1', 'projA'),
        risk('r2', 'projA', status: 'closed'), // excluded
        risk('r3', 'projB'),
      ],
      issues: const [],
      overdueActions: [action('act1', 'projA')],
      overdueDecisions: const [],
      reports: const [],
    );
    final a = rows.firstWhere((r) => r.sourceId == 'projA');
    expect(a.risks, 1);
    expect(a.overdue, 1);
    final b = rows.firstWhere((r) => r.sourceId == 'projB');
    expect(b.risks, 1);
    expect(b.overdue, 0);
    expect(b.rag, Rag.notStarted); // no WPs for projB
  });

  test('lastStatus picks the most recent cascaded report for the project', () {
    final rows = computePerProjectPulse(
      workPackages: [wp('a1', 'projA', 'green')],
      risks: const [],
      issues: const [],
      overdueActions: const [],
      overdueDecisions: const [],
      reports: [
        report('rep1', 'projA', DateTime(2026, 6, 1)),
        report('rep2', 'projA', DateTime(2026, 6, 20)),
        report('rep3', 'projB', DateTime(2026, 5, 1)),
      ],
    );
    expect(rows.firstWhere((r) => r.sourceId == 'projA').lastStatus,
        DateTime(2026, 6, 20));
  });

  test('ignores native (non-cascaded) rows — no source project', () {
    final rows = computePerProjectPulse(
      workPackages: [
        TimelineWorkPackage(
          id: 'native',
          projectId: 'prog',
          name: 'native',
          colourTheme: 'wp1',
          sortOrder: 0,
          ragStatus: 'red',
          sourceProjectId: null,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      risks: const [],
      issues: const [],
      overdueActions: const [],
      overdueDecisions: const [],
      reports: const [],
    );
    expect(rows, isEmpty);
  });
}
