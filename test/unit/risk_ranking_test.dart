import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/status/risk_ranking.dart';
import 'package:keel/core/status/status_snapshot_decoder.dart';

Risk _r(
  String ref, {
  String likelihood = 'likely',
  String impact = 'major',
  bool steerco = false,
  String? dueDate,
  String? nextReview,
  String status = 'open',
  String? title,
  String? note,
  String? plan,
  DateTime? updatedAt,
}) =>
    Risk(
      id: 'id-$ref',
      projectId: 'p',
      ref: ref,
      title: title,
      description: 'Risk $ref',
      likelihood: likelihood,
      impact: impact,
      steerco: steerco,
      strategy: 'treat',
      dueDate: dueDate,
      nextReviewAt: nextReview,
      statusNote: note,
      mitigation: plan,
      status: status,
      source: 'manual',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: updatedAt ?? DateTime(2026, 9, 25, 11),
    );

void main() {
  final today = DateTime(2026, 9, 25);

  test('the TAC tie: six Likely/Major risks written in the same second '
      'rank by SteerCo, due date, review, then ref — not by accident', () {
    final all = [
      _r('R13', steerco: true),
      _r('R12'),
      _r('R23', steerco: true, dueDate: '2026-11-30'),
      _r('R28', steerco: true, dueDate: '2026-12-31'),
      _r('R31', steerco: true, dueDate: '2026-10-31'),
      _r('R21', dueDate: '2027-01-31'),
      _r('R22', impact: 'moderate'),
      _r('R19', likelihood: 'possible', steerco: true, dueDate: '2026-09-30'),
    ];
    final ranked = rankRisks(all, today: today).map((r) => r.ref).toList();
    // Score 16 block first. SteerCo before programme; within SteerCo the
    // soonest due date first, undated (R13) last; then programme-level
    // by due date (R21) then undated (R12). Then the 12s: R22 (likely/
    // moderate) and R19 (possible/major) tie on score; R19 is SteerCo.
    expect(ranked,
        ['R31', 'R23', 'R28', 'R13', 'R21', 'R12', 'R19', 'R22']);
  });

  test('overdue treatment dates rank before future ones', () {
    final ranked = rankRisks([
      _r('R2', dueDate: '2026-10-15'),
      _r('R1', dueDate: '2026-09-01'), // overdue
      _r('R3'),
    ], today: today);
    expect(ranked.map((r) => r.ref), ['R1', 'R2', 'R3']);
  });

  test('review overdue breaks a tie before ref', () {
    final ranked = rankRisks([
      _r('R1'),
      _r('R2', nextReview: '2026-09-20'),
    ], today: today);
    expect(ranked.map((r) => r.ref), ['R2', 'R1']);
  });

  test('in-progress risks stay in; closed and accepted drop out', () {
    final ranked = rankRisks([
      _r('R1', status: 'closed'),
      _r('R2', status: 'in progress'),
      _r('R3', status: 'accepted'),
      _r('R4', status: 'open', likelihood: 'rare', impact: 'minimal'),
    ], today: today);
    expect(ranked.map((r) => r.ref), ['R2', 'R4']);
  });

  test('score always wins over SteerCo', () {
    final ranked = rankRisks([
      _r('R1', steerco: true, likelihood: 'possible', impact: 'moderate'),
      _r('R2', likelihood: 'almost certain', impact: 'severe'),
    ], today: today);
    expect(ranked.first.ref, 'R2');
  });

  test('topRisks takes the first N and is deterministic', () {
    final all = [for (var i = 1; i <= 8; i++) _r('R$i')];
    final a = topRisks(all, limit: 5, today: today).map((r) => r.ref).toList();
    final b = topRisks(all.reversed, limit: 5, today: today)
        .map((r) => r.ref)
        .toList();
    expect(a, ['R1', 'R2', 'R3', 'R4', 'R5']);
    expect(b, a);
  });

  group('change since last snapshot', () {
    SnapshotRisk snap(String ref, String l, String i) => SnapshotRisk(
        id: 'id-$ref', ref: ref, description: 'd', likelihood: l, impact: i);

    test('no previous snapshot → no markers at all', () {
      expect(riskChangeSince(_r('R1'), null), isNull);
      expect(riskChangeLabel(null, _r('R1'), null), isNull);
    });

    test('new, up, down, unchanged', () {
      final prev = {
        'id-R1': snap('R1', 'possible', 'moderate'),
        'id-R2': snap('R2', 'likely', 'major'),
        'id-R3': snap('R3', 'almost certain', 'severe'),
      };
      expect(riskChangeSince(_r('R9'), prev), RiskChange.newEntry);
      expect(riskChangeSince(_r('R1'), prev), RiskChange.up);
      expect(riskChangeSince(_r('R2'), prev), RiskChange.unchanged);
      expect(riskChangeSince(_r('R3'), prev), RiskChange.down);
      expect(riskChangeLabel(RiskChange.newEntry, _r('R9'), prev),
          'NEW to top risks');
      expect(riskChangeLabel(RiskChange.up, _r('R1'), prev),
          '▲ was Possible / Moderate (9)');
      expect(riskChangeLabel(RiskChange.down, _r('R3'), prev),
          '▼ was Almost certain / Severe (25)');
      expect(riskChangeLabel(RiskChange.unchanged, _r('R2'), prev), isNull);
    });

    test('legacy snapshot words still compare', () {
      final prev = {'id-R1': snap('R1', 'high', 'high')}; // = likely/major
      expect(riskChangeSince(_r('R1'), prev), RiskChange.unchanged);
    });
  });

  group('riskSoWhat', () {
    test('status note wins, else first treatment line without the dash', () {
      expect(riskSoWhat(_r('R1', note: 'Awaiting AWS date.', plan: '- x')),
          'Awaiting AWS date.');
      expect(riskSoWhat(_r('R1', plan: '- Weekly vendor checkpoint\n- Stub')),
          'Weekly vendor checkpoint');
      expect(riskSoWhat(_r('R1')), isNull);
    });
  });
}
