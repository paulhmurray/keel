/// Resolves register codes mentioned in a status narrative (R12, DC14,
/// I3, D5, A2, AC7) to plain-language entries, so a reader with no
/// access to Keel's registers still knows what each one is. Pure.
library;

import '../database/database.dart';
import '../raid/risk_rating.dart';

class ReferencedItem {
  final String ref;
  final String kind; // Risk | Assumption | Issue | Dependency | Decision | Action
  final String headline; // the item in plain words
  final String detail; // status · owner · due — whatever exists
  const ReferencedItem({
    required this.ref,
    required this.kind,
    required this.headline,
    required this.detail,
  });
}

/// Longest prefixes first so "DC14" is a decision, not dependency "D" +
/// stray "C14"; "AC7" is an action, not assumption "A".
final RegExp kRefPattern = RegExp(r'\b(DC|AC|R|A|I|D)(\d{1,4})\b');

/// Every code mentioned, in order of first appearance, de-duplicated.
List<String> extractRefs(String? narrative) {
  if (narrative == null) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final m in kRefPattern.allMatches(narrative)) {
    final ref = '${m.group(1)}${m.group(2)}';
    if (seen.add(ref)) out.add(ref);
  }
  return out;
}

String _join(List<String?> parts) =>
    parts.where((p) => p != null && p.trim().isNotEmpty).join(' · ');

String _short(String s, [int max = 160]) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length <= max ? t : '${t.substring(0, max - 1)}…';
}

/// Resolves the codes in [narrative] against the project's registers.
/// Codes that match nothing are dropped — the narrative may say "R&D".
List<ReferencedItem> resolveNarrativeRefs(
  String? narrative, {
  required List<Risk> risks,
  required List<Assumption> assumptions,
  required List<Issue> issues,
  required List<ProgramDependency> dependencies,
  required List<Decision> decisions,
  required List<ProjectAction> actions,
}) {
  final refs = extractRefs(narrative);
  if (refs.isEmpty) return const [];
  final byRef = <String, ReferencedItem>{};

  for (final r in risks) {
    if (r.ref == null) continue;
    byRef[r.ref!] = ReferencedItem(
      ref: r.ref!,
      kind: 'Risk',
      headline: _short(r.title?.trim().isNotEmpty == true
          ? '${r.title}. ${r.description}'
          : r.description),
      detail: _join([
        ratingSummary(r.likelihood, r.impact),
        r.status,
        if (r.owner != null) 'owner ${r.owner}',
        if (r.dueDate != null) 'treatment due ${r.dueDate}',
      ]),
    );
  }
  for (final a in assumptions) {
    if (a.ref == null) continue;
    byRef[a.ref!] = ReferencedItem(
      ref: a.ref!,
      kind: 'Assumption',
      headline: _short(a.description),
      detail: _join([a.status, if (a.owner != null) 'owner ${a.owner}']),
    );
  }
  for (final i in issues) {
    if (i.ref == null) continue;
    byRef[i.ref!] = ReferencedItem(
      ref: i.ref!,
      kind: 'Issue',
      headline: _short(i.title?.trim().isNotEmpty == true
          ? '${i.title}. ${i.description}'
          : i.description),
      detail: _join([
        '${i.priority} priority',
        i.status,
        if (i.owner != null) 'owner ${i.owner}',
        if (i.dueDate != null) 'due ${i.dueDate}',
      ]),
    );
  }
  for (final d in dependencies) {
    if (d.ref == null) continue;
    byRef[d.ref!] = ReferencedItem(
      ref: d.ref!,
      kind: 'Dependency',
      headline: _short(d.description),
      detail: _join([
        d.dependencyType,
        if (d.counterparty != null) 'on ${d.counterparty}',
        d.status,
        if (d.dueDate != null) 'needed by ${d.dueDate}',
      ]),
    );
  }
  for (final d in decisions) {
    if (d.ref == null) continue;
    byRef[d.ref!] = ReferencedItem(
      ref: d.ref!,
      kind: 'Decision',
      headline: _short(d.description),
      detail: _join([
        d.status,
        if (d.decisionMaker != null) 'decision maker ${d.decisionMaker}',
        if (d.dueDate != null) 'needed by ${d.dueDate}',
        if (d.outcome != null && d.outcome!.trim().isNotEmpty)
          'outcome: ${_short(d.outcome!, 80)}',
      ]),
    );
  }
  for (final a in actions) {
    if (a.ref == null) continue;
    byRef[a.ref!] = ReferencedItem(
      ref: a.ref!,
      kind: 'Action',
      headline: _short(a.description),
      detail: _join([
        a.status,
        if (a.owner != null) 'owner ${a.owner}',
        if (a.dueDate != null) 'due ${a.dueDate}',
      ]),
    );
  }

  return [
    for (final ref in refs)
      if (byRef.containsKey(ref)) byRef[ref]!,
  ];
}

/// Convenience: resolve against everything the project holds.
Future<List<ReferencedItem>> resolveNarrativeRefsFromDb(
    AppDatabase db, String projectId, String? narrative) async {
  if (extractRefs(narrative).isEmpty) return const [];
  return resolveNarrativeRefs(
    narrative,
    risks: await db.raidDao.getRisksForProject(projectId),
    assumptions: await db.raidDao.getAssumptionsForProject(projectId),
    issues: await db.raidDao.getIssuesForProject(projectId),
    dependencies: await db.raidDao.getDependenciesForProject(projectId),
    decisions: await db.decisionsDao.getDecisionsForProject(projectId),
    actions: await db.actionsDao.getActionsForProject(projectId),
  );
}
