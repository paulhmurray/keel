/// The programme's funding envelope and contingency ledger, derived from
/// funding approvals and movements. Pure: lists in, ints out. The
/// balance is never stored — it is always the sum of the rows.
///
///   allocation(project) = Σ allocate + Σ draw − Σ return
///   contingency balance = Σ funding − Σ allocations (unallocated funding)
library;

import '../database/database.dart';
import 'variance.dart';

const kMovementAllocate = 'allocate';
const kMovementDraw = 'draw';
const kMovementReturn = 'return';

/// Signed effect of a movement on the project's allocation.
int movementSign(String kind) => kind == kMovementReturn ? -1 : 1;

String movementLabel(String kind) => switch (kind) {
      kMovementAllocate => 'Allocation',
      kMovementDraw => 'Contingency draw',
      kMovementReturn => 'Return to contingency',
      _ => kind,
    };

/// Draws and returns move money out of or into the shared pool; they
/// need the decision that authorised them. An initial allocation is the
/// programme carving up its own envelope and may stand on the funding
/// approval alone.
bool movementNeedsDecision(String kind) => kind != kMovementAllocate;

class ProjectAllocation {
  final String linkedProjectId;
  final int allocatedMinor; // current envelope
  final int initialMinor; // Σ allocate
  final int drawnMinor; // Σ draw
  final int returnedMinor; // Σ return
  final List<ContingencyMovement> history; // oldest first
  const ProjectAllocation({
    required this.linkedProjectId,
    required this.allocatedMinor,
    required this.initialMinor,
    required this.drawnMinor,
    required this.returnedMinor,
    required this.history,
  });
}

class LedgerPoint {
  final String date; // ISO
  final int balanceMinor;
  const LedgerPoint(this.date, this.balanceMinor);
}

class ContingencyLedger {
  final String? currency;
  final int fundingMinor;
  final int allocatedMinor; // Σ over projects
  final int drawnMinor;
  final int returnedMinor;
  final int balanceMinor; // funding − allocated
  final int? balanceBp; // balance as share of funding
  final List<ProjectAllocation> projects;
  final List<LedgerPoint> series; // balance after each dated event
  final bool currencyMismatch; // approvals disagree on currency

  const ContingencyLedger({
    required this.currency,
    required this.fundingMinor,
    required this.allocatedMinor,
    required this.drawnMinor,
    required this.returnedMinor,
    required this.balanceMinor,
    required this.balanceBp,
    required this.projects,
    required this.series,
    required this.currencyMismatch,
  });

  bool get isEmpty => fundingMinor == 0 && projects.isEmpty;

  /// True when the balance has fallen below [warnBp] of funding (or
  /// below zero, which is always a warning).
  bool belowThreshold(int warnBp) =>
      balanceMinor < 0 || (balanceBp != null && balanceBp! < warnBp);

  ProjectAllocation? forProject(String id) =>
      projects.where((p) => p.linkedProjectId == id).firstOrNull;
}

ContingencyLedger computeLedger({
  required List<FundingApproval> approvals,
  required List<ContingencyMovement> movements,
}) {
  final currencies = approvals.map((a) => a.currency).toSet();
  final currency = approvals.isEmpty ? null : approvals.first.currency;
  final funding = approvals.fold<int>(0, (s, a) => s + a.amountMinor);

  final byProject = <String, List<ContingencyMovement>>{};
  for (final m in movements) {
    byProject.putIfAbsent(m.linkedProjectId, () => []).add(m);
  }
  int cmp(ContingencyMovement a, ContingencyMovement b) {
    final d = a.movedOn.compareTo(b.movedOn);
    return d != 0 ? d : a.createdAt.compareTo(b.createdAt);
  }

  final projects = <ProjectAllocation>[];
  var allocated = 0, drawn = 0, returned = 0;
  final ids = byProject.keys.toList()..sort();
  for (final id in ids) {
    final rows = byProject[id]!..sort(cmp);
    var initial = 0, d = 0, r = 0;
    for (final m in rows) {
      switch (m.kind) {
        case kMovementAllocate:
          initial += m.amountMinor;
        case kMovementDraw:
          d += m.amountMinor;
        case kMovementReturn:
          r += m.amountMinor;
      }
    }
    final alloc = initial + d - r;
    projects.add(ProjectAllocation(
      linkedProjectId: id,
      allocatedMinor: alloc,
      initialMinor: initial,
      drawnMinor: d,
      returnedMinor: r,
      history: rows,
    ));
    allocated += alloc;
    drawn += d;
    returned += r;
  }

  // Balance over time: approvals add on their approved date (or the
  // start), movements subtract/add on their date.
  final events = <(String, int)>[
    for (final a in approvals) (a.approvedOn ?? '0000-00-00', a.amountMinor),
    for (final m in movements)
      (m.movedOn, -movementSign(m.kind) * m.amountMinor),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final series = <LedgerPoint>[];
  var running = 0;
  for (final (date, delta) in events) {
    running += delta;
    if (series.isNotEmpty && series.last.date == date) {
      series[series.length - 1] = LedgerPoint(date, running);
    } else {
      series.add(LedgerPoint(date, running));
    }
  }

  final balance = funding - allocated;
  return ContingencyLedger(
    currency: currency,
    fundingMinor: funding,
    allocatedMinor: allocated,
    drawnMinor: drawn,
    returnedMinor: returned,
    balanceMinor: balance,
    balanceBp: VarianceRow.bpOf(balance, funding),
    projects: projects,
    series: series,
    currencyMismatch: currencies.length > 1,
  );
}
