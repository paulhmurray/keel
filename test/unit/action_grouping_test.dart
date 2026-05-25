import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/features/actions/action_grouping.dart';

ProjectAction _a({
  required String id,
  String? parentId,
  String status = 'open',
  String? dueDate,
  DateTime? updatedAt,
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
    dueDate: dueDate,
    createdAt: t,
    updatedAt: updatedAt ?? t,
  );
}

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

  group('eligibleParentCandidates', () {
    test('null editing → all top-level actions', () {
      final all = [
        _a(id: 'a'),
        _a(id: 'b'),
        _a(id: 'c', parentId: 'a'),
      ];
      final candidates =
          eligibleParentCandidates(editing: null, all: all);
      expect(candidates.map((a) => a.id).toList(), ['a', 'b']);
    });

    test('excludes self', () {
      final editing = _a(id: 'a');
      // _allActions traditionally excludes self in the caller's setup,
      // but the helper should also be safe if it's included.
      final all = [editing, _a(id: 'b'), _a(id: 'c')];
      final candidates =
          eligibleParentCandidates(editing: editing, all: all);
      expect(candidates.map((a) => a.id).contains('a'), isFalse);
      expect(candidates.length, 2);
    });

    test('returns empty when editing action has children', () {
      final editing = _a(id: 'a'); // top-level
      final all = [
        _a(id: 'b'),
        _a(id: 'c', parentId: 'a'), // child of editing
      ];
      final candidates =
          eligibleParentCandidates(editing: editing, all: all);
      expect(candidates, isEmpty);
    });

    test('excludes already-child actions (one level deep)', () {
      final all = [
        _a(id: 'a'),                  // top-level
        _a(id: 'b'),                  // top-level
        _a(id: 'c', parentId: 'a'),   // child of a
      ];
      final editing = _a(id: 'new');
      final candidates =
          eligibleParentCandidates(editing: editing, all: all);
      // 'c' must NOT appear; 'a' and 'b' must.
      expect(candidates.map((a) => a.id).toSet(), {'a', 'b'});
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
  });
}
