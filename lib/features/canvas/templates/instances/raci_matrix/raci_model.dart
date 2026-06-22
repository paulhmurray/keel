import 'dart:convert';

/// Role values for the four RACI letters. Stored verbatim in JSON.
class RaciRole {
  static const responsible = 'R';
  static const accountable = 'A';
  static const consulted = 'C';
  static const informed = 'I';

  /// Click-cycle order: blank → R → A → C → I → blank …
  /// Cell tap calls [next] with the current role (null = blank) and
  /// receives the next role (or null) to write.
  static String? next(String? current) {
    switch (current) {
      case null:
        return responsible;
      case responsible:
        return accountable;
      case accountable:
        return consulted;
      case consulted:
        return informed;
      case informed:
        return null;
      default:
        return responsible;
    }
  }

  /// Human label used in the legend.
  static String label(String role) {
    switch (role) {
      case responsible:
        return 'Responsible';
      case accountable:
        return 'Accountable';
      case consulted:
        return 'Consulted';
      case informed:
        return 'Informed';
      default:
        return role;
    }
  }
}

/// Content schema for the RACI Matrix template.
class RaciContent {
  final List<RaciActivity> activities;
  final List<RaciPerson> people;
  final List<RaciAssignment> assignments;

  const RaciContent({
    this.activities = const [],
    this.people = const [],
    this.assignments = const [],
  });

  /// Returns the role for (activityId, personId) or null when blank.
  String? roleFor(String activityId, String personId) {
    for (final a in assignments) {
      if (a.activityId == activityId && a.personId == personId) {
        return a.role;
      }
    }
    return null;
  }

  /// Returns the activities a person has each role for. Used by the
  /// per-person "RACI summary" panel (not wired in V1; helper kept for
  /// future use and for tests to assert the shape is sensible).
  Map<String, List<String>> activitiesByRole(String personId) {
    final out = {
      RaciRole.responsible: <String>[],
      RaciRole.accountable: <String>[],
      RaciRole.consulted: <String>[],
      RaciRole.informed: <String>[],
    };
    final byId = {for (final a in activities) a.id: a};
    for (final a in assignments) {
      if (a.personId != personId) continue;
      final role = a.role;
      if (role == null) continue;
      final name = byId[a.activityId]?.name;
      if (name == null) continue;
      out.putIfAbsent(role, () => <String>[]).add(name);
    }
    return out;
  }

  RaciContent copyWith({
    List<RaciActivity>? activities,
    List<RaciPerson>? people,
    List<RaciAssignment>? assignments,
  }) {
    return RaciContent(
      activities: activities ?? this.activities,
      people: people ?? this.people,
      assignments: assignments ?? this.assignments,
    );
  }

  Map<String, dynamic> toJson() => {
        'activities': activities.map((a) => a.toJson()).toList(),
        'people': people.map((p) => p.toJson()).toList(),
        'assignments': assignments.map((a) => a.toJson()).toList(),
      };

  factory RaciContent.fromJson(Map<String, dynamic> json) {
    List<T> readList<T>(
        String key, T Function(Map<String, dynamic>) build) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => build(Map<String, dynamic>.from(m)))
          .toList();
    }

    final activities = readList('activities', RaciActivity.fromJson)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final people = readList('people', RaciPerson.fromJson)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final assignments = readList('assignments', RaciAssignment.fromJson);
    return RaciContent(
      activities: activities,
      people: people,
      assignments: assignments,
    );
  }

  String encode() => jsonEncode(toJson());

  /// Tolerant decoder — never throws.
  factory RaciContent.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const RaciContent();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return RaciContent.fromJson(decoded);
      }
    } catch (_) {
      // Fall through.
    }
    return const RaciContent();
  }
}

class RaciActivity {
  final String id;
  final String name;
  final int sortOrder;

  const RaciActivity({
    required this.id,
    this.name = '',
    this.sortOrder = 0,
  });

  RaciActivity copyWith({String? name, int? sortOrder}) {
    return RaciActivity(
      id: id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
      };

  factory RaciActivity.fromJson(Map<String, dynamic> json) {
    final order = json['sort_order'];
    return RaciActivity(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sortOrder:
          order is int ? order : (order is num ? order.toInt() : 0),
    );
  }
}

class RaciPerson {
  final String id;
  final String name;

  /// Optional FK back to the People module. When non-null the row was
  /// added by picking an existing project Person; null means the name
  /// is a free-text label entered by the user.
  final String? personId;
  final int sortOrder;

  const RaciPerson({
    required this.id,
    this.name = '',
    this.personId,
    this.sortOrder = 0,
  });

  RaciPerson copyWith({
    String? name,
    Object? personId = _sentinel,
    int? sortOrder,
  }) {
    return RaciPerson(
      id: id,
      name: name ?? this.name,
      personId: personId == _sentinel
          ? this.personId
          : personId as String?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (personId != null) 'person_id': personId,
        'sort_order': sortOrder,
      };

  factory RaciPerson.fromJson(Map<String, dynamic> json) {
    final order = json['sort_order'];
    return RaciPerson(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      personId: json['person_id'] as String?,
      sortOrder:
          order is int ? order : (order is num ? order.toInt() : 0),
    );
  }
}

class RaciAssignment {
  final String activityId;
  final String personId;

  /// One of R/A/C/I, or null for blank. (We store the row even when
  /// blank-cycled-through so the cycle stays predictable, but during
  /// the click-cycle path we prefer to remove blank rows to keep the
  /// JSON small — the view's _setCell does that.)
  final String? role;

  const RaciAssignment({
    required this.activityId,
    required this.personId,
    this.role,
  });

  RaciAssignment copyWith({Object? role = _sentinel}) {
    return RaciAssignment(
      activityId: activityId,
      personId: personId,
      role: role == _sentinel ? this.role : role as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'activity_id': activityId,
        'person_id': personId,
        if (role != null) 'role': role,
      };

  factory RaciAssignment.fromJson(Map<String, dynamic> json) {
    return RaciAssignment(
      activityId: (json['activity_id'] as String?) ?? '',
      personId: (json['person_id'] as String?) ?? '',
      role: json['role'] as String?,
    );
  }
}

const _sentinel = Object();
