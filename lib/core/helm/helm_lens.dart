/// Which projects feed Helm's planning columns.
///
/// Helm is global by design — one person steers a programme and the
/// projects in it, so the day spans all of them. But a machine that also
/// carries sample programmes, or a PM who has parked a project for a
/// month, needs a way to narrow what the rail and the week ritual draw
/// from without touching the data. The lens is that: a LOCAL preference
/// (never synced) naming the projects Helm should look through. Off, or
/// empty, means every project as before.
class HelmLens {
  final Set<String> projectIds;
  final bool on;

  const HelmLens({this.projectIds = const {}, this.on = false});

  static const all = HelmLens();

  /// True when the lens actually narrows anything.
  bool get active => on && projectIds.isNotEmpty;

  bool includes(String projectId) => !active || projectIds.contains(projectId);

  /// The items whose project the lens includes; the list itself when the
  /// lens is not active.
  List<T> apply<T>(List<T> items, String Function(T) projectIdOf) =>
      active ? items.where((i) => projectIds.contains(projectIdOf(i))).toList() : items;

  /// The lens with ids that no longer name a project dropped. A lens left
  /// pointing only at deleted projects falls back to all, so Helm can never
  /// go blank because of a stale preference.
  HelmLens restrictedTo(Iterable<String> knownProjectIds) {
    final known = knownProjectIds.toSet();
    final kept = projectIds.where(known.contains).toSet();
    return HelmLens(projectIds: kept, on: on && kept.isNotEmpty);
  }

  HelmLens copyWith({Set<String>? projectIds, bool? on}) =>
      HelmLens(projectIds: projectIds ?? this.projectIds, on: on ?? this.on);

  @override
  bool operator ==(Object other) =>
      other is HelmLens &&
      other.on == on &&
      other.projectIds.length == projectIds.length &&
      other.projectIds.containsAll(projectIds);

  @override
  int get hashCode => Object.hash(on, projectIds.length);
}

/// The chip's wording: the one project by name, else a count, else all.
String helmLensLabel(HelmLens lens, Map<String, String> projectNamesById) {
  if (!lens.active) return 'All projects';
  final names = lens.projectIds
      .map((id) => projectNamesById[id])
      .whereType<String>()
      .toList()
    ..sort();
  if (names.isEmpty) return 'All projects';
  if (names.length == 1) return names.first;
  return '${names.length} projects';
}
