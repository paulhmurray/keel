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
  // "Nov 26 – Mar 27" — the WP's month window, so the RAG carries its
  // timeframe (red with one month left ≠ red with six months of runway).
  final String? spanLabel;

  const WorkstreamRagStatus({
    required this.wp,
    required this.rag,
    required this.trend,
    this.previousRagLabel,
    this.spanLabel,
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

  /// Filter activities to milestone-type entries whose month falls within
  /// the next [days] days. Completed milestones are excluded.
  ///
  /// Milestones are month-granular, so a milestone counts as upcoming if
  /// any part of its month overlaps [now, now + days] — a milestone due
  /// later this month is still upcoming, not already-passed.
  ///
  /// [month0Date] (the Gantt header's ISO date for month index 0) is the
  /// preferred anchor for converting a month index to a calendar month;
  /// parsing [monthLabels] is the fallback for headers that predate it.
  /// [now] is injectable for tests.
  /// The month window a work package occupies — min activity start to
  /// max activity end. Cascaded WPs whose activities stayed private on
  /// the source project fall back to the cascade span. Null when
  /// nothing carries a month.
  static ({int start, int end})? wpMonthSpan(
      TimelineWorkPackage wp, Iterable<TimelineActivity> allActs) {
    int? lo, hi;
    for (final a in allActs) {
      if (a.workPackageId != wp.id) continue;
      final s = a.startMonth;
      final e = a.endMonth ?? a.startMonth;
      if (s != null && (lo == null || s < lo)) lo = s;
      if (e != null && (hi == null || e > hi)) hi = e;
    }
    lo ??= wp.cascadeStartMonth;
    hi ??= wp.cascadeEndMonth ?? lo;
    if (lo == null || hi == null) return null;
    return (start: lo, end: hi);
  }

  static List<TimelineActivity> upcomingMilestones(
    List<TimelineActivity> all,
    List<String> monthLabels, {
    String? month0Date,
    int days = 90,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final cutoff = today.add(Duration(days: days));

    return all
        .where((a) =>
            (a.activityType == 'milestone' ||
                a.activityType == 'hard_deadline' ||
                a.activityType == 'gate') &&
            a.status != 'complete' &&
            a.startMonth != null)
        .where((a) {
          final monthStart = _dateForMonth(
              a.startMonth!, monthLabels, month0Date, today);
          if (monthStart == null) return false;
          final monthEnd =
              DateTime(monthStart.year, monthStart.month + 1, 0);
          return !monthEnd.isBefore(today) && monthStart.isBefore(cutoff);
        })
        .toList()
      ..sort((a, b) => (a.startMonth ?? 0).compareTo(b.startMonth ?? 0));
  }

  static DateTime? _dateForMonth(
      int idx, List<String> labels, String? month0Date, DateTime now) {
    // Preferred: exact anchor date for month 0 from the Gantt header.
    if (month0Date != null) {
      final base = DateTime.tryParse(month0Date);
      if (base != null) return DateTime(base.year, base.month + idx, 1);
    }

    // Fallback: parse the label — "Sep 26", "Sep 2026", "September 2026",
    // or bare "Sep". Placeholder labels like "M3" stay unparseable.
    if (idx < 0 || idx >= labels.length) return null;
    final label = labels[idx];

    // MMM YY or MMM YYYY
    final full = RegExp(r'^([A-Za-z]+)\s+(\d{2}|\d{4})$').firstMatch(label);
    if (full != null) {
      final month = _monthIndex(full.group(1)!);
      var year = int.tryParse(full.group(2)!);
      if (month != null && year != null) {
        if (year < 100) year += 2000;
        return DateTime(year, month);
      }
    }

    // MMM only — assume current or next year
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
