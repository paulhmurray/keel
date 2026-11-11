import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/raid/risk_review.dart';

void main() {
  final t0 = DateTime(2026, 9, 1);
  final today = DateTime(2026, 10, 26);
  Risk risk(String ref, {String? review, String likelihood = 'possible',
      String impact = 'moderate', String status = 'open', String? src}) =>
      Risk(id: ref.toLowerCase(), projectId: 'p', ref: ref, description: 'Risk $ref',
          likelihood: likelihood, impact: impact, status: status, source: 'manual',
          steerco: false, strategy: 'treat', nextReviewAt: review,
          sourceProjectId: src, createdAt: t0, updatedAt: t0);

  final risks = [
    risk('R1', review: '2026-10-12'),
    risk('R2', review: '2026-09-23', likelihood: 'likely', impact: 'major'),
    risk('R3', review: '2026-11-05'),
    risk('R4'), // never scheduled
    risk('R5', review: '2026-09-23'),
    risk('R6', review: '2026-09-01', status: 'closed'),
    risk('R7', review: '2026-09-01', src: 'other'),
    risk('R8', review: '2026-10-30', likelihood: 'almost certain', impact: 'severe'),
  ];

  test('overdue scope: open native risks whose review date has passed, oldest first',
      () {
    final out = collectReviewCandidates(risks: risks, today: today, scope: ReviewScope.overdue);
    expect(out.map((r) => r.ref), ['R2', 'R5', 'R1'],
        reason: 'R2 and R5 share the oldest date; the bigger rating wins');
  });

  test('all-open scope: overdue first, then by rating, then by ref', () {
    final out = collectReviewCandidates(risks: risks, today: today, scope: ReviewScope.allOpen);
    expect(out.map((r) => r.ref), ['R2', 'R5', 'R1', 'R8', 'R3', 'R4']);
  });

  test('an accepted risk is still reviewed; a closed one is not', () {
    final out = collectReviewCandidates(risks: [
      risk('R10', review: '2026-09-15', status: 'accepted'),
      risk('R11', review: '2026-09-15', status: 'closed'),
    ], today: today, scope: ReviewScope.overdue);
    expect(out.map((r) => r.ref), ['R10']);
  });

  test('a review due today is not overdue', () {
    final out = collectReviewCandidates(
        risks: [risk('R9', review: '2026-10-26')], today: today, scope: ReviewScope.overdue);
    expect(out, isEmpty);
  });

  test('the stamp is today and a fortnight on', () {
    final s = reviewStamp(today);
    expect(s.last, '2026-10-26');
    expect(s.next, '2026-11-09');
  });
}
