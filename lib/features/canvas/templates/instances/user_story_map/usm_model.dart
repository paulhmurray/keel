import 'dart:convert';

/// Content schema for the User Story Map template (Jeff Patton structure).
///
/// Layout intent (laid out by the view):
///   Activities → Tasks (under each activity, left-to-right)
///   Releases (top-to-bottom swimlanes)
///   Stories at each (task × release) intersection.
class UsmContent {
  final List<UsmActivity> activities;
  final List<UsmRelease> releases;
  final List<UsmStory> stories;

  const UsmContent({
    this.activities = const [],
    this.releases = const [],
    this.stories = const [],
  });

  /// All tasks across all activities, flattened in render order.
  List<UsmTask> get allTasks => [
        for (final a in activities) ...a.tasks,
      ];

  /// Stories at a specific (taskId, releaseId) cell, in title order
  /// (stable across edits).
  List<UsmStory> storiesAt(String taskId, String releaseId) {
    return stories
        .where((s) => s.taskId == taskId && s.releaseId == releaseId)
        .toList();
  }

  UsmContent copyWith({
    List<UsmActivity>? activities,
    List<UsmRelease>? releases,
    List<UsmStory>? stories,
  }) {
    return UsmContent(
      activities: activities ?? this.activities,
      releases: releases ?? this.releases,
      stories: stories ?? this.stories,
    );
  }

  Map<String, dynamic> toJson() => {
        'activities': activities.map((a) => a.toJson()).toList(),
        'releases': releases.map((r) => r.toJson()).toList(),
        'stories': stories.map((s) => s.toJson()).toList(),
      };

  factory UsmContent.fromJson(Map<String, dynamic> json) {
    List<T> readList<T>(
        String key, T Function(Map<String, dynamic>) build) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => build(Map<String, dynamic>.from(m)))
          .toList();
    }

    final activities = readList('activities', UsmActivity.fromJson)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final releases = readList('releases', UsmRelease.fromJson)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final stories = readList('stories', UsmStory.fromJson);
    return UsmContent(
      activities: activities,
      releases: releases,
      stories: stories,
    );
  }

  String encode() => jsonEncode(toJson());

  factory UsmContent.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const UsmContent();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return UsmContent.fromJson(decoded);
      }
    } catch (_) {
      // Fall through to empty.
    }
    return const UsmContent();
  }
}

class UsmActivity {
  final String id;
  final String name;
  final int sortOrder;
  final List<UsmTask> tasks;

  const UsmActivity({
    required this.id,
    this.name = '',
    this.sortOrder = 0,
    this.tasks = const [],
  });

  UsmActivity copyWith({
    String? name,
    int? sortOrder,
    List<UsmTask>? tasks,
  }) {
    return UsmActivity(
      id: id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      tasks: tasks ?? this.tasks,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };

  factory UsmActivity.fromJson(Map<String, dynamic> json) {
    final order = json['sort_order'];
    final taskList = (json['tasks'] is List)
        ? (json['tasks'] as List)
            .whereType<Map>()
            .map((m) => UsmTask.fromJson(Map<String, dynamic>.from(m)))
            .toList()
        : <UsmTask>[];
    taskList.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return UsmActivity(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sortOrder: order is int ? order : (order is num ? order.toInt() : 0),
      tasks: taskList,
    );
  }
}

class UsmTask {
  final String id;
  final String name;
  final int sortOrder;

  const UsmTask({
    required this.id,
    this.name = '',
    this.sortOrder = 0,
  });

  UsmTask copyWith({String? name, int? sortOrder}) {
    return UsmTask(
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

  factory UsmTask.fromJson(Map<String, dynamic> json) {
    final order = json['sort_order'];
    return UsmTask(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sortOrder: order is int ? order : (order is num ? order.toInt() : 0),
    );
  }
}

class UsmRelease {
  final String id;
  final String name;
  final int sortOrder;

  const UsmRelease({
    required this.id,
    this.name = '',
    this.sortOrder = 0,
  });

  UsmRelease copyWith({String? name, int? sortOrder}) {
    return UsmRelease(
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

  factory UsmRelease.fromJson(Map<String, dynamic> json) {
    final order = json['sort_order'];
    return UsmRelease(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sortOrder: order is int ? order : (order is num ? order.toInt() : 0),
    );
  }
}

class UsmStory {
  final String id;
  final String taskId;
  final String releaseId;
  final String title;
  final String? description;
  final String? estimate;
  final List<String> tags;
  final List<String> acceptanceCriteria;

  const UsmStory({
    required this.id,
    required this.taskId,
    required this.releaseId,
    this.title = '',
    this.description,
    this.estimate,
    this.tags = const [],
    this.acceptanceCriteria = const [],
  });

  UsmStory copyWith({
    String? taskId,
    String? releaseId,
    String? title,
    Object? description = _sentinel,
    Object? estimate = _sentinel,
    List<String>? tags,
    List<String>? acceptanceCriteria,
  }) {
    return UsmStory(
      id: id,
      taskId: taskId ?? this.taskId,
      releaseId: releaseId ?? this.releaseId,
      title: title ?? this.title,
      description: description == _sentinel
          ? this.description
          : description as String?,
      estimate: estimate == _sentinel
          ? this.estimate
          : estimate as String?,
      tags: tags ?? this.tags,
      acceptanceCriteria:
          acceptanceCriteria ?? this.acceptanceCriteria,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'task_id': taskId,
        'release_id': releaseId,
        'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        if (estimate != null && estimate!.isNotEmpty) 'estimate': estimate,
        if (tags.isNotEmpty) 'tags': tags,
        if (acceptanceCriteria.isNotEmpty)
          'acceptance_criteria': acceptanceCriteria,
      };

  factory UsmStory.fromJson(Map<String, dynamic> json) {
    List<String> stringList(dynamic v) {
      if (v is! List) return const [];
      return v.whereType<String>().toList(growable: false);
    }

    return UsmStory(
      id: (json['id'] as String?) ?? '',
      taskId: (json['task_id'] as String?) ?? '',
      releaseId: (json['release_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      estimate: json['estimate'] as String?,
      tags: stringList(json['tags']),
      acceptanceCriteria: stringList(json['acceptance_criteria']),
    );
  }
}

const _sentinel = Object();
