/// "Find duplicates": the pure half of the duplicate checker. Gathers the
/// open, native items of the four registers, builds the one prompt that
/// asks the model for groups of entries that say the same thing in
/// different words (within a register or across them), validates what
/// comes back against the real items, and phrases the notes a merge
/// leaves behind. The dialog owns the LLM call and the merge service
/// owns the writes.
library;

import 'dart:convert';

import '../database/database.dart';
import '../llm/raid_assist_prompts.dart' show RaidAssistPrompt;
import 'raid_conversion_service.dart' show RaidKind, RaidKindExt;
import 'raid_lifecycle.dart';
import 'raid_statements.dart';
import 'risk_rating.dart';

/// One register item as the checker sees it: enough to show on a card
/// and to describe to the model, nothing more.
class DuplicateItem {
  final RaidKind kind;
  final String id;
  final String? ref;
  final String? title;
  final String description;
  final String status;
  final String? owner;
  final String? dueDate;

  /// Label → value, for the strip under each member on the card.
  final List<(String, String)> context;

  const DuplicateItem({
    required this.kind,
    required this.id,
    required this.ref,
    required this.title,
    required this.description,
    required this.status,
    required this.owner,
    required this.dueDate,
    required this.context,
  });

  /// "Risk R3", or just "Risk" for an item with no ref yet.
  String get label => ref == null || ref!.isEmpty ? kind.label : '${kind.label} $ref';

  /// The headline a card leads with: the title when there is one.
  String get headline =>
      title != null && title!.trim().isNotEmpty ? title!.trim() : description;
}

/// What the model proposed and the PM reviews: two or more items that
/// describe the same thing, the register the merged entry belongs in,
/// why they match, and a merged statement to offer the survivor.
class DuplicateGroup {
  final List<DuplicateItem> members;
  final RaidKind register;
  final String reason;
  final String merged;

  const DuplicateGroup({
    required this.members,
    required this.register,
    required this.reason,
    required this.merged,
  });

  /// True when the members come from more than one register — the card
  /// then asks which one the survivor should live in.
  bool get crossesRegisters => members.map((m) => m.kind).toSet().length > 1;

  List<RaidKind> get kinds => [
        for (final k in RaidKind.values)
          if (members.any((m) => m.kind == k)) k,
      ];
}

List<(String, String)> _ctx(Map<String, String?> m) => [
      for (final e in m.entries)
        if (e.value != null && e.value!.trim().isNotEmpty)
          (e.key, e.value!.trim()),
    ];

/// Open, native items across the four registers, in register order.
/// Closed items and cascaded copies are never candidates: one is
/// history, the other is not ours to merge.
List<DuplicateItem> collectDuplicateItems({
  required List<Risk> risks,
  required List<Assumption> assumptions,
  required List<Issue> issues,
  required List<ProgramDependency> dependencies,
}) {
  final out = <DuplicateItem>[];
  for (final r in risks) {
    if (r.sourceProjectId != null || isTerminalStatus(RaidKind.risk, r.status)) {
      continue;
    }
    out.add(DuplicateItem(
      kind: RaidKind.risk,
      id: r.id,
      ref: r.ref,
      title: r.title,
      description: r.description,
      status: r.status,
      owner: r.owner,
      dueDate: r.dueDate,
      context: _ctx({
        'Likelihood': likelihoodLabel(r.likelihood),
        'Consequence': consequenceLabel(r.impact),
        'Owner': r.owner,
        'Status': r.status,
        'Treatment': r.mitigation,
        'Due': r.dueDate,
      }),
    ));
  }
  for (final a in assumptions) {
    if (a.sourceProjectId != null ||
        isTerminalStatus(RaidKind.assumption, a.status)) {
      continue;
    }
    out.add(DuplicateItem(
      kind: RaidKind.assumption,
      id: a.id,
      ref: a.ref,
      title: null,
      description: a.description,
      status: a.status,
      owner: a.owner,
      dueDate: null,
      context: _ctx({
        'Status': a.status,
        'Owner': a.owner,
        'Validated by': a.validatedBy,
      }),
    ));
  }
  for (final i in issues) {
    if (i.sourceProjectId != null || isTerminalStatus(RaidKind.issue, i.status)) {
      continue;
    }
    out.add(DuplicateItem(
      kind: RaidKind.issue,
      id: i.id,
      ref: i.ref,
      title: i.title,
      description: i.description,
      status: i.status,
      owner: i.owner,
      dueDate: i.dueDate,
      context: _ctx({
        'Priority': i.priority,
        'Status': i.status,
        'Owner': i.owner,
        'Due': i.dueDate,
        'Impact': i.impactStatement,
      }),
    ));
  }
  for (final d in dependencies) {
    if (d.sourceProjectId != null ||
        isTerminalStatus(RaidKind.dependency, d.status)) {
      continue;
    }
    out.add(DuplicateItem(
      kind: RaidKind.dependency,
      id: d.id,
      ref: d.ref,
      title: null,
      description: d.description,
      status: d.status,
      owner: d.owner,
      dueDate: d.dueDate,
      context: _ctx({
        'Direction': d.dependencyType,
        'Counterparty': d.counterparty,
        'Owner': d.owner,
        'Status': d.status,
        'Needed by': d.dueDate,
      }),
    ));
  }
  return out;
}

const String _kPersona =
    'You are reviewing a project or programme RAID register (risks, '
    'assumptions, issues, dependencies) for duplicate entries: items that '
    'describe the same underlying thing in different words. Two items are '
    'duplicates when a project manager would keep only one of them. That '
    'includes the same risk written twice, and an assumption and a '
    'dependency that are really the same promise from the same party. Items '
    'that merely share a topic, counterparty or system are NOT duplicates. '
    'Be conservative: when unsure, do not group.';

String _patternsBlock() => [
      for (final k in RaidKind.values)
        if (kRaidStatementPatterns.containsKey(k))
          '  ${k.name}: ${kRaidStatementPatterns[k]}',
    ].join('\n');

/// The one prompt for a register. Items are numbered so the answer can
/// name them without relying on refs (an item may have none yet).
RaidAssistPrompt duplicatesPrompt(
  List<DuplicateItem> items, {
  String? projectContext,
}) {
  final system = StringBuffer();
  if (projectContext != null && projectContext.trim().isNotEmpty) {
    system
      ..writeln(projectContext.trim())
      ..writeln()
      ..writeln('---')
      ..writeln();
  }
  system
    ..writeln(_kPersona)
    ..writeln()
    ..writeln('Answer with ONLY a JSON object, no prose, no markdown fence, in '
        'exactly this shape:')
    ..writeln('{"groups":[{"items":[1,4],"register":"risk","reason":"one '
        'sentence on why these are the same thing","merged":"one statement '
        'for the surviving entry"}]}')
    ..writeln('Rules: "items" are the numbers from the list, at least two per '
        'group, each number in at most one group. "register" is the register '
        'the merged entry belongs in and must be the register of one of its '
        'members (risk, assumption, issue or dependency). "merged" is ONE '
        'statement in that register\'s house shape, built only from what the '
        'members say, under 50 words, gaps marked as bracketed points to '
        'confirm. If nothing is duplicated, answer {"groups":[]}.')
    ..writeln()
    ..writeln('House shapes:')
    ..write(_patternsBlock());

  final user = StringBuffer()
    ..writeln('Open register items (${items.length}):')
    ..writeln();
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final extras = <String>[
      if (it.owner != null && it.owner!.trim().isNotEmpty) 'owner: ${it.owner!.trim()}',
      'status: ${it.status}',
      if (it.dueDate != null && it.dueDate!.isNotEmpty) 'due: ${it.dueDate}',
    ];
    user.write('[${i + 1}] ${it.label}: ');
    if (it.title != null && it.title!.trim().isNotEmpty) {
      user.write('${it.title!.trim()} — ');
    }
    user
      ..write(it.description.trim())
      ..writeln(' (${extras.join('; ')})');
  }
  return RaidAssistPrompt(system: system.toString(), user: user.toString());
}

/// Pulls the JSON object out of a model answer that may be wrapped in a
/// fence or prose. Throws [FormatException] when there is none.
Map<String, dynamic> _extractJson(String raw) {
  // A reasoning model may think aloud first; a brace in that block would
  // otherwise swallow the answer. The Ollama client already strips it,
  // but other providers and future clients may not.
  var s = raw
      .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
      .trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
      .firstMatch(s);
  if (fence != null) s = fence.group(1)!.trim();
  final start = s.indexOf('{');
  final end = s.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('No JSON object in the answer');
  }
  final decoded = jsonDecode(s.substring(start, end + 1));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Answer is not a JSON object');
  }
  return decoded;
}

/// Turns the model's answer into groups the PM can act on. Every member
/// must name a real item (by list number, or by ref as a courtesy);
/// unknown ones are dropped, an item appears in at most one group, and a
/// group needs two distinct members to survive. The register falls back
/// to the first member's when the answer names one no member has.
List<DuplicateGroup> parseDuplicateGroups(String raw, List<DuplicateItem> items) {
  final obj = _extractJson(raw);
  final rawGroups = obj['groups'];
  if (rawGroups is! List) return const [];

  final byRef = <String, DuplicateItem>{
    for (final it in items)
      if (it.ref != null && it.ref!.isNotEmpty) it.ref!.toUpperCase(): it,
  };
  DuplicateItem? resolve(Object? key) {
    if (key is int) {
      return key >= 1 && key <= items.length ? items[key - 1] : null;
    }
    if (key is String) {
      final n = int.tryParse(key.trim());
      if (n != null) return resolve(n);
      return byRef[key.trim().toUpperCase()];
    }
    return null;
  }

  final used = <String>{};
  final out = <DuplicateGroup>[];
  for (final g in rawGroups) {
    if (g is! Map) continue;
    final keys = g['items'];
    if (keys is! List) continue;
    final members = <DuplicateItem>[];
    for (final k in keys) {
      final it = resolve(k);
      if (it == null || used.contains(it.id) || members.any((m) => m.id == it.id)) {
        continue;
      }
      members.add(it);
    }
    if (members.length < 2) continue;
    used.addAll(members.map((m) => m.id));

    final regName = (g['register'] ?? '').toString().trim().toLowerCase();
    final register = members
            .map((m) => m.kind)
            .where((k) => k.name == regName || k.label.toLowerCase() == regName)
            .firstOrNull ??
        members.first.kind;

    out.add(DuplicateGroup(
      members: members,
      register: register,
      reason: (g['reason'] ?? '').toString().trim(),
      merged: (g['merged'] ?? '').toString().trim(),
    ));
  }
  return out;
}

/// Rebuilds [groups] from [current] after the register changed under
/// them (an item edited, converted or closed from inside the check).
/// Members are matched by id, so a converted item comes back in its new
/// register with its new ref; one that is now closed, or gone, drops
/// out. A group's register is kept when a member still lives there and
/// otherwise follows the first remaining member. Groups are returned in
/// place, even when fewer than two members remain, so the review keeps
/// its numbering; the caller treats a short group as resolved.
List<DuplicateGroup> refreshGroups(
  List<DuplicateGroup> groups,
  List<DuplicateItem> current,
) {
  final byId = {for (final it in current) it.id: it};
  return [
    for (final g in groups)
      () {
        final members = [
          for (final m in g.members)
            if (byId[m.id] != null) byId[m.id]!,
        ];
        final register = members.any((m) => m.kind == g.register)
            ? g.register
            : (members.firstOrNull?.kind ?? g.register);
        return DuplicateGroup(
          members: members,
          register: register,
          reason: g.reason,
          merged: g.merged,
        );
      }(),
  ];
}

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _append(String? existing, String line) {
  final cur = existing?.trim() ?? '';
  return cur.isEmpty ? line : '$cur\n$line';
}

/// The note the survivor keeps: which entries it absorbed and, when its
/// wording changed, what it used to say.
String mergeSurvivorNote({
  required String? existingSourceNote,
  required List<String> absorbedLabels,
  required String? previousDescription,
  required DateTime when,
}) {
  var line = 'Merged in ${absorbedLabels.join(', ')} ${_day(when)}.';
  if (previousDescription != null && previousDescription.trim().isNotEmpty) {
    line += ' Was: "${previousDescription.trim()}"';
  }
  return _append(existingSourceNote, line);
}

/// The note a closed duplicate keeps, so anyone who finds it later knows
/// where the live entry went.
String mergeClosedNote({
  required String? existingSourceNote,
  required String survivorLabel,
  required DateTime when,
}) =>
    _append(existingSourceNote, 'Merged into $survivorLabel ${_day(when)}.');
