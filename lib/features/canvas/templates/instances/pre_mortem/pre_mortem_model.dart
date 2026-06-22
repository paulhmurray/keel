import 'dart:convert';

/// The "Pre-mortem" template content schema, as stored in
/// `CanvasTemplates.content`. Plain Dart classes with explicit
/// JSON serialisation — no codegen, so the schema's easy to
/// inspect when reading the template body in the DB.
class PreMortemContent {
  /// The imagined failure state — a sentence the PM sets at the top.
  final String goal;
  final List<PreMortemCause> causes;

  const PreMortemContent({
    this.goal = '',
    this.causes = const [],
  });

  PreMortemContent copyWith({
    String? goal,
    List<PreMortemCause>? causes,
  }) {
    return PreMortemContent(
      goal: goal ?? this.goal,
      causes: causes ?? this.causes,
    );
  }

  Map<String, dynamic> toJson() => {
        'goal': goal,
        'causes': causes.map((c) => c.toJson()).toList(),
      };

  factory PreMortemContent.fromJson(Map<String, dynamic> json) {
    return PreMortemContent(
      goal: json['goal'] is String ? json['goal'] as String : '',
      causes: (json['causes'] is List)
          ? (json['causes'] as List)
              .whereType<Map>()
              .map((m) => PreMortemCause.fromJson(
                  Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }

  String encode() => jsonEncode(toJson());

  /// Tolerant decoder — malformed or empty payloads yield an empty
  /// pre-mortem (instead of throwing or producing partial state).
  factory PreMortemContent.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const PreMortemContent();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PreMortemContent.fromJson(decoded);
      }
    } catch (_) {
      // Fall through to empty.
    }
    return const PreMortemContent();
  }
}

class PreMortemCause {
  final String id;
  final String description;

  /// low | medium | high
  final String likelihood;
  final String impact;

  final List<PreMortemMitigation> mitigations;

  /// When non-null, this cause has been promoted to a Risk row in RAID.
  /// The id points to the [Risks.id] of the created risk.
  final String? promotedToRiskId;

  const PreMortemCause({
    required this.id,
    this.description = '',
    this.likelihood = 'medium',
    this.impact = 'medium',
    this.mitigations = const [],
    this.promotedToRiskId,
  });

  PreMortemCause copyWith({
    String? description,
    String? likelihood,
    String? impact,
    List<PreMortemMitigation>? mitigations,
    Object? promotedToRiskId = _sentinel,
  }) {
    return PreMortemCause(
      id: id,
      description: description ?? this.description,
      likelihood: likelihood ?? this.likelihood,
      impact: impact ?? this.impact,
      mitigations: mitigations ?? this.mitigations,
      promotedToRiskId: promotedToRiskId == _sentinel
          ? this.promotedToRiskId
          : promotedToRiskId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'likelihood': likelihood,
        'impact': impact,
        'mitigations': mitigations.map((m) => m.toJson()).toList(),
        if (promotedToRiskId != null) 'promoted_to_risk_id': promotedToRiskId,
      };

  factory PreMortemCause.fromJson(Map<String, dynamic> json) {
    return PreMortemCause(
      id: (json['id'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      likelihood: _normaliseLevel(json['likelihood']),
      impact: _normaliseLevel(json['impact']),
      mitigations: (json['mitigations'] is List)
          ? (json['mitigations'] as List)
              .whereType<Map>()
              .map((m) => PreMortemMitigation.fromJson(
                  Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      promotedToRiskId: json['promoted_to_risk_id'] as String?,
    );
  }
}

class PreMortemMitigation {
  final String id;
  final String description;
  final String? owner;

  /// When non-null, this mitigation has been promoted to an Action row.
  final String? promotedToActionId;

  const PreMortemMitigation({
    required this.id,
    this.description = '',
    this.owner,
    this.promotedToActionId,
  });

  PreMortemMitigation copyWith({
    String? description,
    Object? owner = _sentinel,
    Object? promotedToActionId = _sentinel,
  }) {
    return PreMortemMitigation(
      id: id,
      description: description ?? this.description,
      owner: owner == _sentinel ? this.owner : owner as String?,
      promotedToActionId: promotedToActionId == _sentinel
          ? this.promotedToActionId
          : promotedToActionId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        if (owner != null) 'owner': owner,
        if (promotedToActionId != null)
          'promoted_to_action_id': promotedToActionId,
      };

  factory PreMortemMitigation.fromJson(Map<String, dynamic> json) {
    return PreMortemMitigation(
      id: (json['id'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      owner: json['owner'] as String?,
      promotedToActionId: json['promoted_to_action_id'] as String?,
    );
  }
}

const _sentinel = Object();

/// Normalises a level field to one of low/medium/high, defaulting to
/// 'medium' when the input is missing or unrecognised.
String _normaliseLevel(dynamic raw) {
  if (raw is String) {
    final v = raw.toLowerCase();
    if (v == 'low' || v == 'medium' || v == 'high') return v;
  }
  return 'medium';
}
