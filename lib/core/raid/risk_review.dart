/// "Review risks": the pure half of the review session. Picks the risks
/// due a look, orders them so the longest-neglected and the biggest come
/// first, and stamps the fortnightly cadence. The dialog owns the edits
/// and the writes.
library;

import '../database/database.dart';
import 'raid_conversion_service.dart' show RaidKind;
import 'raid_lifecycle.dart';
import 'risk_rating.dart';

enum ReviewScope { overdue, allOpen }

/// Open, native risks in review order: overdue first (oldest missed
/// review first), then the rest by rating, then by ref. [ReviewScope.overdue]
/// keeps only those whose next review date has passed; a risk that has
/// never been given a review date is not "overdue" and waits for
/// [ReviewScope.allOpen].
List<Risk> collectReviewCandidates({
  required List<Risk> risks,
  required DateTime today,
  required ReviewScope scope,
}) {
  final open = [
    for (final r in risks)
      if (r.sourceProjectId == null && !isTerminalStatus(RaidKind.risk, r.status))
        r,
  ];
  final picked = scope == ReviewScope.allOpen
      ? open
      : [for (final r in open) if (reviewOverdue(r.nextReviewAt, today)) r];

  int cmp(Risk a, Risk b) {
    final ao = reviewOverdue(a.nextReviewAt, today);
    final bo = reviewOverdue(b.nextReviewAt, today);
    if (ao != bo) return ao ? -1 : 1;
    if (ao && bo) {
      final d = a.nextReviewAt!.compareTo(b.nextReviewAt!);
      if (d != 0) return d;
    }
    final s = riskScore(b.likelihood, b.impact).compareTo(riskScore(a.likelihood, a.impact));
    if (s != 0) return s;
    return (a.ref ?? '').compareTo(b.ref ?? '');
  }

  return picked..sort(cmp);
}

/// The two dates a review writes: reviewed today, next one a cadence out.
({String last, String next}) reviewStamp(DateTime today) => (
      last: '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}',
      next: nextReviewFrom(today),
    );

/// Outcome of a session, for the closing summary.
class ReviewSummary {
  final int reviewed;
  final int skipped;
  const ReviewSummary({required this.reviewed, required this.skipped});
}
