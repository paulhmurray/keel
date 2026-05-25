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

/// Returns top-level actions (parentActionId == null) that the editing
/// action may pick as its parent.
///
/// Rules:
///   - one level deep — an action that already has children cannot itself
///     be made a child of someone else (it's a parent already)
///   - cannot pick yourself
///   - candidate must itself be top-level (no parent)
///
/// If [editing] is non-null and already has children in [all], returns an
/// empty list — meaning the parent picker should be disabled with an
/// explanatory hint.
List<ProjectAction> eligibleParentCandidates({
  required ProjectAction? editing,
  required List<ProjectAction> all,
}) {
  if (editing != null) {
    final hasChildren =
        all.any((a) => a.parentActionId != null && a.parentActionId == editing.id);
    if (hasChildren) return const [];
  }
  return all
      .where((a) =>
          a.parentActionId == null && (editing == null || a.id != editing.id))
      .toList();
}

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
({List<ProjectAction> roots, Map<String, List<ProjectAction>> childrenByParent})
    partitionByParent(List<ProjectAction> actions) {
  final roots = <ProjectAction>[];
  final children = <String, List<ProjectAction>>{};
  for (final a in actions) {
    if (a.parentActionId == null) {
      roots.add(a);
    } else {
      children.putIfAbsent(a.parentActionId!, () => []).add(a);
    }
  }
  return (roots: roots, childrenByParent: children);
}
