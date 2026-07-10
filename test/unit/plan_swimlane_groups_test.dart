import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/timeline/gantt/programme_gantt_view.dart';

/// Pure grouping logic behind the programme plan's per-project swimlanes.
void main() {
  // Minimal WP factory — only the fields the grouping reads.
  TimelineWorkPackage wp(String id,
          {String? source, int sortOrder = 0}) =>
      TimelineWorkPackage(
        id: id,
        projectId: 'prog',
        name: id,
        colourTheme: 'wp1',
        sortOrder: sortOrder,
        ragStatus: 'not_started',
        sourceProjectId: source,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  final names = {'projA': 'Alpha', 'projB': 'Beta', 'projZ': 'Zeta'};
  String nameFor(String id) => names[id] ?? 'Linked project';

  test('no cascaded WPs → a single native group, no project grouping', () {
    final groups = planSwimlaneGroups(
      [wp('w1'), wp('w2')],
      nameFor: nameFor,
    );
    expect(groups, hasLength(1));
    expect(groups.single.sourceProjectId, isNull);
    expect(groups.single.wps.map((w) => w.id), ['w1', 'w2']);
  });

  test('native group comes first, then projects alphabetically by name', () {
    final groups = planSwimlaneGroups(
      [
        wp('nativeWp'),
        wp('zWp', source: 'projZ'),
        wp('bWp', source: 'projB'),
        wp('aWp', source: 'projA'),
      ],
      nameFor: nameFor,
    );
    expect(groups.map((g) => g.sourceProjectId).toList(),
        [null, 'projA', 'projB', 'projZ']);
    expect(groups[1].wps.single.id, 'aWp');
    expect(groups[3].wps.single.id, 'zWp');
  });

  test('multiple WPs from the same project stay together in input order',
      () {
    final groups = planSwimlaneGroups(
      [
        wp('b1', source: 'projB', sortOrder: 0),
        wp('b2', source: 'projB', sortOrder: 1),
        wp('a1', source: 'projA'),
      ],
      nameFor: nameFor,
    );
    // No native WPs → no native group emitted.
    expect(groups.map((g) => g.sourceProjectId), ['projA', 'projB']);
    final beta = groups.firstWhere((g) => g.sourceProjectId == 'projB');
    expect(beta.wps.map((w) => w.id), ['b1', 'b2']);
  });

  test('cascaded-only (no native WPs) emits no empty native group', () {
    final groups = planSwimlaneGroups(
      [wp('a1', source: 'projA')],
      nameFor: nameFor,
    );
    expect(groups, hasLength(1));
    expect(groups.single.sourceProjectId, 'projA');
  });

  test('two projects with the same WP local id are not merged', () {
    // Distinct rows because their synthetic ids differ; grouping keys on
    // sourceProjectId so they land in separate swimlanes.
    final groups = planSwimlaneGroups(
      [
        wp('cascade:projA:wp1', source: 'projA'),
        wp('cascade:projB:wp1', source: 'projB'),
      ],
      nameFor: nameFor,
    );
    expect(groups, hasLength(2));
    expect(groups.map((g) => g.wps.single.id),
        ['cascade:projA:wp1', 'cascade:projB:wp1']);
  });
}
