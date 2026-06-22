import 'dart:convert';

/// String IDs for the four SWOT quadrants. Used as keys in the JSON
/// payload and for the drag-drop payload type discrimination.
class SwotQuadrant {
  static const strengths = 'strengths';
  static const weaknesses = 'weaknesses';
  static const opportunities = 'opportunities';
  static const threats = 'threats';

  static const all = [strengths, weaknesses, opportunities, threats];

  /// Pretty display name for a quadrant id. Capitalised, single word.
  static String label(String q) {
    switch (q) {
      case strengths:
        return 'Strengths';
      case weaknesses:
        return 'Weaknesses';
      case opportunities:
        return 'Opportunities';
      case threats:
        return 'Threats';
      default:
        return q;
    }
  }

  /// True for the two "negative-implication" quadrants where it makes
  /// sense to surface a Promote-to-Risk action.
  static bool canPromoteToRisk(String q) =>
      q == weaknesses || q == threats;
}

/// The "SWOT" template content. Four bucketed lists, sorted by [SwotItem.sortOrder]
/// within each bucket.
class SwotContent {
  final List<SwotItem> strengths;
  final List<SwotItem> weaknesses;
  final List<SwotItem> opportunities;
  final List<SwotItem> threats;

  const SwotContent({
    this.strengths = const [],
    this.weaknesses = const [],
    this.opportunities = const [],
    this.threats = const [],
  });

  /// Returns the list for [quadrant] (one of [SwotQuadrant.all]) — used
  /// by the view to render and mutate by quadrant id rather than four
  /// hard-coded code paths.
  List<SwotItem> itemsFor(String quadrant) {
    switch (quadrant) {
      case SwotQuadrant.strengths:
        return strengths;
      case SwotQuadrant.weaknesses:
        return weaknesses;
      case SwotQuadrant.opportunities:
        return opportunities;
      case SwotQuadrant.threats:
        return threats;
      default:
        return const [];
    }
  }

  /// Returns a new content with [quadrant]'s list replaced by [items],
  /// preserving every other quadrant as-is. Item sort_orders should be
  /// pre-renumbered by the caller.
  SwotContent withQuadrant(String quadrant, List<SwotItem> items) {
    switch (quadrant) {
      case SwotQuadrant.strengths:
        return copyWith(strengths: items);
      case SwotQuadrant.weaknesses:
        return copyWith(weaknesses: items);
      case SwotQuadrant.opportunities:
        return copyWith(opportunities: items);
      case SwotQuadrant.threats:
        return copyWith(threats: items);
      default:
        return this;
    }
  }

  SwotContent copyWith({
    List<SwotItem>? strengths,
    List<SwotItem>? weaknesses,
    List<SwotItem>? opportunities,
    List<SwotItem>? threats,
  }) {
    return SwotContent(
      strengths: strengths ?? this.strengths,
      weaknesses: weaknesses ?? this.weaknesses,
      opportunities: opportunities ?? this.opportunities,
      threats: threats ?? this.threats,
    );
  }

  Map<String, dynamic> toJson() => {
        SwotQuadrant.strengths:
            strengths.map((e) => e.toJson()).toList(),
        SwotQuadrant.weaknesses:
            weaknesses.map((e) => e.toJson()).toList(),
        SwotQuadrant.opportunities:
            opportunities.map((e) => e.toJson()).toList(),
        SwotQuadrant.threats:
            threats.map((e) => e.toJson()).toList(),
      };

  factory SwotContent.fromJson(Map<String, dynamic> json) {
    List<SwotItem> readBucket(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      final items = raw
          .whereType<Map>()
          .map((m) => SwotItem.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return items;
    }

    return SwotContent(
      strengths: readBucket(SwotQuadrant.strengths),
      weaknesses: readBucket(SwotQuadrant.weaknesses),
      opportunities: readBucket(SwotQuadrant.opportunities),
      threats: readBucket(SwotQuadrant.threats),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Tolerant decoder: null / empty / wrong-shape / malformed input
  /// yields an empty SWOT rather than throwing.
  factory SwotContent.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const SwotContent();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SwotContent.fromJson(decoded);
      }
    } catch (_) {
      // Fall through.
    }
    return const SwotContent();
  }
}

/// A single SWOT entry. The same shape regardless of which quadrant it
/// belongs to; the quadrant is implicit in which list it sits in.
class SwotItem {
  final String id;
  final String text;
  final int sortOrder;

  /// When non-null, the item has been promoted to a formal item.
  /// [promotedToType] is one of: 'risk' | 'action'. [promotedToId] is
  /// the corresponding DAO row id.
  final String? promotedToType;
  final String? promotedToId;

  const SwotItem({
    required this.id,
    this.text = '',
    this.sortOrder = 0,
    this.promotedToType,
    this.promotedToId,
  });

  SwotItem copyWith({
    String? text,
    int? sortOrder,
    Object? promotedToType = _sentinel,
    Object? promotedToId = _sentinel,
  }) {
    return SwotItem(
      id: id,
      text: text ?? this.text,
      sortOrder: sortOrder ?? this.sortOrder,
      promotedToType: promotedToType == _sentinel
          ? this.promotedToType
          : promotedToType as String?,
      promotedToId: promotedToId == _sentinel
          ? this.promotedToId
          : promotedToId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'sort_order': sortOrder,
        if (promotedToType != null) 'promoted_to_type': promotedToType,
        if (promotedToId != null) 'promoted_to_id': promotedToId,
      };

  factory SwotItem.fromJson(Map<String, dynamic> json) {
    final order = json['sort_order'];
    return SwotItem(
      id: (json['id'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
      sortOrder: order is int
          ? order
          : (order is num ? order.toInt() : 0),
      promotedToType: json['promoted_to_type'] as String?,
      promotedToId: json['promoted_to_id'] as String?,
    );
  }
}

const _sentinel = Object();
