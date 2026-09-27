/// One ranking for "top risks", shared by the Status page, the side
/// panel, the weekly snapshot and the exports, so they never disagree.
///
/// The report goes to the business owner, who has to be able to see WHY
/// these are the top risks, so the order is deliberate and repeatable:
///   1. score (likelihood × consequence), highest first
///   2. escalated (raised for attention) before not
///   3. treatment due date, overdue first then soonest; undated last
///   4. review overdue before reviewed
///   5. reference number, so equal risks always land in the same order
/// Open AND in-progress risks qualify — a risk being treated is still a
/// risk. Closed and accepted ones are out.
library;

import '../database/database.dart';
import '../raid/raid_conversion_service.dart' show RaidKind;
import '../raid/raid_lifecycle.dart';
import '../raid/risk_rating.dart';
import 'status_snapshot_decoder.dart' show SnapshotRisk;

List<Risk> rankRisks(Iterable<Risk> all, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final todayIso = '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  int refNumber(Risk r) =>
      int.tryParse((r.ref ?? '').replaceFirst(RegExp(r'^[A-Za-z]+'), '')) ??
      1 << 30;

  // Overdue due dates sort before future ones; both before "no date".
  String dueKey(Risk r) {
    final d = r.dueDate;
    if (d == null || d.isEmpty) return '2~'; // after every real date
    return d.compareTo(todayIso) < 0 ? '0$d' : '1$d';
  }

  final live = all
      .where((r) => !isTerminalStatus(RaidKind.risk, r.status))
      .toList();
  live.sort((a, b) {
    final s = riskScore(b.likelihood, b.impact) -
        riskScore(a.likelihood, a.impact);
    if (s != 0) return s;
    if (a.steerco != b.steerco) return a.steerco ? -1 : 1;
    final d = dueKey(a).compareTo(dueKey(b));
    if (d != 0) return d;
    final ra = reviewOverdue(a.nextReviewAt, now);
    final rb = reviewOverdue(b.nextReviewAt, now);
    if (ra != rb) return ra ? -1 : 1;
    return refNumber(a).compareTo(refNumber(b));
  });
  return live;
}

List<Risk> topRisks(Iterable<Risk> all, {int limit = 5, DateTime? today}) =>
    rankRisks(all, today: today).take(limit).toList();

/// How a risk compares with the last report's top list.
enum RiskChange { newEntry, up, down, unchanged }

/// Compares [risk] against the previous snapshot's frozen top risks
/// (keyed by risk id). Null when there is no previous snapshot at all,
/// so a first report doesn't mark everything "new".
RiskChange? riskChangeSince(Risk risk, Map<String, SnapshotRisk>? previous) {
  if (previous == null) return null;
  final prev = previous[risk.id];
  if (prev == null) return RiskChange.newEntry;
  final before = riskScore(prev.likelihood, prev.impact);
  final now = riskScore(risk.likelihood, risk.impact);
  if (now > before) return RiskChange.up;
  if (now < before) return RiskChange.down;
  return RiskChange.unchanged;
}

/// Short label for the change marker, or null when nothing to say.
String? riskChangeLabel(RiskChange? change, Risk risk,
    Map<String, SnapshotRisk>? previous) {
  switch (change) {
    case null:
    case RiskChange.unchanged:
      return null;
    case RiskChange.newEntry:
      return 'NEW to top risks';
    case RiskChange.up:
    case RiskChange.down:
      final prev = previous![risk.id]!;
      final arrow = change == RiskChange.up ? '▲' : '▼';
      return '$arrow was ${likelihoodLabel(prev.likelihood)} / '
          '${consequenceLabel(prev.impact)} '
          '(${riskScore(prev.likelihood, prev.impact)})';
  }
}

/// The one-line "so what" for a risk row: the latest status note if the
/// PM wrote one, else the first line of the treatment plan.
String? riskSoWhat(Risk r) {
  final note = r.statusNote?.trim();
  if (note != null && note.isNotEmpty) return note;
  final plan = r.mitigation?.trim();
  if (plan == null || plan.isEmpty) return null;
  final first = plan.split('\n').first.trim();
  return first.startsWith('- ') ? first.substring(2) : first;
}
