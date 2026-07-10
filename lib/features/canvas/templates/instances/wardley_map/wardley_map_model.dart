import 'dart:convert';

/// Content model for a Wardley map template instance. Serialised as JSON
/// into `CanvasTemplates.content`.
///
/// Positions are fractional (0..1) so they're resolution-independent:
///   - [WardleyComponent.positionX] = evolution: 0 = Genesis (left) →
///     1 = Commodity (right), through Custom-Built and Product.
///   - [WardleyComponent.positionY] = visibility in the value chain:
///     0 = visible to the user (top) → 1 = invisible/infrastructure
///     (bottom).
class WardleyMapContent {
  final List<WardleyComponent> components;
  final List<WardleyDependency> dependencies;

  const WardleyMapContent({
    this.components = const [],
    this.dependencies = const [],
  });

  WardleyMapContent copyWith({
    List<WardleyComponent>? components,
    List<WardleyDependency>? dependencies,
  }) =>
      WardleyMapContent(
        components: components ?? this.components,
        dependencies: dependencies ?? this.dependencies,
      );

  Map<String, dynamic> toJson() => {
        'components': components.map((c) => c.toJson()).toList(),
        'dependencies': dependencies.map((d) => d.toJson()).toList(),
      };

  factory WardleyMapContent.fromJson(Map<String, dynamic> json) {
    final rawComps = json['components'];
    final rawDeps = json['dependencies'];
    return WardleyMapContent(
      components: rawComps is List
          ? rawComps
              .whereType<Map>()
              .map((m) =>
                  WardleyComponent.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      dependencies: rawDeps is List
          ? rawDeps
              .whereType<Map>()
              .map((m) =>
                  WardleyDependency.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }

  String encode() => jsonEncode(toJson());

  /// Tolerant decode — never throws; malformed content yields an empty map.
  factory WardleyMapContent.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const WardleyMapContent();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return WardleyMapContent.fromJson(decoded);
      }
    } catch (_) {}
    return const WardleyMapContent();
  }
}

class WardleyComponent {
  final String id;
  final String name;
  final double positionX; // evolution: 0 genesis → 1 commodity
  final double positionY; // visibility: 0 visible → 1 invisible
  final String? notes;

  const WardleyComponent({
    required this.id,
    required this.name,
    this.positionX = 0.5,
    this.positionY = 0.4,
    this.notes,
  });

  static const _keep = Object();

  WardleyComponent copyWith({
    String? name,
    double? positionX,
    double? positionY,
    Object? notes = _keep,
  }) =>
      WardleyComponent(
        id: id,
        name: name ?? this.name,
        positionX: positionX == null
            ? this.positionX
            : positionX.clamp(0.0, 1.0).toDouble(),
        positionY: positionY == null
            ? this.positionY
            : positionY.clamp(0.0, 1.0).toDouble(),
        notes: identical(notes, _keep) ? this.notes : notes as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'position_x': positionX,
        'position_y': positionY,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  factory WardleyComponent.fromJson(Map<String, dynamic> json) {
    double pos(dynamic v, double fallback) =>
        v is num ? v.toDouble().clamp(0.0, 1.0) : fallback;
    return WardleyComponent(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      positionX: pos(json['position_x'], 0.5),
      positionY: pos(json['position_y'], 0.4),
      notes: json['notes'] as String?,
    );
  }
}

/// A directed "needs" edge: [fromComponentId] depends on [toComponentId].
class WardleyDependency {
  final String id;
  final String fromComponentId;
  final String toComponentId;

  const WardleyDependency({
    required this.id,
    required this.fromComponentId,
    required this.toComponentId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from_component_id': fromComponentId,
        'to_component_id': toComponentId,
      };

  factory WardleyDependency.fromJson(Map<String, dynamic> json) =>
      WardleyDependency(
        id: (json['id'] as String?) ?? '',
        fromComponentId: (json['from_component_id'] as String?) ?? '',
        toComponentId: (json['to_component_id'] as String?) ?? '',
      );
}
