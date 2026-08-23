import '../../core/database/database.dart';

/// Status rollup for a group of actions (typically the children of a parent).
class GroupRollup {
  final int todo;
  final int inProgress;
  final int overdue;
  final int done;

  const GroupRollup({
    this.todo = 0,
    this.inProgress = 0,
    this.overdue = 0,
    this.done = 0,
  });

  int get total => todo + inProgress + overdue + done;
  int get open => todo + inProgress + overdue;
  bool get isComplete => total > 0 && done == total;
}

GroupRollup rollupFor(Iterable<ProjectAction> actions, {DateTime? now}) {
  final today = (now ?? DateTime.now()).toIso8601String().substring(0, 10);
  int todo = 0, inProgress = 0, overdue = 0, done = 0;
  for (final a in actions) {
    if (a.status == 'closed') {
      done++;
      continue;
    }
    final isOverdue = (a.dueDate != null && a.dueDate!.compareTo(today) < 0) ||
        a.status == 'overdue';
    if (isOverdue) {
      overdue++;
      continue;
    }
    if (a.status == 'in progress') {
      inProgress++;
      continue;
    }
    todo++;
  }
  return GroupRollup(
    todo: todo,
    inProgress: inProgress,
    overdue: overdue,
    done: done,
  );
}

/// Maximum nesting: parent (0) → task (1) → sub-task (2).
const int kMaxActionDepth = 2;

/// Depth of [a] in the hierarchy: 0 for top-level, 1 for a task under a
/// parent, 2 for a sub-task. Missing parents and cycles are treated as
/// top-level so corrupt data degrades gracefully instead of recursing.
int actionDepth(ProjectAction a, Map<String, ProjectAction> byId) {
  var depth = 0;
  final seen = <String>{a.id};
  var cursor = a;
  while (cursor.parentActionId != null && depth < kMaxActionDepth) {
    final parent = byId[cursor.parentActionId!];
    if (parent == null || !seen.add(parent.id)) break;
    depth++;
    cursor = parent;
  }
  return depth;
}

/// Height of the subtree rooted at [id]: 0 for a leaf, 1 if it has
/// children, 2 if it has grandchildren.
int actionSubtreeHeight(
    String id, Map<String, List<ProjectAction>> childrenByParent) {
  final children = childrenByParent[id];
  if (children == null || children.isEmpty) return 0;
  var max = 0;
  for (final c in children) {
    final h = actionSubtreeHeight(c.id, childrenByParent);
    if (h > max) max = h;
  }
  return 1 + max;
}

/// All descendant ids of [id] (children and grandchildren).
Set<String> actionDescendantIds(
    String id, Map<String, List<ProjectAction>> childrenByParent) {
  final out = <String>{};
  void walk(String cursor) {
    for (final c in childrenByParent[cursor] ?? const <ProjectAction>[]) {
      if (out.add(c.id)) walk(c.id);
    }
  }
  walk(id);
  return out;
}

/// True when [candidate] can become the parent of [editing] (or of a new
/// action when [editing] is null) without breaking the hierarchy rules:
///   - candidate is explicitly flagged as a parent
///   - not yourself, not one of your own descendants (no cycles)
///   - resulting depth stays within [kMaxActionDepth]: the candidate's
///     depth plus one plus the height of the moving subtree must fit.
bool canNestUnder({
  required ProjectAction? editing,
  required ProjectAction candidate,
  required Map<String, ProjectAction> byId,
  required Map<String, List<ProjectAction>> childrenByParent,
}) {
  if (!candidate.isParent) return false;
  final movingHeight = editing == null
      ? 0
      : actionSubtreeHeight(editing.id, childrenByParent);
  if (editing != null) {
    if (candidate.id == editing.id) return false;
    if (actionDescendantIds(editing.id, childrenByParent)
        .contains(candidate.id)) {
      return false;
    }
  }
  return actionDepth(candidate, byId) + 1 + movingHeight <= kMaxActionDepth;
}

/// Actions the editing action may pick as its parent: explicitly flagged
/// parents that pass [canNestUnder], most recently touched first.
List<ProjectAction> eligibleParentCandidates({
  required ProjectAction? editing,
  required List<ProjectAction> all,
}) {
  // Callers conventionally exclude the editing action from [all]; put it
  // back so its children resolve to it instead of becoming orphan roots.
  final working = editing == null || all.any((a) => a.id == editing.id)
      ? all
      : [...all, editing];
  final byId = {for (final a in working) a.id: a};
  final childrenByParent = partitionByParent(working).childrenByParent;
  return all
      .where((c) => canNestUnder(
            editing: editing,
            candidate: c,
            byId: byId,
            childrenByParent: childrenByParent,
          ))
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

/// True when [a] may be flagged as a group parent: sub-tasks (depth 2)
/// can't grow children of their own.
bool canBeParent(ProjectAction a, Map<String, ProjectAction> byId) =>
    actionDepth(a, byId) < kMaxActionDepth;

/// True if [a] is a closed action whose last-update is older than
/// [hideAfterDays] (relative to [now]).
///
/// Centralised so the actions view and any other surface use the same rule.
bool isOldClosed(
  ProjectAction a, {
  DateTime? now,
  int hideAfterDays = 14,
}) {
  if (a.status != 'closed') return false;
  final cutoff =
      (now ?? DateTime.now()).subtract(Duration(days: hideAfterDays));
  return a.updatedAt.isBefore(cutoff);
}

/// Splits a flat action list into top-level actions plus a children map keyed
/// by parent id. Children for a parent are sorted by their original order.
/// An action whose parent is not in [actions] (filtered out or deleted)
/// counts as a root so it never silently disappears from a view.
({List<ProjectAction> roots, Map<String, List<ProjectAction>> childrenByParent})
    partitionByParent(List<ProjectAction> actions) {
  final ids = {for (final a in actions) a.id};
  final roots = <ProjectAction>[];
  final children = <String, List<ProjectAction>>{};
  for (final a in actions) {
    if (a.parentActionId == null || !ids.contains(a.parentActionId)) {
      roots.add(a);
    } else {
      children.putIfAbsent(a.parentActionId!, () => []).add(a);
    }
  }
  return (roots: roots, childrenByParent: children);
}

/// Ids of top-level actions whose whole group is finished: the root is
/// closed and so is every descendant. Retired groups drop off the board
/// and list immediately (no 14-day wait) — the "show old closed" toggle
/// brings them back.
Set<String> retiredRootIds(List<ProjectAction> actions) {
  final part = partitionByParent(actions);
  final byId = {for (final a in actions) a.id: a};
  final out = <String>{};
  for (final root in part.roots) {
    if (root.status != 'closed') continue;
    final descendants = actionDescendantIds(root.id, part.childrenByParent);
    // Plain closed actions age out over 14 days like always; only real
    // groups (designated or with children) retire the moment they close.
    if (descendants.isEmpty && !root.isParent) continue;
    if (descendants.every((id) => byId[id]?.status == 'closed')) {
      out.add(root.id);
    }
  }
  return out;
}
