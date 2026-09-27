/// "Tidy my register": the pure half of the review queue. Picks the
/// items worth rewriting, builds each item's draft prompt, and phrases
/// the history note that keeps the previous wording. The dialog owns the
/// LLM calls and the writes.
library;

import '../database/database.dart';
import '../llm/raid_assist_prompts.dart';
import '../raid/risk_rating.dart';
import 'raid_conversion_service.dart' show RaidKind;
import 'raid_lifecycle.dart';
import 'raid_statements.dart';

enum TidyScope { needsWork, allOpen }

/// One register item queued for review, with everything the card shows.
class TidyCandidate {
  final RaidKind kind;
  final String id;
  final String? ref;
  final String? title;
  final String description;
  final List<RaidQualityHint> hints;
  /// Label → value, for the context strip under the draft.
  final List<(String, String)> context;
  final RaidAssistPrompt Function(String? projectContext) prompt;

  const TidyCandidate({
    required this.kind,
    required this.id,
    required this.ref,
    required this.title,
    required this.description,
    required this.hints,
    required this.context,
    required this.prompt,
  });

  bool get needsWork => hints.any((h) => h.severity == 2);
}

String _kindLabel(RaidKind k) => switch (k) {
      RaidKind.risk => 'Risk',
      RaidKind.assumption => 'Assumption',
      RaidKind.issue => 'Issue',
      RaidKind.dependency => 'Dependency',
      RaidKind.decision => 'Decision',
    };

String kindLabelFor(RaidKind k) => _kindLabel(k);

List<(String, String)> _ctx(Map<String, String?> m) => [
      for (final e in m.entries)
        if (e.value != null && e.value!.trim().isNotEmpty) (e.key, e.value!.trim()),
    ];

/// Open, editable (non-cascaded) items across the four registers, in
/// register order, filtered by [scope]. Closed items and cascaded copies
/// are never candidates: one is history, the other is not ours.
List<TidyCandidate> collectTidyCandidates({
  required List<Risk> risks,
  required List<Assumption> assumptions,
  required List<Issue> issues,
  required List<ProgramDependency> dependencies,
  required TidyScope scope,
}) {
  final out = <TidyCandidate>[];

  for (final r in risks) {
    if (r.sourceProjectId != null || isTerminalStatus(RaidKind.risk, r.status)) {
      continue;
    }
    final hints = raidQualityHints(RaidKind.risk,
        description: r.description, title: r.title, owner: r.owner);
    out.add(TidyCandidate(
      kind: RaidKind.risk,
      id: r.id,
      ref: r.ref,
      title: r.title,
      description: r.description,
      hints: hints,
      context: _ctx({
        'Likelihood': likelihoodLabel(r.likelihood),
        'Consequence': consequenceLabel(r.impact),
        'Owner': r.owner,
        'Treatment': r.mitigation,
        'Due': r.dueDate,
      }),
      prompt: (ctx) => riskAssistPrompt(
        field: RiskAssistField.description,
        description: r.title == null || r.title!.trim().isEmpty
            ? r.description
            : '${r.title!.trim()} — ${r.description}',
        likelihood: likelihoodLabel(r.likelihood),
        impact: consequenceLabel(r.impact),
        likelihoodRationale: r.likelihoodRationale,
        impactRationale: r.impactRationale,
        mitigation: r.mitigation,
        owner: r.owner,
        projectContext: ctx,
      ),
    ));
  }

  for (final a in assumptions) {
    if (a.sourceProjectId != null ||
        isTerminalStatus(RaidKind.assumption, a.status)) {
      continue;
    }
    final hints = raidQualityHints(RaidKind.assumption,
        description: a.description, owner: a.owner, validatedBy: a.validatedBy);
    out.add(TidyCandidate(
      kind: RaidKind.assumption,
      id: a.id,
      ref: a.ref,
      title: null,
      description: a.description,
      hints: hints,
      context: _ctx({
        'Status': a.status,
        'Owner': a.owner,
        'Validated by': a.validatedBy,
      }),
      prompt: (ctx) => assumptionAssistPrompt(
        field: AssumptionAssistField.description,
        description: a.description,
        status: a.status,
        owner: a.owner,
        validatedBy: a.validatedBy,
        projectContext: ctx,
      ),
    ));
  }

  for (final i in issues) {
    if (i.sourceProjectId != null || isTerminalStatus(RaidKind.issue, i.status)) {
      continue;
    }
    final hints = raidQualityHints(RaidKind.issue,
        description: i.description,
        title: i.title,
        owner: i.owner,
        dueDate: i.dueDate,
        impactStatement: i.impactStatement);
    out.add(TidyCandidate(
      kind: RaidKind.issue,
      id: i.id,
      ref: i.ref,
      title: i.title,
      description: i.description,
      hints: hints,
      context: _ctx({
        'Priority': i.priority,
        'Status': i.status,
        'Owner': i.owner,
        'Due': i.dueDate,
        'Impact': i.impactStatement,
        'Resolution': i.resolution,
      }),
      prompt: (ctx) => issueAssistPrompt(
        field: IssueAssistField.description,
        title: i.title,
        description: i.description,
        priority: i.priority,
        status: i.status,
        impactStatement: i.impactStatement,
        resolution: i.resolution,
        owner: i.owner,
        dueDate: i.dueDate,
        projectContext: ctx,
      ),
    ));
  }

  for (final d in dependencies) {
    if (d.sourceProjectId != null ||
        isTerminalStatus(RaidKind.dependency, d.status)) {
      continue;
    }
    final hints = raidQualityHints(RaidKind.dependency,
        description: d.description,
        owner: d.owner,
        dueDate: d.dueDate,
        counterparty: d.counterparty,
        impactStatement: d.impactStatement);
    out.add(TidyCandidate(
      kind: RaidKind.dependency,
      id: d.id,
      ref: d.ref,
      title: null,
      description: d.description,
      hints: hints,
      context: _ctx({
        'Direction': d.dependencyType,
        'Counterparty': d.counterparty,
        'Owner': d.owner,
        'Needed by': d.dueDate,
        'Why': d.rationale,
        'Impact': d.impactStatement,
      }),
      prompt: (ctx) => dependencyAssistPrompt(
        field: DependencyAssistField.description,
        description: d.description,
        dependencyType: d.dependencyType,
        counterparty: d.counterparty,
        rationale: d.rationale,
        impactStatement: d.impactStatement,
        owner: d.owner,
        dueDate: d.dueDate,
        projectContext: ctx,
      ),
    ));
  }

  return scope == TidyScope.allOpen
      ? out
      : out.where((c) => c.needsWork).toList();
}

/// The note that keeps the previous wording once a rewrite is accepted.
/// Appended to the item's source note so the original stays visible in
/// the detail view and can be restored by hand.
String tidyHistoryNote({
  required String? existingSourceNote,
  required String previousDescription,
  required DateTime when,
}) {
  final date = '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';
  final line = 'Reworded $date. Was: "${previousDescription.trim()}"';
  final cur = existingSourceNote?.trim() ?? '';
  return cur.isEmpty ? line : '$cur\n$line';
}

/// Outcome of a review pass, for the closing summary.
class TidySummary {
  final int accepted;
  final int skipped;
  final int failed;
  const TidySummary({required this.accepted, required this.skipped, required this.failed});
}
