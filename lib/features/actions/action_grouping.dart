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

/// Local midnight on the Monday of the week containing [t].
DateTime weekStartOf(DateTime t) {
  final day = DateTime(t.year, t.month, t.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// True if [a] is a closed action the default view should hide.
///
/// Closed actions stay on the board and list for the rest of the week
/// they were closed in, then drop off on Sunday night so Monday opens
/// clean. "Closed in" is read from [updatedAt], which closing stamps;
/// a later edit to a closed action keeps it another week.
///
/// Centralised so the actions view and any other surface use the same rule.
bool isOldClosed(ProjectAction a, {DateTime? now}) {
  if (a.status != 'closed') return false;
  final thisWeek = weekStartOf((now ?? DateTime.now()).toLocal());
  return a.updatedAt.toLocal().isBefore(thisWeek);
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

/// Ids of top-level actions whose whole group is finished and has had
/// its week on the board: the root is closed and so is every descendant,
/// all of them before the current week began (see [isOldClosed]). Retired
/// groups drop off the board and list as a whole — the "show closed"
/// toggle brings them back.
Set<String> retiredRootIds(List<ProjectAction> actions, {DateTime? now}) {
  final part = partitionByParent(actions);
  final byId = {for (final a in actions) a.id: a};
  final out = <String>{};
  for (final root in part.roots) {
    if (!isOldClosed(root, now: now)) continue;
    final descendants = actionDescendantIds(root.id, part.childrenByParent);
    // Only real groups (designated or with children) retire as a unit;
    // a plain closed action is hidden on its own by isOldClosed.
    if (descendants.isEmpty && !root.isParent) continue;
    if (descendants.every(
      (id) => byId[id] != null && isOldClosed(byId[id]!, now: now),
    )) {
      out.add(root.id);
    }
  }
  return out;
}
