/// The "Planview Risks" sheet: the shape TAC's Planview register expects,
/// used both ways — exported from Keel into the workbook so the PM can
/// paste it into Planview, and read back by the import tool. Pure Dart:
/// the row model, the header list, date parsing and the match logic
/// that decides whether a sheet row updates an existing risk or creates
/// a new one.
library;

import '../database/database.dart';
import '../journal/journal_match.dart' show distinctiveWords;
import 'risk_rating.dart';

/// Column headers, verbatim and in order.
const List<String> kPlanviewRiskHeaders = [
  'REF',
  'SteerCo',
  'RISK (title)',
  'DESCRIPTION',
  'RISK OWNER',
  'RISK ASSIGNEE',
  'LIKELIHOOD (current)',
  'CONSEQUENCE (current)',
  'STRATEGY',
  'TREATMENT PLAN',
  'LIKELIHOOD (target)',
  'CONSEQUENCE (target)',
  'RAISED ON',
  'DUE DATE',
  'LAST REVIEW',
  'NEXT REVIEW',
  'NOTES (status update)',
  'ENTERPRISE RISK LINK',
];

const String kPlanviewEscalateMark = '▲ ESCALATE';
const String kPlanviewProgrammeMark = 'programme';

/// Legend lines printed under the table, matching the register's own.
const List<String> kPlanviewLegend = [
  'Current rating = the risk as it stands today. Target rating = residual '
      'rating expected once the treatment plan is delivered; if it equals the '
      'current rating the strategy should be Tolerate, not Treat.',
  'Owner = accountable for the risk and reports on it. Assignee = does the '
      'treatment plan. Where the risk sits with another party the owner is on '
      'their side and the assignee is whoever on ours is chasing it.',
  'Strategy: Treat = mitigation reduces likelihood or consequence. Tolerate = '
      'accepted, monitored, no spend. Transfer = sits with another project or '
      'contract. Terminate = cause removed; recommend closing.',
  'Review cadence: fortnightly, aligned to business-owner reporting. Due date '
      '= when the treatment plan should have taken effect; "—" for '
      'Tolerate/Terminate.',
];

class PlanviewRiskRow {
  final String ref;
  final bool steerco;
  final String title;
  final String description;
  final String? owner;
  final String? assignee;
  final String likelihood; // normalised scale word
  final String consequence; // normalised scale word
  final String strategy; // treat|tolerate|transfer|terminate
  final String? treatmentPlan;
  final String? likelihoodTarget;
  final String? consequenceTarget;
  final String? raisedOn; // ISO or null
  final String? dueDate; // ISO or null
  final String? lastReview; // ISO or null
  final String? nextReview; // ISO or null
  final String? statusNote;
  final String? enterpriseRiskLink;

  const PlanviewRiskRow({
    required this.ref,
    required this.steerco,
    required this.title,
    required this.description,
    this.owner,
    this.assignee,
    required this.likelihood,
    required this.consequence,
    required this.strategy,
    this.treatmentPlan,
    this.likelihoodTarget,
    this.consequenceTarget,
    this.raisedOn,
    this.dueDate,
    this.lastReview,
    this.nextReview,
    this.statusNote,
    this.enterpriseRiskLink,
  });

  /// Builds a row from the sheet's cell strings, in header order.
  /// Returns null for blank, legend or note rows (no R-ref in column A).
  static PlanviewRiskRow? fromCells(List<String?> cells) {
    String? at(int i) {
      if (i >= cells.length) return null;
      final v = cells[i]?.trim();
      return v == null || v.isEmpty || v == '—' || v == '-' ? null : v;
    }

    final ref = at(0);
    if (ref == null || !RegExp(r'^R\d+$').hasMatch(ref)) return null;
    final steercoCell = (at(1) ?? '').toLowerCase();
    return PlanviewRiskRow(
      ref: ref,
      steerco: steercoCell.contains('escalate'),
      title: at(2) ?? '',
      description: at(3) ?? at(2) ?? '',
      owner: at(4),
      assignee: at(5),
      likelihood: normaliseLikelihood(at(6)),
      consequence: normaliseConsequence(at(7)),
      strategy: normaliseStrategy(at(8)),
      treatmentPlan: at(9),
      likelihoodTarget: at(10) == null ? null : normaliseLikelihood(at(10)),
      consequenceTarget:
          at(11) == null ? null : normaliseConsequence(at(11)),
      raisedOn: parsePlanviewDate(at(12)),
      dueDate: parsePlanviewDate(at(13)),
      lastReview: parsePlanviewDate(at(14)),
      nextReview: parsePlanviewDate(at(15)),
      statusNote: at(16),
      enterpriseRiskLink: at(17),
    );
  }
}

String normaliseStrategy(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  return kRiskStrategies.contains(v) ? v : 'treat';
}

const _kMonths = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Parses the register's date styles — "4 Sep 26", "04 Sep 2026",
/// "2026-09-04", "—" — to an ISO date, or null.
String? parsePlanviewDate(String? raw) {
  if (raw == null) return null;
  final v = raw.trim();
  if (v.isEmpty || v == '—' || v == '-') return null;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
  if (iso != null) return v.substring(0, 10);
  final m = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3,4})\.?\s+(\d{2}|\d{4})$')
      .firstMatch(v);
  if (m == null) return null;
  final day = int.parse(m.group(1)!);
  final month = _kMonths[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  var year = int.parse(m.group(3)!);
  if (year < 100) year += 2000;
  return '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// "4 Sep 26" from an ISO date, the register's display style; "—" for null.
String formatPlanviewDate(String? iso) {
  if (iso == null || iso.length < 10) return '—';
  final y = int.tryParse(iso.substring(0, 4));
  final mo = int.tryParse(iso.substring(5, 7));
  final d = int.tryParse(iso.substring(8, 10));
  if (y == null || mo == null || d == null) return '—';
  const names = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '$d ${names[mo - 1]} ${(y % 100).toString().padLeft(2, '0')}';
}

/// Cell strings for one risk, in [kPlanviewRiskHeaders] order.
List<String> planviewCellsFor(Risk r) => [
      r.ref ?? '',
      r.steerco ? kPlanviewEscalateMark : kPlanviewProgrammeMark,
      r.title ?? '',
      r.description,
      r.owner ?? '',
      r.assignee ?? '',
      likelihoodLabel(r.likelihood),
      consequenceLabel(r.impact),
      r.strategy.isEmpty
          ? 'Treat'
          : r.strategy[0].toUpperCase() + r.strategy.substring(1),
      r.mitigation ?? '',
      r.likelihoodTarget == null ? '' : likelihoodLabel(r.likelihoodTarget),
      r.impactTarget == null ? '' : consequenceLabel(r.impactTarget),
      formatPlanviewDate(r.createdAt.toIso8601String().substring(0, 10)),
      formatPlanviewDate(r.dueDate),
      formatPlanviewDate(r.lastReviewedAt),
      formatPlanviewDate(r.nextReviewAt),
      r.statusNote ?? '',
      r.enterpriseRiskLink ?? '',
    ];

// ─── Import matching ─────────────────────────────────────────────────────────

enum PlanviewMatchKind {
  /// Same ref, same risk: update in place.
  update,

  /// Ref not in Keel: create.
  create,

  /// Same ref but a different risk: the sheet's ref wins (it is what
  /// Planview knows); the existing Keel row is renumbered.
  renumber,
}

class PlanviewMatch {
  final PlanviewRiskRow row;
  final PlanviewMatchKind kind;
  final Risk? existing;

  /// For [PlanviewMatchKind.renumber]: the ref the Keel row moves to.
  final String? newRefForExisting;

  const PlanviewMatch({
    required this.row,
    required this.kind,
    this.existing,
    this.newRefForExisting,
  });
}

/// Word overlap between a sheet row and the Keel row holding the same
/// ref, as a share of the SHORTER side's distinctive words — the
/// register often rewrites a one-line Keel risk into a titled paragraph,
/// so measuring against the longer side would call them different.
/// Below this the two are treated as different risks.
const double kPlanviewSameRiskThreshold = 0.25;

/// Decides what each sheet row does to the register. Pure, so the tool
/// can dry-run it and the tests can pin the R21-style collision.
List<PlanviewMatch> planPlanviewImport(
    List<PlanviewRiskRow> rows, List<Risk> existing) {
  final byRef = <String, Risk>{
    for (final r in existing)
      if (r.ref != null) r.ref!: r,
  };
  var maxRef = 0;
  for (final r in existing) {
    final n = int.tryParse((r.ref ?? '').replaceFirst('R', ''));
    if (n != null && n > maxRef) maxRef = n;
  }
  for (final row in rows) {
    final n = int.tryParse(row.ref.replaceFirst('R', ''));
    if (n != null && n > maxRef) maxRef = n;
  }

  final out = <PlanviewMatch>[];
  for (final row in rows) {
    final hit = byRef[row.ref];
    if (hit == null) {
      out.add(PlanviewMatch(row: row, kind: PlanviewMatchKind.create));
      continue;
    }
    final want = distinctiveWords('${row.title} ${row.description}');
    final have = distinctiveWords('${hit.title ?? ''} ${hit.description}');
    final shorter = want.length < have.length ? want.length : have.length;
    final overlap =
        shorter == 0 ? 0.0 : want.intersection(have).length / shorter;
    if (overlap >= kPlanviewSameRiskThreshold) {
      out.add(PlanviewMatch(
          row: row, kind: PlanviewMatchKind.update, existing: hit));
    } else {
      maxRef += 1;
      out.add(PlanviewMatch(
        row: row,
        kind: PlanviewMatchKind.renumber,
        existing: hit,
        newRefForExisting: 'R$maxRef',
      ));
    }
  }
  return out;
}
