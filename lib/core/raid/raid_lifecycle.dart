/// Closure rules for the RAID registers and Decisions.
///
/// Closed items are never deleted — they are the audit trail. In the
/// four RAID registers "closed" is the one final state: the default
/// view hides closed items at once and the "show closed" toggle brings
/// them back. Settled-but-open states (an accepted risk, a resolved
/// issue, a validated assumption) stay on the books and stay
/// reviewable; one left settled for a few weeks earns a nudge to close
/// it or reopen it. Decisions keep their own rule: a made decision is
/// the record, so it ages out of the log two weeks after it was made.
/// Everything here is pure Dart so the rules are unit-tested once and
/// shared by the tabs, the forms, the plan-arrow sync and the exports.
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
/// For the RAID registers that is "closed" alone. Accepted, resolved,
/// validated and invalidated are settled, not finished: see
/// [kSettledStatuses].
const Map<RaidKind, Set<String>> kTerminalStatuses = {
  RaidKind.risk: {'closed'},
  RaidKind.assumption: {'closed'},
  RaidKind.issue: {'closed'},
  RaidKind.dependency: {'closed'},
  RaidKind.decision: kDecisionMadeStatuses,
};

/// Statuses that mean the item is dealt with but still on the books: a
/// risk we have chosen to carry, an issue whose fix is in but not yet
/// confirmed, an assumption that has been tested. They stay visible and
/// stay reviewable, and after [kSettledNudgeDays] the register asks
/// whether it is time to close.
const Map<RaidKind, Set<String>> kSettledStatuses = {
  RaidKind.risk: {'accepted'},
  RaidKind.assumption: {'validated', 'invalidated'},
  RaidKind.issue: {'resolved'},
  RaidKind.dependency: {'resolved'},
  RaidKind.decision: {},
};

/// How long an item may sit settled before the register nudges.
const int kSettledNudgeDays = 21;

/// Made decisions stay in the default view this long after being made.
const int kClosedHideAfterDays = 14;

bool isTerminalStatus(RaidKind kind, String status) =>
    kTerminalStatuses[kind]!.contains(status.toLowerCase());

bool isSettledStatus(RaidKind kind, String status) =>
    kSettledStatuses[kind]!.contains(status.toLowerCase());

/// True for an item that is neither closed nor settled: still being
/// worked. Plan gaps and the status page's risk ranking use this, since
/// an accepted risk is a decision already made, not a gap.
bool isActiveStatus(RaidKind kind, String status) =>
    !isTerminalStatus(kind, status) && !isSettledStatus(kind, status);

/// Days a terminal item stays in the default view: none for the RAID
/// registers, two weeks for decisions.
int hideAfterDaysFor(RaidKind kind) =>
    kind == RaidKind.decision ? kClosedHideAfterDays : 0;

/// The nudge for an item left settled too long, or null. [updatedAt]
/// is the last touch: settling is a status change, so it is the best
/// stand-in for when the item was settled.
String? settledNudge({
  required RaidKind kind,
  required String status,
  required DateTime updatedAt,
  DateTime? now,
  int afterDays = kSettledNudgeDays,
}) {
  if (!isSettledStatus(kind, status)) return null;
  final days = (now ?? DateTime.now()).difference(updatedAt).inDays;
  if (days < afterDays) return null;
  final weeks = days ~/ 7;
  final since = weeks >= 1 ? '${weeks}w' : '${days}d';
  final verb = status.toLowerCase();
  final ask = switch (kind) {
    RaidKind.risk => 'still carrying it? Close it or review it',
    RaidKind.assumption => 'close it, or raise what it changed',
    _ => 'confirm and close it, or reopen',
  };
  return '${verb[0].toUpperCase()}${verb.substring(1)} $since ago — $ask';
}

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

/// True when the default view should hide the item: closed, and closed
/// for longer than the register's grace ([hideAfterDaysFor]: none for
/// RAID, so a closed item hides at once; two weeks for decisions).
bool isAgedOut({
  required RaidKind kind,
  required String status,
  required String? closedAt,
  required DateTime updatedAt,
  DateTime? now,
  int? hideAfterDays,
}) {
  if (!isTerminalStatus(kind, status)) return false;
  final days = hideAfterDays ?? hideAfterDaysFor(kind);
  if (days <= 0) return true;
  final start = closureClockStart(closedAt: closedAt, updatedAt: updatedAt);
  final cutoff = (now ?? DateTime.now()).subtract(Duration(days: days));
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
