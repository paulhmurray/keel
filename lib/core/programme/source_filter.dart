/// Programme-side filtering of registers that mix the programme's own
/// rows with cascaded copies from linked projects. Pure so the RAID,
/// Actions and Decisions views share one tested rule.
library;

/// What the programme manager wants to see.
///
///   - [sourceId] null  → every row (programme + all linked projects)
///   - [sourceId] == [kProgrammeOnly] → the programme's native rows only
///   - [sourceId] == a project id → that project's cascaded rows only
///   - [escalatedOnly] → additionally drop cascaded rows the project PM
///     never escalated (full-share links carry the whole register)
class SourceFilter {
  static const kProgrammeOnly = '__programme__';

  final String? sourceId;
  final bool escalatedOnly;

  const SourceFilter({this.sourceId, this.escalatedOnly = false});

  static const all = SourceFilter();

  bool get isAll => sourceId == null && !escalatedOnly;

  SourceFilter copyWith({String? sourceId, bool clearSource = false,
      bool? escalatedOnly}) =>
      SourceFilter(
        sourceId: clearSource ? null : (sourceId ?? this.sourceId),
        escalatedOnly: escalatedOnly ?? this.escalatedOnly,
      );

  /// Applies the filter. [sourceProjectId] reads a row's cascade origin
  /// (null = native); [escalatedAt] reads its escalation stamp.
  List<T> apply<T>(
    Iterable<T> rows, {
    required String? Function(T) sourceProjectId,
    required DateTime? Function(T) escalatedAt,
  }) {
    return rows.where((r) {
      final src = sourceProjectId(r);
      if (sourceId == kProgrammeOnly) return src == null;
      if (sourceId != null && src != sourceId) return false;
      if (escalatedOnly && src != null && escalatedAt(r) == null) return false;
      return true;
    }).toList();
  }

  /// Distinct source project ids present in [rows], in first-seen order.
  /// Drives the chip row so only projects that actually contribute show.
  static List<String> sourcesIn<T>(
    Iterable<T> rows, {
    required String? Function(T) sourceProjectId,
  }) {
    final seen = <String>{};
    final out = <String>[];
    for (final r in rows) {
      final s = sourceProjectId(r);
      if (s != null && seen.add(s)) out.add(s);
    }
    return out;
  }
}
