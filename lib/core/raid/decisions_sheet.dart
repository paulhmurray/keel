/// The "Open decisions" block of the plan workbook's "Actions & Decisions"
/// sheet: parsing, matching against Keel's decision register, and the
/// write. Pure Dart apart from the final apply.
library;

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../journal/journal_match.dart' show distinctiveWords;
import 'planview_risk_sheet.dart' show parsePlanviewDate;

class SheetDecisionRow {
  /// The sheet's own reference, e.g. "DEC3" — kept in the source note;
  /// Keel numbers decisions DC<n>.
  final String sheetRef;
  final String description;
  final String? decisionMaker;
  final String? neededBy; // ISO or null
  final String status; // Keel vocabulary
  final String? context;

  const SheetDecisionRow({
    required this.sheetRef,
    required this.description,
    this.decisionMaker,
    this.neededBy,
    required this.status,
    this.context,
  });

  /// Parses one row of the block (columns: #, DECISION, DECISION-MAKER,
  /// NEEDED BY, STATUS, CONTEXT). Null unless column A is a DEC-ref.
  static SheetDecisionRow? fromCells(List<String?> cells) {
    String? at(int i) {
      if (i >= cells.length) return null;
      final v = cells[i]?.trim();
      return v == null || v.isEmpty || v == '—' ? null : v;
    }

    final ref = at(0);
    if (ref == null || !RegExp(r'^DEC\d+$', caseSensitive: false).hasMatch(ref)) {
      return null;
    }
    final desc = at(1);
    if (desc == null) return null;
    return SheetDecisionRow(
      sheetRef: ref.toUpperCase(),
      description: desc,
      decisionMaker: at(2),
      neededBy: parseNeededBy(at(3)),
      status: normaliseDecisionStatus(at(4)),
      context: at(5),
    );
  }
}

/// "Open" → pending; the register's own words pass through.
String normaliseDecisionStatus(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  return switch (v) {
    '' || 'open' || 'pending' => 'pending',
    'decided' || 'made' || 'agreed' => 'decided',
    'approved' => 'approved',
    'rejected' => 'rejected',
    'deferred' || 'parked' => 'deferred',
    'closed' => 'closed',
    _ => 'pending',
  };
}

const _kMonths = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// "Nov 26" → the last day of that month; "18 Sep 26" and ISO pass to
/// the Planview date parser; prose ("Kick-off (Oct 26)") takes the month
/// it names; otherwise null.
String? parseNeededBy(String? raw) {
  if (raw == null) return null;
  final exact = parsePlanviewDate(raw);
  if (exact != null) return exact;
  final m = RegExp(r'([A-Za-z]{3,4})\.?\s+(\d{2}|\d{4})\b').firstMatch(raw);
  if (m == null) return null;
  final month = _kMonths[m.group(1)!.toLowerCase()];
  if (month == null) return null;
  var year = int.parse(m.group(2)!);
  if (year < 100) year += 2000;
  final last = DateTime(year, month + 1, 0).day;
  return '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${last.toString().padLeft(2, '0')}';
}

enum DecisionMatchKind { update, create }

class DecisionMatch {
  final SheetDecisionRow row;
  final DecisionMatchKind kind;
  final Decision? existing;
  const DecisionMatch({required this.row, required this.kind, this.existing});
}

/// Word overlap (share of the shorter side) above which a sheet decision
/// is taken to be an existing Keel decision reworded.
const double kSameDecisionThreshold = 0.34;

/// A weaker overlap still counts when the two name the same decision
/// maker — a journal-captured "where are payments coming from" and the
/// register's "where payments originate during transition" share few
/// words but the same owner and the same subject.
const double kSameDecisionWithMakerThreshold = 0.15;

bool _sameMaker(String? a, String? b) {
  if (a == null || b == null) return false;
  final wa = distinctiveWords(a);
  final wb = distinctiveWords(b);
  return wa.isNotEmpty && wa.intersection(wb).isNotEmpty;
}

/// Decides update-vs-create for each sheet row. A Keel decision is
/// matched at most once; the best-overlapping sheet row wins it.
List<DecisionMatch> planDecisionsImport(
    List<SheetDecisionRow> rows, List<Decision> existing) {
  final scored = <(int rowIdx, Decision d, double score)>[];
  for (var i = 0; i < rows.length; i++) {
    final want = distinctiveWords(rows[i].description);
    for (final d in existing) {
      final have = distinctiveWords(d.description);
      final shorter = want.length < have.length ? want.length : have.length;
      if (shorter == 0) continue;
      final score = want.intersection(have).length / shorter;
      final threshold = _sameMaker(rows[i].decisionMaker, d.decisionMaker)
          ? kSameDecisionWithMakerThreshold
          : kSameDecisionThreshold;
      if (score >= threshold) scored.add((i, d, score));
    }
  }
  scored.sort((a, b) => b.$3.compareTo(a.$3));
  final matchedRows = <int, Decision>{};
  final usedDecisions = <String>{};
  for (final s in scored) {
    if (matchedRows.containsKey(s.$1) || usedDecisions.contains(s.$2.id)) {
      continue;
    }
    matchedRows[s.$1] = s.$2;
    usedDecisions.add(s.$2.id);
  }
  return [
    for (var i = 0; i < rows.length; i++)
      matchedRows.containsKey(i)
          ? DecisionMatch(
              row: rows[i],
              kind: DecisionMatchKind.update,
              existing: matchedRows[i])
          : DecisionMatch(row: rows[i], kind: DecisionMatchKind.create),
  ];
}

String nextDecisionRef(Iterable<Decision> existing) {
  final nums = existing
      .where((d) => d.ref != null && d.ref!.startsWith('DC'))
      .map((d) => int.tryParse(d.ref!.substring(2)) ?? 0)
      .toList()
    ..sort();
  return 'DC${(nums.isEmpty ? 0 : nums.last) + 1}';
}

class DecisionsImportResult {
  final int updated;
  final int created;
  const DecisionsImportResult({required this.updated, required this.created});
}

/// Writes the plan. Sheet fields overwrite description, decision maker,
/// needed-by, status and impact (from CONTEXT); rationale, outcome, plan
/// link and options are kept from an existing row.
Future<DecisionsImportResult> applyDecisionsImport(
  AppDatabase db, {
  required String projectId,
  required List<DecisionMatch> plan,
  DateTime? now,
}) async {
  final stamp = now ?? DateTime.now();
  final stampIso = stamp.toIso8601String().substring(0, 10);
  var updated = 0, created = 0;
  await db.transaction(() async {
    var existing = await db.decisionsDao.getDecisionsForProject(projectId);
    for (final m in plan) {
      final target = m.existing;
      final id = target?.id ?? const Uuid().v4();
      final ref = target?.ref ?? nextDecisionRef(existing);
      final r = m.row;
      await db.decisionsDao.upsertDecision(DecisionsCompanion(
        id: Value(id),
        projectId: Value(projectId),
        ref: Value(ref),
        description: Value(r.description),
        status: Value(r.status),
        decisionMaker: Value(r.decisionMaker ?? target?.decisionMaker),
        dueDate: Value(r.neededBy ?? target?.dueDate),
        impactStatement: Value(r.context ?? target?.impactStatement),
        rationale: Value(target?.rationale),
        outcome: Value(target?.outcome),
        optionsConsidered: Value(target?.optionsConsidered),
        planActivityId: Value(target?.planActivityId),
        decidedAt: Value(r.status == 'pending' ? null : target?.decidedAt),
        source: Value(target?.source ?? 'document'),
        sourceNote: Value(
            '${r.sheetRef} in Actions & Decisions sheet · imported $stampIso'),
        escalatedAt: Value(target?.escalatedAt),
        sourceProjectId: Value(target?.sourceProjectId),
        createdAt: Value(target?.createdAt ?? stamp),
        updatedAt: Value(stamp),
      ));
      if (target != null) {
        updated++;
      } else {
        created++;
        existing = await db.decisionsDao.getDecisionsForProject(projectId);
      }
    }
  });
  return DecisionsImportResult(updated: updated, created: created);
}
