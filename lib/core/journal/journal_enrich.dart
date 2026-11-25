/// Completes parsed journal items before review: owners resolved to the
/// People list, loose due dates turned into real dates. What can't be
/// completed is reported by [deltaWarnings] so the review card can say so
/// before the item is created.
library;

import 'journal_due_date.dart';
import 'journal_owner_resolver.dart';
import 'journal_parser.dart';

/// Field keys that name a person, per item type.
List<String> personKeysFor(DeltaType type) => switch (type) {
  DeltaType.action ||
  DeltaType.risk ||
  DeltaType.issue ||
  DeltaType.dependency => const ['owner'],
  DeltaType.decision => const ['decisionMaker'],
  DeltaType.timelineChange => const [],
};

/// Edit-field key holding the due phrase as written, once [enrichDeltas]
/// has replaced `dueDate` with a real date. Written to the item's source
/// note on confirm so the original wording isn't lost.
const kDueAsWritten = 'dueAsWritten';

/// Resolves owners and due dates in each delta's edit fields, in place.
/// [hint] is the entry title (organisation names there break owner ties);
/// [entryDate] anchors due dates with no year.
void enrichDeltas(
  List<DetectedDelta> deltas, {
  required List<PersonRef> people,
  String myName = '',
  String hint = '',
  required DateTime entryDate,
  int fyAnchorMonth = 1,
}) {
  for (final d in deltas) {
    final f = d.editFields;
    for (final key in personKeysFor(d.type)) {
      final r = resolveOwner(f[key], people, myName: myName, hint: hint);
      if (r != null && r.isPerson) f[key] = r.name;
    }
    final due = f['dueDate'];
    if (due != null && due.trim().isNotEmpty && !isIsoDate(due)) {
      final iso = normaliseDueDate(
        due,
        ref: entryDate,
        fyAnchorMonth: fyAnchorMonth,
      );
      if (iso != null) {
        f['dueDate'] = iso;
        f[kDueAsWritten] = due.trim();
      }
    }
  }
}

/// What still needs the user before [d] is created: owners that aren't a
/// person in People, due dates that aren't dates. Live — call it on the
/// current edit fields so fixing a field clears its warning.
List<String> deltaWarnings(
  DetectedDelta d, {
  required List<PersonRef> people,
  String myName = '',
}) {
  final out = <String>[];
  final f = d.editFields;
  for (final key in personKeysFor(d.type)) {
    final raw = f[key];
    final label = key == 'owner' ? 'Owner' : 'Decision-maker';
    final r = resolveOwner(raw, people, myName: myName);
    if (r == null) {
      if (d.type == DeltaType.action) out.add('No owner');
      continue;
    }
    // Resolved, but only counts if it's the exact stored name.
    if (r.isPerson && r.name == raw!.trim()) continue;
    out.add(switch (r.kind) {
      OwnerMatch.person => '$label "$raw" — did you mean ${r.name}?',
      OwnerMatch.group => '$label "$raw" is a group — pick one lead person',
      OwnerMatch.ambiguous =>
        '$label "$raw" could be ${r.candidates.join(' or ')}',
      OwnerMatch.unknown => '$label "$raw" isn\'t in People',
    });
  }
  final due = f['dueDate'];
  if (due != null && due.trim().isNotEmpty && !isIsoDate(due)) {
    out.add('Due "$due" isn\'t a date');
  } else if (d.type == DeltaType.action &&
      (due == null || due.trim().isEmpty)) {
    out.add('No due date');
  }
  return out;
}
