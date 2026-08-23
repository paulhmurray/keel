import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/actions/action_grouping.dart';

ProjectAction _a({
  required String id,
  String? parentId,
  String status = 'open',
  String? dueDate,
  DateTime? updatedAt,
  bool isParent = false,
}) {
  final t = DateTime(2026, 1, 1);
  return ProjectAction(
    id: id,
    projectId: 'p1',
    description: id,
    status: status,
    priority: 'medium',
    source: 'manual',
    parentActionId: parentId,
    isParent: isParent,
    dueDate: dueDate,
    createdAt: t,
    updatedAt: updatedAt ?? t,
  );
}

Map<String, ProjectAction> _byId(List<ProjectAction> all) =>
    {for (final a in all) a.id: a};

void main() {
  group('rollupFor', () {
    test('empty actions → zero counts', () {
      final r = rollupFor(const []);
      expect(r.total, 0);
      expect(r.open, 0);
      expect(r.done, 0);
      expect(r.isComplete, isFalse);
    });

    test('counts by status', () {
      final fixedNow = DateTime(2026, 6, 1);
      final r = rollupFor([
        _a(id: 'a', status: 'open'),
        _a(id: 'b', status: 'in progress'),
        _a(id: 'c', status: 'closed'),
        _a(id: 'd', status: 'closed'),
      ], now: fixedNow);
      expect(r.todo, 1);
      expect(r.inProgress, 1);
      expect(r.done, 2);
      expect(r.overdue, 0);
      expect(r.total, 4);
    });

    test('past dueDate marks open action as overdue', () {
      final fixedNow = DateTime(2026, 6, 1);
      final r = rollupFor([
        _a(id: 'a', status: 'open', dueDate: '2026-01-01'),
        _a(id: 'b', status: 'open', dueDate: '2026-12-01'),
      ], now: fixedNow);
      expect(r.overdue, 1);
      expect(r.todo, 1);
    });

    test('closed status wins over past due date', () {
      final fixedNow = DateTime(2026, 6, 1);
      final r = rollupFor([
        _a(id: 'a', status: 'closed', dueDate: '2026-01-01'),
      ], now: fixedNow);
      expect(r.done, 1);
      expect(r.overdue, 0);
    });

    test('isComplete only true when total > 0 and all done', () {
      expect(rollupFor([_a(id: 'a', status: 'closed')]).isComplete, isTrue);
      expect(
          rollupFor([_a(id: 'a', status: 'closed'), _a(id: 'b')]).isComplete,
          isFalse);
      expect(rollupFor(const []).isComplete, isFalse);
    });
  });

  group('actionDepth / actionSubtreeHeight', () {
    test('computes depth across two levels', () {
      final all = [
        _a(id: 'root', isParent: true),
        _a(id: 'task', parentId: 'root', isParent: true),
        _a(id: 'sub', parentId: 'task'),
      ];
      final byId = _byId(all);
      expect(actionDepth(byId['root']!, byId), 0);
      expect(actionDepth(byId['task']!, byId), 1);
      expect(actionDepth(byId['sub']!, byId), 2);
    });

    test('missing parent counts as top level', () {
      final orphan = _a(id: 'x', parentId: 'gone');
      expect(actionDepth(orphan, {'x': orphan}), 0);
    });

    test('subtree height: leaf 0, children 1, grandchildren 2', () {
      final all = [
        _a(id: 'root', isParent: true),
        _a(id: 'task', parentId: 'root', isParent: true),
        _a(id: 'sub', parentId: 'task'),
      ];
      final children = partitionByParent(all).childrenByParent;
      expect(actionSubtreeHeight('sub', children), 0);
      expect(actionSubtreeHeight('task', children), 1);
      expect(actionSubtreeHeight('root', children), 2);
    });
  });

  group('eligibleParentCandidates', () {
    test('only flagged parents are offered', () {
      final all = [
        _a(id: 'a', isParent: true),
        _a(id: 'b'), // not flagged
        _a(id: 'c', isParent: true),
      ];
      final candidates =
          eligibleParentCandidates(editing: null, all: all);
      expect(candidates.map((a) => a.id).toSet(), {'a', 'c'});
    });

    test('a flagged task (depth 1) is offered — enables sub-tasks', () {
      final all = [
        _a(id: 'root', isParent: true),
        _a(id: 'task', parentId: 'root', isParent: true),
      ];
      final candidates =
          eligibleParentCandidates(editing: null, all: all);
      expect(candidates.map((a) => a.id).toSet(), {'root', 'task'});
    });

    test('a flagged sub-task (depth 2) is NOT offered', () {
      final all = [
        _a(id: 'root', isParent: true),
        _a(id: 'task', parentId: 'root', isParent: true),
        _a(id: 'sub', parentId: 'task', isParent: true), // corrupt flag
      ];
      final candidates =
          eligibleParentCandidates(editing: null, all: all);
      expect(candidates.map((a) => a.id).contains('sub'), isFalse);
    });

    test('excludes self and own descendants (no cycles)', () {
      final editing = _a(id: 'task', parentId: 'root', isParent: true);
      final all = [
        _a(id: 'root', isParent: true),
        _a(id: 'sub', parentId: 'task', isParent: true),
      ];
      final candidates =
          eligibleParentCandidates(editing: editing, all: all);
      expect(candidates.map((a) => a.id).toList(), ['root']);
    });

    test('an action with children can only nest under a top-level parent',
        () {
      final editing = _a(id: 'task', isParent: true);
      final all = [
        _a(id: 'root', isParent: true),
        _a(id: 'nested', parentId: 'root', isParent: true),
        _a(id: 'kid', parentId: 'task'),
      ];
      final candidates =
          eligibleParentCandidates(editing: editing, all: all);
      // Nesting under 'nested' would put 'kid' at depth 3.
      expect(candidates.map((a) => a.id).toList(), ['root']);
    });

    test('an action with grandchildren cannot nest anywhere', () {
      final editing = _a(id: 'root', isParent: true);
      final all = [
        _a(id: 'other', isParent: true),
        _a(id: 'task', parentId: 'root', isParent: true),
        _a(id: 'sub', parentId: 'task'),
      ];
      final candidates =
          eligibleParentCandidates(editing: editing, all: all);
      expect(candidates, isEmpty);
    });

    test('most recently touched candidates come first', () {
      final all = [
        _a(id: 'old', isParent: true, updatedAt: DateTime(2026, 1, 1)),
        _a(id: 'fresh', isParent: true, updatedAt: DateTime(2026, 7, 1)),
      ];
      final candidates =
          eligibleParentCandidates(editing: null, all: all);
      expect(candidates.map((a) => a.id).toList(), ['fresh', 'old']);
    });
  });

  group('canBeParent', () {
    test('top-level and depth-1 actions can be parents, sub-tasks cannot',
        () {
      final all = [
        _a(id: 'root', isParent: true),
        _a(id: 'task', parentId: 'root'),
        _a(id: 'sub', parentId: 'task'),
      ];
      final byId = _byId(all);
      expect(canBeParent(byId['root']!, byId), isTrue);
      expect(canBeParent(byId['task']!, byId), isTrue);
      expect(canBeParent(byId['sub']!, byId), isFalse);
    });
  });

  group('isOldClosed', () {
    final now = DateTime(2026, 5, 13);

    test('open actions are never old-closed regardless of age', () {
      expect(
          isOldClosed(
            _a(id: 'a', status: 'open', updatedAt: DateTime(2020)),
            now: now,
          ),
          isFalse);
    });

    test('closed action edited yesterday is NOT old-closed', () {
      expect(
          isOldClosed(
            _a(
              id: 'a',
              status: 'closed',
              updatedAt: now.subtract(const Duration(days: 1)),
            ),
            now: now,
          ),
          isFalse);
    });

    test('closed action edited exactly 14 days ago is NOT old-closed', () {
      expect(
          isOldClosed(
            _a(
              id: 'a',
              status: 'closed',
              updatedAt: now.subtract(const Duration(days: 14)),
            ),
            now: now,
          ),
          isFalse);
    });

    test('closed action edited 15 days ago IS old-closed', () {
      expect(
          isOldClosed(
            _a(
              id: 'a',
              status: 'closed',
              updatedAt: now.subtract(const Duration(days: 15)),
            ),
            now: now,
          ),
          isTrue);
    });

    test('honours custom hideAfterDays threshold', () {
      expect(
          isOldClosed(
            _a(
              id: 'a',
              status: 'closed',
              updatedAt: now.subtract(const Duration(days: 5)),
            ),
            now: now,
            hideAfterDays: 3,
          ),
          isTrue);
      expect(
          isOldClosed(
            _a(
              id: 'a',
              status: 'closed',
              updatedAt: now.subtract(const Duration(days: 1)),
            ),
            now: now,
            hideAfterDays: 3,
          ),
          isFalse);
    });
  });

  group('partitionByParent', () {
    test('groups children under their parents', () {
      final list = [
        _a(id: 'root1'),
        _a(id: 'root2'),
        _a(id: 'child1a', parentId: 'root1'),
        _a(id: 'child1b', parentId: 'root1'),
        _a(id: 'child2', parentId: 'root2'),
      ];
      final p = partitionByParent(list);
      expect(p.roots.map((a) => a.id).toList(), ['root1', 'root2']);
      expect(p.childrenByParent['root1']!.map((a) => a.id).toList(),
          ['child1a', 'child1b']);
      expect(
          p.childrenByParent['root2']!.map((a) => a.id).toList(), ['child2']);
    });

    test('actions with no parent and no children all become roots', () {
      final list = [_a(id: 'a'), _a(id: 'b'), _a(id: 'c')];
      final p = partitionByParent(list);
      expect(p.roots.length, 3);
      expect(p.childrenByParent, isEmpty);
    });

    test('a child whose parent is absent from the list becomes a root', () {
      final list = [_a(id: 'orphan', parentId: 'missing')];
      final p = partitionByParent(list);
      expect(p.roots.map((a) => a.id).toList(), ['orphan']);
      expect(p.childrenByParent, isEmpty);
    });
  });

  group('retiredRootIds', () {
    test('closed root with all descendants closed is retired', () {
      final all = [
        _a(id: 'root', status: 'closed', isParent: true),
        _a(id: 'task', parentId: 'root', status: 'closed'),
      ];
      expect(retiredRootIds(all), {'root'});
    });

    test('closed root with an open descendant is NOT retired', () {
      final all = [
        _a(id: 'root', status: 'closed', isParent: true),
        _a(id: 'task', parentId: 'root', status: 'closed'),
        _a(id: 'sub', parentId: 'task', status: 'open'),
      ];
      expect(retiredRootIds(all), isEmpty);
    });

    test('open root is never retired even if all children are closed', () {
      final all = [
        _a(id: 'root', status: 'open', isParent: true),
        _a(id: 'task', parentId: 'root', status: 'closed'),
      ];
      expect(retiredRootIds(all), isEmpty);
    });

    test('a plain closed action is NOT retired — it ages out instead', () {
      final all = [_a(id: 'solo', status: 'closed')];
      expect(retiredRootIds(all), isEmpty);
    });

    test('a closed designated parent with no children retires', () {
      final all = [_a(id: 'empty-group', status: 'closed', isParent: true)];
      expect(retiredRootIds(all), {'empty-group'});
    });
  });
}
