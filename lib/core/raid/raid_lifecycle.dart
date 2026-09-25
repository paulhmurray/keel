/// Closure rules for the RAID registers and Decisions.
///
/// Closed items are never deleted — they are the audit trail — so the
/// registers *age them out* instead: an item in a terminal state drops
/// from the default view two weeks after it got there and comes back
/// with the "show closed" toggle. Everything here is pure Dart so the
/// rules are unit-tested once and shared by the tabs, the forms, the
/// plan-arrow sync and the exports.
library;

import '../database/database.dart';
import 'raid_conversion_service.dart' show RaidKind;

/// Decision statuses that mean the call has been made (as opposed to
/// still open or parked). Drives the decided-on date prefill and the
/// plan-arrow removal.
const Set<String> kDecisionMadeStatuses = {
  'decided', 'approved', 'rejected', 'closed'
};

/// Statuses that end an item's life in its register.
///
/// Deliberately NOT terminal: issue/dependency `resolved` (the register
/// flags "resolved-but-not-closed" as stale — it's the nudge to confirm
/// and close), risk `in progress`, decision `deferred` (parked, not
/// made).
const Map<RaidKind, Set<String>> kTerminalStatuses = {
  RaidKind.risk: {'closed', 'accepted'},
  RaidKind.assumption: {'validated', 'invalidated', 'closed'},
  RaidKind.issue: {'closed'},
  RaidKind.dependency: {'closed'},
  RaidKind.decision: kDecisionMadeStatuses,
};

/// Closed items stay in the default view this long after closing.
const int kClosedHideAfterDays = 14;

bool isTerminalStatus(RaidKind kind, String status) =>
    kTerminalStatuses[kind]!.contains(status.toLowerCase());

/// The date an item's closure clock runs from: the recorded closed-on
/// date, else the last update (rows closed before closed-on existed,
/// or closed by paths that don't stamp it — cascade, conversion).
DateTime closureClockStart({
  required String? closedAt,
  required DateTime updatedAt,
}) {
  final parsed = closedAt != null ? DateTime.tryParse(closedAt) : null;
  return parsed ?? updatedAt;
}

/// True when the item is closed and has been for longer than
/// [hideAfterDays] — i.e. the default view should hide it.
bool isAgedOut({
  required RaidKind kind,
  required String status,
  required String? closedAt,
  required DateTime updatedAt,
  DateTime? now,
  int hideAfterDays = kClosedHideAfterDays,
}) {
  if (!isTerminalStatus(kind, status)) return false;
  final start = closureClockStart(closedAt: closedAt, updatedAt: updatedAt);
  final cutoff = (now ?? DateTime.now()).subtract(Duration(days: hideAfterDays));
  return start.isBefore(cutoff);
}

/// The closed-on value to persist after a status change: stamped with
/// [today] on first entry to a terminal state, kept while it stays
/// terminal, and cleared on reopen so the clock resets next time.
String? nextClosedAt({
  required RaidKind kind,
  required String newStatus,
  required String? existing,
  DateTime? today,
}) {
  if (!isTerminalStatus(kind, newStatus)) return null;
  if (existing != null && existing.isNotEmpty) return existing;
  final d = today ?? DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Splits [items] into the ones the default view shows and the ones it
/// hides, using [status], [closedAt] and [updatedAt] accessors so the
/// same rule serves every register's row type.
({List<T> visible, List<T> hidden}) partitionAgedOut<T>(
  Iterable<T> items, {
  required RaidKind kind,
  required String Function(T) status,
  required String? Function(T) closedAt,
  required DateTime Function(T) updatedAt,
  required bool showClosed,
  DateTime? now,
}) {
  final visible = <T>[];
  final hidden = <T>[];
  for (final item in items) {
    final aged = isAgedOut(
      kind: kind,
      status: status(item),
      closedAt: closedAt(item),
      updatedAt: updatedAt(item),
      now: now,
    );
    if (aged && !showClosed) {
      hidden.add(item);
    } else {
      visible.add(item);
    }
  }
  return (visible: visible, hidden: hidden);
}

/// Splits [items] into open and closed by terminal status — the export
/// rule: open items in the body, closed ones in a trailing section.
({List<T> open, List<T> closed}) splitClosed<T>(
  Iterable<T> items, {
  required RaidKind kind,
  required String Function(T) status,
}) {
  final open = <T>[];
  final closed = <T>[];
  for (final item in items) {
    (isTerminalStatus(kind, status(item)) ? closed : open).add(item);
  }
  return (open: open, closed: closed);
}

/// One row of an export's "closed items" section, type-agnostic.
class ClosedItemRow {
  final String ref;
  final String kind;
  final String description;
  final String status;
  final String closedOn;
  final String note;

  const ClosedItemRow({
    required this.ref,
    required this.kind,
    required this.description,
    required this.status,
    required this.closedOn,
    required this.note,
  });
}

String _closedOnOf(String? closedAt, DateTime updatedAt) =>
    closedAt ?? updatedAt.toIso8601String().substring(0, 10);

/// Flattens the closed items of the four RAID registers into export
/// rows, newest closure first.
List<ClosedItemRow> closedRaidRows({
  required Iterable<Risk> risks,
  required Iterable<Assumption> assumptions,
  required Iterable<Issue> issues,
  required Iterable<ProgramDependency> dependencies,
}) {
  final rows = <ClosedItemRow>[
    for (final r in risks)
      if (isTerminalStatus(RaidKind.risk, r.status))
        ClosedItemRow(
            ref: r.ref ?? '',
            kind: 'Risk',
            description: r.description,
            status: r.status,
            closedOn: _closedOnOf(r.closedAt, r.updatedAt),
            note: r.closureNote ?? r.mitigation ?? ''),
    for (final a in assumptions)
      if (isTerminalStatus(RaidKind.assumption, a.status))
        ClosedItemRow(
            ref: a.ref ?? '',
            kind: 'Assumption',
            description: a.description,
            status: a.status,
            closedOn: _closedOnOf(a.closedAt, a.updatedAt),
            note: a.validatedBy != null ? 'Validated by ${a.validatedBy}' : ''),
    for (final i in issues)
      if (isTerminalStatus(RaidKind.issue, i.status))
        ClosedItemRow(
            ref: i.ref ?? '',
            kind: 'Issue',
            description: i.title ?? i.description,
            status: i.status,
            closedOn: _closedOnOf(i.closedAt, i.updatedAt),
            note: i.resolution ?? ''),
    for (final d in dependencies)
      if (isTerminalStatus(RaidKind.dependency, d.status))
        ClosedItemRow(
            ref: d.ref ?? '',
            kind: 'Dependency',
            description: d.description,
            status: d.status,
            closedOn: _closedOnOf(d.closedAt, d.updatedAt),
            note: d.impactStatement ?? ''),
  ]..sort((a, b) => b.closedOn.compareTo(a.closedOn));
  return rows;
}
