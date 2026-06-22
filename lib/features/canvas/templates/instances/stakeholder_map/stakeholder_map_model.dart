import 'dart:convert';

/// Content schema for the Stakeholder Map template — a 2×2 grid of
/// Influence × Interest with each stakeholder positioned at a (x, y)
/// fraction of the grid.
///
/// Positions are independent of `StakeholderProfiles.influence/interest`
/// in the People module — this template is a private strategic
/// thinking surface; positions here don't sync back. (Future work may
/// wire the two together via a per-template toggle.)
class StakeholderMapContent {
  final List<StakeholderDot> stakeholders;

  const StakeholderMapContent({this.stakeholders = const []});

  /// Convenience: was this person already placed on the map?
  bool containsPerson(String personId) =>
      stakeholders.any((d) => d.personId == personId);

  StakeholderMapContent copyWith({List<StakeholderDot>? stakeholders}) {
    return StakeholderMapContent(
      stakeholders: stakeholders ?? this.stakeholders,
    );
  }

  Map<String, dynamic> toJson() => {
        'stakeholders': stakeholders.map((d) => d.toJson()).toList(),
      };

  factory StakeholderMapContent.fromJson(Map<String, dynamic> json) {
    final raw = json['stakeholders'];
    if (raw is! List) return const StakeholderMapContent();
    return StakeholderMapContent(
      stakeholders: raw
          .whereType<Map>()
          .map((m) => StakeholderDot.fromJson(
              Map<String, dynamic>.from(m)))
          .toList(),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Tolerant decoder — never throws.
  factory StakeholderMapContent.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const StakeholderMapContent();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return StakeholderMapContent.fromJson(decoded);
      }
    } catch (_) {
      // Fall through.
    }
    return const StakeholderMapContent();
  }
}

/// One stakeholder placed on the map.
///
/// [positionX] runs left → right; 0 = low interest, 1 = high interest.
/// [positionY] runs top → bottom; 0 = high influence, 1 = low influence.
/// (This matches Stack/Positioned coordinates: y=0 is the top of the
/// grid, where high-influence stakeholders sit.)
class StakeholderDot {
  final String id;
  final String personId;
  final double positionX;
  final double positionY;
  final String? notes;

  const StakeholderDot({
    required this.id,
    required this.personId,
    this.positionX = 0.5,
    this.positionY = 0.5,
    this.notes,
  });

  StakeholderDot copyWith({
    double? positionX,
    double? positionY,
    Object? notes = _sentinel,
  }) {
    return StakeholderDot(
      id: id,
      personId: personId,
      positionX: positionX == null
          ? this.positionX
          : positionX.clamp(0.0, 1.0).toDouble(),
      positionY: positionY == null
          ? this.positionY
          : positionY.clamp(0.0, 1.0).toDouble(),
      notes: notes == _sentinel ? this.notes : notes as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'person_id': personId,
        'position_x': positionX,
        'position_y': positionY,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  factory StakeholderDot.fromJson(Map<String, dynamic> json) {
    double readPos(dynamic v) {
      if (v is num) return v.toDouble().clamp(0.0, 1.0);
      return 0.5;
    }

    return StakeholderDot(
      id: (json['id'] as String?) ?? '',
      personId: (json['person_id'] as String?) ?? '',
      positionX: readPos(json['position_x']),
      positionY: readPos(json['position_y']),
      notes: json['notes'] as String?,
    );
  }
}

const _sentinel = Object();

/// The four named quadrants. Used for the faint background labels on
/// the grid. Tuple-style — given an (x, y) fraction we can look up
/// which quadrant it falls in.
class StakeholderQuadrant {
  static const manageClosely = 'Manage Closely';
  static const keepSatisfied = 'Keep Satisfied';
  static const keepInformed = 'Keep Informed';
  static const monitor = 'Monitor';

  /// Returns the canonical label for the quadrant containing (x, y).
  /// x ∈ [0,1] is interest, y ∈ [0,1] is INFLUENCE (with y=0 = high).
  static String at(double x, double y) {
    final highInfluence = y < 0.5;
    final highInterest = x >= 0.5;
    if (highInfluence && highInterest) return manageClosely;
    if (highInfluence && !highInterest) return keepSatisfied;
    if (!highInfluence && highInterest) return keepInformed;
    return monitor;
  }
}
