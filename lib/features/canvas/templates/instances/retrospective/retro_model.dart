import 'dart:convert';

/// Column identifiers for the Start / Stop / Continue / Learn retro.
/// The string values match the JSON keys on disk (don't rename without
/// a data migration).
class RetroColumn {
  static const start = 'start';
  static const stop = 'stop';
  static const cont = 'continue'; // Dart keyword — variable name is `cont`.
  static const learn = 'learn';

  static const all = [start, stop, cont, learn];

  /// Display label for a column id.
  static String label(String c) {
    switch (c) {
      case start:
        return 'Start';
      case stop:
        return 'Stop';
      case cont:
        return 'Continue';
      case learn:
        return 'Learn';
      default:
        return c;
    }
  }

  /// One-line subtitle shown under each column header.
  static String subtitle(String c) {
    switch (c) {
      case start:
        return "what's not happening yet";
      case stop:
        return "what's not working";
      case cont:
        return "what's working";
      case learn:
        return 'insights to carry forward';
      default:
        return '';
    }
  }

  /// Only Start items are eligible for "Promote to Action" per the
  /// canonical retro pattern — the other columns are reflection-only.
  /// (Easy to relax later if the team wants to action Stop items too.)
  static bool canPromoteToAction(String c) => c == start;
}

/// The "Retrospective" template content. Four columns of items, sorted
/// by [RetroItem.votes] descending within each column, ties broken by
/// [RetroItem.sortOrder].
class RetroContent {
  final List<RetroItem> start;
  final List<RetroItem> stop;
  // Renamed because `continue` is a reserved Dart keyword. The JSON
  // key is still 'continue' (see [toJson] / [fromJson]).
  final List<RetroItem> continueItems;
  final List<RetroItem> learn;

  const RetroContent({
    this.start = const [],
    this.stop = const [],
    this.continueItems = const [],
    this.learn = const [],
  });

  /// Returns the list for [column], sorted by votes descending then
  /// sortOrder ascending. Sorting in the accessor keeps the view code
  /// simple — mutations don't have to re-sort, and the on-disk JSON
  /// is canonical (also sorted on decode).
  List<RetroItem> itemsFor(String column) {
    final raw = _rawFor(column);
    final out = [...raw];
    out.sort((a, b) {
      final byVotes = b.votes.compareTo(a.votes);
      if (byVotes != 0) return byVotes;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return out;
  }

  List<RetroItem> _rawFor(String column) {
    switch (column) {
      case RetroColumn.start:
        return start;
      case RetroColumn.stop:
        return stop;
      case RetroColumn.cont:
        return continueItems;
      case RetroColumn.learn:
        return learn;
      default:
        return const [];
    }
  }

  /// Returns a new content with [column]'s list replaced by [items].
  /// Caller is responsible for renumbering sortOrder if needed.
  RetroContent withColumn(String column, List<RetroItem> items) {
    switch (column) {
      case RetroColumn.start:
        return copyWith(start: items);
      case RetroColumn.stop:
        return copyWith(stop: items);
      case RetroColumn.cont:
        return copyWith(continueItems: items);
      case RetroColumn.learn:
        return copyWith(learn: items);
      default:
        return this;
    }
  }

  RetroContent copyWith({
    List<RetroItem>? start,
    List<RetroItem>? stop,
    List<RetroItem>? continueItems,
    List<RetroItem>? learn,
  }) {
    return RetroContent(
      start: start ?? this.start,
      stop: stop ?? this.stop,
      continueItems: continueItems ?? this.continueItems,
      learn: learn ?? this.learn,
    );
  }

  Map<String, dynamic> toJson() => {
        RetroColumn.start: start.map((e) => e.toJson()).toList(),
        RetroColumn.stop: stop.map((e) => e.toJson()).toList(),
        RetroColumn.cont: continueItems.map((e) => e.toJson()).toList(),
        RetroColumn.learn: learn.map((e) => e.toJson()).toList(),
      };

  factory RetroContent.fromJson(Map<String, dynamic> json) {
    List<RetroItem> readColumn(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      final items = raw
          .whereType<Map>()
          .map((m) => RetroItem.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      // Sort: votes desc, then sortOrder asc (stable tie-break).
      items.sort((a, b) {
        final byVotes = b.votes.compareTo(a.votes);
        if (byVotes != 0) return byVotes;
        return a.sortOrder.compareTo(b.sortOrder);
      });
      return items;
    }

    return RetroContent(
      start: readColumn(RetroColumn.start),
      stop: readColumn(RetroColumn.stop),
      continueItems: readColumn(RetroColumn.cont),
      learn: readColumn(RetroColumn.learn),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Tolerant decoder.
  factory RetroContent.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const RetroContent();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return RetroContent.fromJson(decoded);
      }
    } catch (_) {
      // Fall through.
    }
    return const RetroContent();
  }
}

/// A single retro card.
class RetroItem {
  final String id;
  final String title;
  final String? notes;
  final int votes;
  final int sortOrder;

  /// Non-null once the item has been promoted to an Action row.
  final String? promotedToActionId;

  const RetroItem({
    required this.id,
    this.title = '',
    this.notes,
    this.votes = 0,
    this.sortOrder = 0,
    this.promotedToActionId,
  });

  RetroItem copyWith({
    String? title,
    Object? notes = _sentinel,
    int? votes,
    int? sortOrder,
    Object? promotedToActionId = _sentinel,
  }) {
    return RetroItem(
      id: id,
      title: title ?? this.title,
      notes: notes == _sentinel ? this.notes : notes as String?,
      votes: votes ?? this.votes,
      sortOrder: sortOrder ?? this.sortOrder,
      promotedToActionId: promotedToActionId == _sentinel
          ? this.promotedToActionId
          : promotedToActionId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'votes': votes,
        'sort_order': sortOrder,
        if (promotedToActionId != null)
          'promoted_to_action_id': promotedToActionId,
      };

  factory RetroItem.fromJson(Map<String, dynamic> json) {
    final votes = json['votes'];
    final sortOrder = json['sort_order'];
    return RetroItem(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      notes: json['notes'] as String?,
      votes: votes is int
          ? votes
          : (votes is num ? votes.toInt() : 0),
      sortOrder: sortOrder is int
          ? sortOrder
          : (sortOrder is num ? sortOrder.toInt() : 0),
      promotedToActionId: json['promoted_to_action_id'] as String?,
    );
  }
}

const _sentinel = Object();
