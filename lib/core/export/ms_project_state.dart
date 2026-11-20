import 'dart:convert';

/// What Keel remembers between Microsoft Project exports, stored as JSON
/// on the plan header (ProgrammeHeaders.msProjectState) so it syncs with
/// the plan:
///
/// * the Project UID handed to every Keel row. A row keeps its UID for
///   life, and a UID is never handed out twice — so inserting a task
///   mid-plan leaves every other task's UID alone, and Project (or anyone
///   diffing two exports) can follow a task from one week to the next.
/// * the resource UID per owner, on the same terms.
/// * a snapshot of the last export, for "changes since last export".
class MsProjectState {
  final Map<String, int> taskUids;
  final Map<String, int> resourceUids;
  final int nextTaskUid;
  final int nextResourceUid;
  final MsExportSnapshot? last;

  const MsProjectState({
    this.taskUids = const {},
    this.resourceUids = const {},
    this.nextTaskUid = 1,
    this.nextResourceUid = 1,
    this.last,
  });

  static const empty = MsProjectState();

  /// Tolerant: a missing or damaged value starts afresh rather than
  /// blocking the export.
  factory MsProjectState.decode(String? json) {
    if (json == null || json.isEmpty) return empty;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      Map<String, int> ints(Object? o) => {
            for (final e in ((o as Map?) ?? const {}).entries)
              e.key as String: (e.value as num).toInt(),
          };
      final tasks = ints(m['tasks']);
      final res = ints(m['resources']);
      int next(Object? stored, Map<String, int> used) {
        final n = (stored as num?)?.toInt() ?? 1;
        final maxUsed = used.values.fold(0, (a, b) => a > b ? a : b);
        return n > maxUsed ? n : maxUsed + 1;
      }

      return MsProjectState(
        taskUids: tasks,
        resourceUids: res,
        nextTaskUid: next(m['nextTask'], tasks),
        nextResourceUid: next(m['nextResource'], res),
        last: m['last'] == null
            ? null
            : MsExportSnapshot.fromJson(m['last'] as Map<String, dynamic>),
      );
    } catch (_) {
      return empty;
    }
  }

  String encode() => jsonEncode({
        'v': 1,
        'tasks': taskUids,
        'resources': resourceUids,
        'nextTask': nextTaskUid,
        'nextResource': nextResourceUid,
        if (last != null) 'last': last!.toJson(),
      });

  MsProjectState copyWith({MsExportSnapshot? last}) => MsProjectState(
        taskUids: taskUids,
        resourceUids: resourceUids,
        nextTaskUid: nextTaskUid,
        nextResourceUid: nextResourceUid,
        last: last ?? this.last,
      );
}

/// Hands out UIDs against a [MsProjectState]: known keys keep theirs,
/// new keys get the next unused number.
class MsUidAllocator {
  final Map<String, int> _tasks;
  final Map<String, int> _resources;
  int _nextTask;
  int _nextResource;
  final MsExportSnapshot? _last;

  MsUidAllocator(MsProjectState s)
      : _tasks = Map.of(s.taskUids),
        _resources = Map.of(s.resourceUids),
        _nextTask = s.nextTaskUid,
        _nextResource = s.nextResourceUid,
        _last = s.last;

  int task(String key) => _tasks.putIfAbsent(key, () => _nextTask++);
  int resource(String key) =>
      _resources.putIfAbsent(key, () => _nextResource++);

  MsProjectState get state => MsProjectState(
        taskUids: _tasks,
        resourceUids: _resources,
        nextTaskUid: _nextTask,
        nextResourceUid: _nextResource,
        last: _last,
      );
}

/// One task as it went out in an export.
class MsSnapshotRow {
  final String name;
  final String start;
  final String finish;
  final String? parent; // Keel id of the parent row
  final String status;

  const MsSnapshotRow({
    required this.name,
    required this.start,
    required this.finish,
    required this.parent,
    required this.status,
  });

  factory MsSnapshotRow.fromJson(Map<String, dynamic> m) => MsSnapshotRow(
        name: m['n'] as String? ?? '',
        start: m['s'] as String? ?? '',
        finish: m['f'] as String? ?? '',
        parent: m['p'] as String?,
        status: m['st'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'n': name,
        's': start,
        'f': finish,
        if (parent != null) 'p': parent,
        if (status.isNotEmpty) 'st': status,
      };
}

class MsExportSnapshot {
  final DateTime at;
  final Map<String, MsSnapshotRow> rows; // by Keel id

  const MsExportSnapshot(this.at, this.rows);

  factory MsExportSnapshot.fromJson(Map<String, dynamic> m) => MsExportSnapshot(
        DateTime.tryParse(m['at'] as String? ?? '') ?? DateTime(2000),
        {
          for (final e in ((m['rows'] as Map?) ?? const {}).entries)
            e.key as String:
                MsSnapshotRow.fromJson(e.value as Map<String, dynamic>),
        },
      );

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'rows': {for (final e in rows.entries) e.key: e.value.toJson()},
      };
}

/// "Changes since last export", grouped the way a reviewer reads them.
class MsChangeSummary {
  final DateTime? since; // null = no earlier export to compare with
  final List<String> added;
  final List<String> removed;
  final List<String> redated;
  final List<String> reparented;
  final List<String> renamed;
  final List<String> statusChanged;

  const MsChangeSummary({
    required this.since,
    this.added = const [],
    this.removed = const [],
    this.redated = const [],
    this.reparented = const [],
    this.renamed = const [],
    this.statusChanged = const [],
  });

  bool get isFirstExport => since == null;
  bool get isEmpty =>
      added.isEmpty &&
      removed.isEmpty &&
      redated.isEmpty &&
      reparented.isEmpty &&
      renamed.isEmpty &&
      statusChanged.isEmpty;

  /// Section title → lines, empty sections left out.
  List<(String, List<String>)> get sections => [
        if (added.isNotEmpty) ('Added', added),
        if (removed.isNotEmpty) ('Removed', removed),
        if (redated.isNotEmpty) ('Re-dated', redated),
        if (reparented.isNotEmpty) ('Moved to a new parent', reparented),
        if (renamed.isNotEmpty) ('Renamed', renamed),
        if (statusChanged.isNotEmpty) ('Status changed', statusChanged),
      ];

  String toText() {
    if (isFirstExport) return 'First export with change tracking — nothing to compare with yet.';
    if (isEmpty) return 'No changes since the last export.';
    final b = StringBuffer();
    for (final (title, lines) in sections) {
      b.writeln('$title (${lines.length})');
      for (final l in lines) {
        b.writeln('  • $l');
      }
    }
    return b.toString().trimRight();
  }
}

MsChangeSummary diffSnapshots(MsExportSnapshot? last, MsExportSnapshot now) {
  if (last == null) return const MsChangeSummary(since: null);
  String day(String iso) => msDayLabel(iso);
  String nameOf(Map<String, MsSnapshotRow> rows, String? id) =>
      id == null ? 'top level' : (rows[id]?.name ?? 'a removed row');

  final added = <String>[], removed = <String>[], redated = <String>[];
  final reparented = <String>[], renamed = <String>[], status = <String>[];
  for (final e in now.rows.entries) {
    final was = last.rows[e.key];
    final r = e.value;
    if (was == null) {
      added.add('${r.name} (${day(r.start)} – ${day(r.finish)})');
      continue;
    }
    if (was.start != r.start || was.finish != r.finish) {
      redated.add('${r.name}: ${day(was.start)} – ${day(was.finish)} → '
          '${day(r.start)} – ${day(r.finish)}');
    }
    if (was.parent != r.parent) {
      reparented.add('${r.name}: ${nameOf(last.rows, was.parent)} → '
          '${nameOf(now.rows, r.parent)}');
    }
    if (was.name != r.name) renamed.add('${was.name} → ${r.name}');
    if (was.status != r.status) {
      status.add('${r.name}: ${was.status.isEmpty ? '—' : was.status} → '
          '${r.status.isEmpty ? '—' : r.status}');
    }
  }
  for (final e in last.rows.entries) {
    if (!now.rows.containsKey(e.key)) removed.add(e.value.name);
  }
  return MsChangeSummary(
    since: last.at,
    added: added,
    removed: removed,
    redated: redated,
    reparented: reparented,
    renamed: renamed,
    statusChanged: status,
  );
}

/// "2026-07-01T08:00:00" → "1 Jul 26" (time kept when it isn't a plain
/// 08:00 start or 17:00 finish).
String msDayLabel(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final base = '${d.day} ${names[d.month - 1]} ${d.year % 100}';
  if ((d.hour == 8 || d.hour == 17) && d.minute == 0) return base;
  String two(int n) => n.toString().padLeft(2, '0');
  return '$base ${two(d.hour)}:${two(d.minute)}';
}
