import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/database/database.dart';
import 'package:keel/core/finance/contingency_ledger.dart';

void main() {
  final t0 = DateTime(2026, 9, 1);
  FundingApproval fund(String id, int minor, {String on = '2026-07-01', String cur = 'AUD'}) =>
      FundingApproval(id: id, projectId: 'prog', name: id, amountMinor: minor,
          currency: cur, approvedOn: on, createdAt: t0, updatedAt: t0);
  ContingencyMovement mv(String id, String kind, int minor, String to,
          {String on = '2026-08-01', String? decision}) =>
      ContingencyMovement(id: id, projectId: 'prog', kind: kind, amountMinor: minor,
          linkedProjectId: to, decisionId: decision, movedOn: on, createdAt: t0);

  test('balance is funding minus allocations; draws and returns net per project', () {
    final l = computeLedger(
      approvals: [fund('bc', 1000000), fund('topup', 200000, on: '2026-09-01')],
      movements: [
        mv('a1', kMovementAllocate, 600000, 'tac', on: '2026-07-15'),
        mv('a2', kMovementAllocate, 300000, 'claims', on: '2026-07-15'),
        mv('d1', kMovementDraw, 100000, 'tac', on: '2026-08-10', decision: 'dc1'),
        mv('r1', kMovementReturn, 50000, 'claims', on: '2026-08-20', decision: 'dc2'),
      ],
    );
    expect(l.fundingMinor, 1200000);
    expect(l.allocatedMinor, 950000);
    expect(l.drawnMinor, 100000);
    expect(l.returnedMinor, 50000);
    expect(l.balanceMinor, 250000);
    expect(l.balanceBp, 2083); // 250000/1200000 = 20.83%
    final tac = l.forProject('tac')!;
    expect(tac.allocatedMinor, 700000);
    expect(tac.initialMinor, 600000);
    expect(tac.drawnMinor, 100000);
    expect(tac.history.map((m) => m.id), ['a1', 'd1']);
    expect(l.forProject('claims')!.allocatedMinor, 250000);
    expect(l.currencyMismatch, isFalse);
  });

  test('threshold: below the share of funding, or over-allocated', () {
    final l = computeLedger(
      approvals: [fund('bc', 1000000)],
      movements: [mv('a', kMovementAllocate, 850000, 'tac')],
    );
    expect(l.balanceBp, 1500);
    expect(l.belowThreshold(2000), isTrue);
    expect(l.belowThreshold(1000), isFalse);
    final over = computeLedger(
        approvals: [fund('bc', 100)], movements: [mv('a', kMovementAllocate, 150, 'tac')]);
    expect(over.balanceMinor, -50);
    expect(over.belowThreshold(0), isTrue);
  });

  test('series walks the balance through dated events', () {
    final l = computeLedger(
      approvals: [fund('bc', 1000, on: '2026-01-01')],
      movements: [
        mv('a', kMovementAllocate, 400, 'tac', on: '2026-02-01'),
        mv('d', kMovementDraw, 100, 'tac', on: '2026-03-01', decision: 'x'),
        mv('r', kMovementReturn, 50, 'tac', on: '2026-03-01', decision: 'x'),
      ],
    );
    expect(l.series.map((p) => (p.date, p.balanceMinor)).toList(),
        [('2026-01-01', 1000), ('2026-02-01', 600), ('2026-03-01', 550)]);
  });

  test('mixed currencies are flagged; empty ledger is empty', () {
    final l = computeLedger(
        approvals: [fund('a', 1), fund('b', 1, cur: 'GBP')], movements: const []);
    expect(l.currencyMismatch, isTrue);
    expect(computeLedger(approvals: const [], movements: const []).isEmpty, isTrue);
  });

  test('kind helpers', () {
    expect(movementNeedsDecision(kMovementAllocate), isFalse);
    expect(movementNeedsDecision(kMovementDraw), isTrue);
    expect(movementNeedsDecision(kMovementReturn), isTrue);
    expect(movementSign(kMovementReturn), -1);
    expect(movementLabel(kMovementDraw), 'Contingency draw');
  });
}
