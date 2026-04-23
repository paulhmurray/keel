import 'dart:convert';

import '../database/database.dart';

// ─── RAG enum ─────────────────────────────────────────────────────────────────

enum Rag { green, amber, red, notStarted }

extension RagExtension on Rag {
  String get label => switch (this) {
        Rag.green      => 'Green',
        Rag.amber      => 'Amber',
        Rag.red        => 'Red',
        Rag.notStarted => 'Not started',
      };

  String get value => switch (this) {
        Rag.green      => 'green',
        Rag.amber      => 'amber',
        Rag.red        => 'red',
        Rag.notStarted => 'not_started',
      };
}

Rag ragFromString(String? s) => switch (s) {
      'green'       => Rag.green,
      'amber'       => Rag.amber,
      'red'         => Rag.red,
      _             => Rag.notStarted,
    };

// ─── Trend ────────────────────────────────────────────────────────────────────

enum RagTrend { improved, worsened, steady, noData }

extension RagTrendExtension on RagTrend {
  String get arrow => switch (this) {
        RagTrend.improved  => '↑',
        RagTrend.worsened  => '↓',
        RagTrend.steady    => '→',
        RagTrend.noData    => '',
      };

  String get label => switch (this) {
        RagTrend.improved  => 'Improved',
        RagTrend.worsened  => 'Worsened',
        RagTrend.steady    => 'Steady',
        RagTrend.noData    => '—',
      };
}

// ─── Status data model ────────────────────────────────────────────────────────

class WorkstreamRagStatus {
  final TimelineWorkPackage wp;
  final Rag rag;
  final RagTrend trend;
  final String? previousRagLabel;

  const WorkstreamRagStatus({
    required this.wp,
    required this.rag,
    required this.trend,
    this.previousRagLabel,
  });
}

class ProgrammeStatusData {
  final Rag programmeRag;
  final RagTrend programmeTrend;
  final String? previousRagLabel;
  final List<WorkstreamRagStatus> workstreams;
  final List<TimelineActivity> upcomingMilestones;
  final List<Risk> topRisks;
  final List<Decision> pendingDecisions;
  final int overdueActionsCount;
  final int openActionsCount;
  final int openRisksCount;
  final ProjectPlaybook? projectPlaybook;
  final PlaybookStage? currentStage;
  final ProjectStageProgressesData? stageProgress;

  const ProgrammeStatusData({
    required this.programmeRag,
    required this.programmeTrend,
    this.previousRagLabel,
    required this.workstreams,
    required this.upcomingMilestones,
    required this.topRisks,
    required this.pendingDecisions,
    required this.overdueActionsCount,
    required this.openActionsCount,
    required this.openRisksCount,
    this.projectPlaybook,
    this.currentStage,
    this.stageProgress,
  });

  int get pendingDecisionsCount => pendingDecisions.length;
}

// ─── Calculator ───────────────────────────────────────────────────────────────

class StatusCalculator {
  /// Compute programme RAG from a list of work package RAG values.
  /// RED beats AMBER beats GREEN. Not-started is ignored.
  static Rag computeProgrammeRag(List<TimelineWorkPackage> wps) {
    if (wps.isEmpty) return Rag.notStarted;
    Rag result = Rag.notStarted;
    for (final wp in wps) {
      final r = ragFromString(wp.ragStatus);
      if (r == Rag.red) return Rag.red;
      if (r == Rag.amber) result = Rag.amber;
      if (r == Rag.green && result == Rag.notStarted) result = Rag.green;
    }
    return result;
  }

  /// Compare current RAG to previous to determine trend.
  static RagTrend computeTrend(Rag current, Rag? previous) {
    if (previous == null) return RagTrend.noData;
    if (current == previous) return RagTrend.steady;
    // Better: red→amber, red→green, amber→green
    final score = _ragScore(current) - _ragScore(previous);
    return score > 0 ? RagTrend.improved : RagTrend.worsened;
  }

  static int _ragScore(Rag r) => switch (r) {
        Rag.green      => 3,
        Rag.amber      => 2,
        Rag.red        => 1,
        Rag.notStarted => 0,
      };

  /// Parse workstream RAG map from a snapshot's JSON string.
  static Map<String, String> parseWorkstreamRag(String json) {
    try {
      return (jsonDecode(json) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  /// Encode current workstream RAGs into JSON for snapshot storage.
  static String encodeWorkstreamRag(List<TimelineWorkPackage> wps) {
    final map = {for (final wp in wps) wp.id: wp.ragStatus};
    return jsonEncode(map);
  }

  /// Return the top-3 risks sorted by likelihood × impact score,
  /// tie-broken by most recently updated.
  static List<Risk> topRisks(List<Risk> all, {int limit = 3}) {
    final open = all.where((r) => r.status == 'open').toList();
    open.sort((a, b) {
      final sa = _riskScore(a.likelihood, a.impact);
      final sb = _riskScore(b.likelihood, b.impact);
      if (sa != sb) return sb.compareTo(sa);
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return open.take(limit).toList();
  }

  static int _riskScore(String likelihood, String impact) {
    int l = switch (likelihood) { 'high' => 3, 'medium' => 2, _ => 1 };
    int i = switch (impact) { 'high' => 3, 'medium' => 2, _ => 1 };
    return l * i;
  }

  /// Filter activities to those within the next [days] days.
  static List<TimelineActivity> upcomingMilestones(
    List<TimelineActivity> all,
    List<String> monthLabels, {
    int days = 30,
  }) {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: days));

    // Approximate: map month index to a date using current date as anchor.
    // Month 0 = first month in the timeline. We estimate: if today is in
    // month M, then index M corresponds to the current month.
    // Simple heuristic: treat monthLabels as calendar months where possible.
    return all
        .where((a) =>
            (a.activityType == 'milestone' ||
                a.activityType == 'hard_deadline' ||
                a.activityType == 'gate') &&
            a.startMonth != null)
        .where((a) {
          final date = _approximateDateForMonth(
              a.startMonth!, monthLabels, now);
          if (date == null) return false;
          return date.isAfter(now.subtract(const Duration(days: 1))) &&
              date.isBefore(cutoff);
        })
        .toList()
      ..sort((a, b) => (a.startMonth ?? 0).compareTo(b.startMonth ?? 0));
  }

  static DateTime? _approximateDateForMonth(
      int idx, List<String> labels, DateTime now) {
    // Try to parse "Apr 2026", "April 2026", "Apr", "M3" etc.
    if (idx < 0 || idx >= labels.length) return null;
    final label = labels[idx];

    // Try MMM YYYY
    final full = RegExp(r'^([A-Za-z]+)\s+(\d{4})$').firstMatch(label);
    if (full != null) {
      final month = _monthIndex(full.group(1)!);
      final year = int.tryParse(full.group(2)!);
      if (month != null && year != null) {
        return DateTime(year, month);
      }
    }

    // Try MMM only — assume current or next year
    final abbr = RegExp(r'^([A-Za-z]+)$').firstMatch(label);
    if (abbr != null) {
      final month = _monthIndex(abbr.group(1)!);
      if (month != null) {
        final year = month >= now.month ? now.year : now.year + 1;
        return DateTime(year, month);
      }
    }

    return null;
  }

  static int? _monthIndex(String abbr) {
    const months = {
      'jan': 1, 'january': 1,
      'feb': 2, 'february': 2,
      'mar': 3, 'march': 3,
      'apr': 4, 'april': 4,
      'may': 5,
      'jun': 6, 'june': 6,
      'jul': 7, 'july': 7,
      'aug': 8, 'august': 8,
      'sep': 9, 'september': 9,
      'oct': 10, 'october': 10,
      'nov': 11, 'november': 11,
      'dec': 12, 'december': 12,
    };
    return months[abbr.toLowerCase()];
  }
}
