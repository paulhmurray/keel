import '../../../core/database/database.dart';

/// Pure helpers for reasoning about a [TimelineDependency] graph.
/// Lives outside the widget so it's trivially unit-testable without
/// pulling in Flutter.
class DependencyChains {
  DependencyChains._();

  /// Walks the dep graph backward from [activityId] and returns every
  /// upstream activity id reachable (the predecessors, and their
  /// predecessors, all the way to the source). The seed id is NOT
  /// included.
  ///
  /// Cycle-safe via a visited set — a malformed graph won't deadlock.
  static Set<String> upstreamOf(
      String activityId, List<TimelineDependency> deps) {
    final byTo = <String, List<TimelineDependency>>{};
    for (final d in deps) {
      byTo.putIfAbsent(d.toActivityId, () => []).add(d);
    }
    final out = <String>{};
    final stack = <String>[activityId];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      for (final d in byTo[id] ?? const <TimelineDependency>[]) {
        if (out.add(d.fromActivityId)) {
          stack.add(d.fromActivityId);
        }
      }
    }
    return out;
  }

  /// Mirror of [upstreamOf] — walks forward and returns every
  /// downstream activity id reachable (successors and their successors).
  static Set<String> downstreamOf(
      String activityId, List<TimelineDependency> deps) {
    final byFrom = <String, List<TimelineDependency>>{};
    for (final d in deps) {
      byFrom.putIfAbsent(d.fromActivityId, () => []).add(d);
    }
    final out = <String>{};
    final stack = <String>[activityId];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      for (final d in byFrom[id] ?? const <TimelineDependency>[]) {
        if (out.add(d.toActivityId)) {
          stack.add(d.toActivityId);
        }
      }
    }
    return out;
  }

  /// Whether [dep] is "broken" — i.e. the dependency rule is violated
  /// by the current dates of the connected activities. The rule per
  /// type:
  ///   - finish_to_start (FS): from must finish ≤ to.start
  ///   - start_to_start  (SS): from.start must be ≤ to.start
  ///   - finish_to_finish (FF): from.end must be ≤ to.end
  ///   - external: never broken (the predecessor lives outside the plan)
  ///
  /// Returns false when the relevant date pair isn't set — without a
  /// date, we can't claim the constraint is violated.
  static bool isBroken(
    TimelineDependency dep,
    Map<String, TimelineActivity> byId,
  ) {
    final from = byId[dep.fromActivityId];
    final to = byId[dep.toActivityId];
    if (from == null || to == null) return false;
    switch (dep.dependencyType) {
      case 'external':
        return false;
      case 'start_to_start':
        final a = from.startMonth, b = to.startMonth;
        if (a == null || b == null) return false;
        return b < a;
      case 'finish_to_finish':
        final a = from.endMonth ?? from.startMonth;
        final b = to.endMonth ?? to.startMonth;
        if (a == null || b == null) return false;
        return b < a;
      case 'finish_to_start':
      default:
        final a = from.endMonth ?? from.startMonth;
        final b = to.startMonth;
        if (a == null || b == null) return false;
        return b < a;
    }
  }

  /// Compact 2-3 char label for the dependency type. Renders at the
  /// midpoint of the arrow in the painter.
  static String shortLabel(String dependencyType) {
    switch (dependencyType) {
      case 'start_to_start':
        return 'SS';
      case 'finish_to_finish':
        return 'FF';
      case 'external':
        return 'EXT';
      case 'finish_to_start':
      default:
        return 'FS';
    }
  }
}
