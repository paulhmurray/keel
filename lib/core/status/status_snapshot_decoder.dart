import 'dart:convert';

import '../database/database.dart';

/// Decoded view of a single workstream's frozen state at snapshot time.
class SnapshotWorkstream {
  final String id;
  final String name;
  final String rag;

  const SnapshotWorkstream({
    required this.id,
    required this.name,
    required this.rag,
  });
}

/// Decoded view of a frozen risk on a snapshot.
class SnapshotRisk {
  final String id;
  final String? ref;
  final String description;
  final String likelihood;
  final String impact;

  const SnapshotRisk({
    required this.id,
    required this.ref,
    required this.description,
    required this.likelihood,
    required this.impact,
  });
}

/// Decoded view of a frozen upcoming milestone.
class SnapshotMilestone {
  final String id;
  final String name;
  final String? owner;
  final String? monthLabel;

  const SnapshotMilestone({
    required this.id,
    required this.name,
    required this.owner,
    required this.monthLabel,
  });
}

/// Decoded view of a frozen pending decision.
class SnapshotDecision {
  final String id;
  final String? ref;
  final String description;
  final String? dueDate;
  final String? owner;

  const SnapshotDecision({
    required this.id,
    required this.ref,
    required this.description,
    required this.dueDate,
    required this.owner,
  });
}

/// Decoded view of a frozen playbook stage.
class SnapshotPlaybookStage {
  final String stageId;
  final String stageName;
  final String status;

  const SnapshotPlaybookStage({
    required this.stageId,
    required this.stageName,
    required this.status,
  });
}

/// Decodes the JSON columns on a [StatusSnapshot] row into typed lists.
///
/// All decoders return empty lists / null for missing or malformed data —
/// snapshots from before schema v19 (which have null JSON columns) are
/// treated as snapshots with no rich data, not as errors.
class SnapshotDecoder {
  static List<SnapshotWorkstream> workstreams(StatusSnapshot s) {
    return _decodeList(s.workstreamHealthJson, (m) => SnapshotWorkstream(
          id: m['id'] as String,
          name: m['name'] as String,
          rag: m['rag'] as String,
        ));
  }

  static List<SnapshotRisk> topRisks(StatusSnapshot s) {
    return _decodeList(s.topRisksJson, (m) => SnapshotRisk(
          id: m['id'] as String,
          ref: m['ref'] as String?,
          description: m['description'] as String,
          likelihood: m['likelihood'] as String,
          impact: m['impact'] as String,
        ));
  }

  static List<SnapshotMilestone> upcomingMilestones(StatusSnapshot s) {
    return _decodeList(s.upcomingMilestonesJson, (m) => SnapshotMilestone(
          id: m['id'] as String,
          name: m['name'] as String,
          owner: m['owner'] as String?,
          monthLabel: m['monthLabel'] as String?,
        ));
  }

  static List<SnapshotDecision> pendingDecisions(StatusSnapshot s) {
    return _decodeList(s.pendingDecisionsJson, (m) => SnapshotDecision(
          id: m['id'] as String,
          ref: m['ref'] as String?,
          description: m['description'] as String,
          dueDate: m['dueDate'] as String?,
          owner: m['owner'] as String?,
        ));
  }

  static SnapshotPlaybookStage? playbookStage(StatusSnapshot s) {
    final raw = s.playbookStageJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return SnapshotPlaybookStage(
        stageId: m['stageId'] as String,
        stageName: m['stageName'] as String,
        status: m['status'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  static List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) build,
  ) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(build)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
