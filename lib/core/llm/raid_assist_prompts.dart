/// Prompt builders for the per-field "AI draft" buttons on RAID forms.
///
/// Pure functions: they take the item's current fields plus optional
/// project context and return the system/user pair to send. Keeping the
/// wording here (not in the widgets) means the prompts are unit-testable
/// and every form asks in the same voice.
library;

import '../raid/raid_conversion_service.dart' show RaidKind;
import '../raid/raid_statements.dart';

class RaidAssistPrompt {
  final String system;
  final String user;
  const RaidAssistPrompt({required this.system, required this.user});
}

enum RiskAssistField { description, likelihoodRationale, impactRationale, mitigation }

enum IssueAssistField { description, impactStatement, resolution }

enum DependencyAssistField { description, rationale, impactStatement }

enum AssumptionAssistField { description }

/// The instruction for rewriting a description into the house pattern.
/// Shared so every kind asks in the same way: one statement, in the
/// shape, from the material given, gaps marked rather than invented.
String _describeInstruction(RaidKind kind, {String? extra}) =>
    'Rewrite the description as ONE statement in exactly this shape:\n'
    '  ${kRaidStatementPatterns[kind]}\n'
    '${kRaidStatementWhy[kind]} Use only what the fields above give you; '
    'where a part is genuinely unknown, write it as a bracketed point to '
    'confirm, e.g. "[impact to confirm]". Keep it under 50 words, plain '
    'English, no heading.${extra == null ? '' : ' $extra'}';

enum DecisionAssistField { rationale, optionsConsidered, impactStatement }

const String _kPersona =
    'You are helping a project or programme manager write one field of a RAID '
    'register entry. Write in plain, direct English suitable for a '
    'steering committee. Output ONLY the text for the field: no heading, '
    'no preamble, no markdown emphasis. Never invent facts (dates, names, '
    'figures, systems) that are not in the context you were given; where '
    'something is unknown, phrase it as a point to confirm.';

String _system(String? projectContext) => projectContext == null ||
        projectContext.trim().isEmpty
    ? _kPersona
    : '$projectContext\n\n---\n\n$_kPersona';

String _field(String label, String? value) =>
    value == null || value.trim().isEmpty ? '' : '$label: ${value.trim()}\n';

/// Builds the prompt for one field of a risk.
RaidAssistPrompt riskAssistPrompt({
  required RiskAssistField field,
  required String description,
  required String likelihood,
  required String impact,
  String? likelihoodRationale,
  String? impactRationale,
  String? mitigation,
  String? owner,
  String? projectContext,
}) {
  final sb = StringBuffer();
  sb.writeln('RISK');
  sb.write(_field('Description', description));
  sb.writeln('Likelihood rating: $likelihood');
  sb.writeln('Impact rating: $impact');
  sb.write(_field('Owner', owner));
  if (field != RiskAssistField.likelihoodRationale) {
    sb.write(_field('Why this likelihood (existing)', likelihoodRationale));
  }
  if (field != RiskAssistField.impactRationale) {
    sb.write(_field('Why this impact (existing)', impactRationale));
  }
  if (field != RiskAssistField.mitigation) {
    sb.write(_field('Mitigation (existing)', mitigation));
  }
  if (field == RiskAssistField.description) {
    sb.write(_field('Description (existing, to rewrite)', description));
  }
  sb.writeln();
  switch (field) {
    case RiskAssistField.description:
      sb.writeln(_describeInstruction(RaidKind.risk,
          extra: 'The event must be uncertain ("may occur"), not something '
              'that has already happened.'));
    case RiskAssistField.likelihoodRationale:
      sb.writeln(
          'Write the "Why this likelihood?" rationale: 2-3 sentences '
          'explaining what makes a $likelihood likelihood the right '
          'call — the drivers, evidence or precedent behind it, and what '
          'would move the rating up or down.');
    case RiskAssistField.impactRationale:
      sb.writeln(
          'Write the "Why this impact?" rationale: 2-3 sentences '
          'explaining why the impact is rated $impact — which of '
          'schedule, cost, scope, quality or reputation is hit, how '
          'badly, and what would change the rating.');
    case RiskAssistField.mitigation:
      sb.writeln(
          'Write a mitigation plan as 3-5 short bullet points, each on '
          'its own line starting with "- " and a verb. Cover reducing '
          'the likelihood, reducing the impact if it lands, and an early '
          'warning trigger to watch. Keep each bullet under 25 words.');
  }
  return RaidAssistPrompt(
      system: _system(projectContext), user: sb.toString());
}

/// Builds the prompt for one field of an assumption.
RaidAssistPrompt assumptionAssistPrompt({
  required AssumptionAssistField field,
  required String description,
  required String status,
  String? owner,
  String? validatedBy,
  String? projectContext,
}) {
  final sb = StringBuffer();
  sb.writeln('ASSUMPTION');
  sb.write(_field('Description (existing, to rewrite)', description));
  sb.writeln('Status: $status');
  sb.write(_field('Owner', owner));
  sb.write(_field('Validated by', validatedBy));
  sb.writeln();
  switch (field) {
    case AssumptionAssistField.description:
      sb.writeln(_describeInstruction(RaidKind.assumption,
          extra: 'Make the validation concrete: who checks it, how, and '
              'by when — a date or a named milestone.'));
  }
  return RaidAssistPrompt(
      system: _system(projectContext), user: sb.toString());
}

/// Builds the prompt for one field of an issue.
RaidAssistPrompt issueAssistPrompt({
  required IssueAssistField field,
  String? title,
  required String description,
  required String priority,
  required String status,
  String? impactStatement,
  String? resolution,
  String? owner,
  String? dueDate,
  String? projectContext,
}) {
  final sb = StringBuffer();
  sb.writeln('ISSUE');
  sb.write(_field('Title', title));
  sb.write(_field('Description', description));
  sb.writeln('Priority: $priority');
  sb.writeln('Status: $status');
  sb.write(_field('Owner', owner));
  sb.write(_field('Due', dueDate));
  if (field != IssueAssistField.impactStatement) {
    sb.write(_field('Impact statement (existing)', impactStatement));
  }
  if (field != IssueAssistField.resolution) {
    sb.write(_field('Resolution (existing)', resolution));
  }
  sb.writeln();
  switch (field) {
    case IssueAssistField.description:
      sb.writeln(_describeInstruction(RaidKind.issue,
          extra: 'Present tense — it has happened. No "may" or "could".'));
    case IssueAssistField.impactStatement:
      sb.writeln(
          'Write the impact statement: 2-3 sentences on what happens to '
          'the project if this issue is not resolved — name the '
          'schedule, cost, scope, quality or stakeholder consequence, '
          'and by when it starts to bite.');
    case IssueAssistField.resolution:
      sb.writeln(
          'Write a proposed resolution as 3-5 short bullet points, each '
          'on its own line starting with "- " and a verb: the concrete '
          'steps to close this issue, who needs to be involved (by role '
          'if unknown), and how we will know it is resolved. Keep each '
          'bullet under 25 words.');
  }
  return RaidAssistPrompt(
      system: _system(projectContext), user: sb.toString());
}

/// Builds the prompt for one field of a dependency.
RaidAssistPrompt dependencyAssistPrompt({
  required DependencyAssistField field,
  required String description,
  required String dependencyType,
  String? counterparty,
  String? rationale,
  String? impactStatement,
  String? owner,
  String? dueDate,
  String? linkedActivity,
  String? projectContext,
}) {
  final sb = StringBuffer();
  sb.writeln('DEPENDENCY');
  sb.write(_field('Description', description));
  sb.writeln('Direction: $dependencyType');
  sb.write(_field('Counterparty (who we depend on)', counterparty));
  sb.write(_field('Owner on our side', owner));
  sb.write(_field('Needed by', dueDate));
  sb.write(_field('Plan activity it gates', linkedActivity));
  if (field != DependencyAssistField.rationale) {
    sb.write(_field('Why it is a dependency (existing)', rationale));
  }
  if (field != DependencyAssistField.impactStatement) {
    sb.write(_field('Impact (existing)', impactStatement));
  }
  sb.writeln();
  switch (field) {
    case DependencyAssistField.description:
      sb.writeln(_describeInstruction(RaidKind.dependency,
          extra: 'Respect the direction: inbound = they deliver to us, '
              'outbound = we deliver to them, bilateral = both.'));
    case DependencyAssistField.rationale:
      sb.writeln(
          'Write "Why this is a dependency": 2-3 sentences on what we '
          'need from the counterparty (or they need from us), why the '
          'linked work cannot proceed without it, and what assumption '
          'we are making about when it lands.');
    case DependencyAssistField.impactStatement:
      sb.writeln(
          'Write the impact statement: 2-3 sentences on what happens to '
          'the project if this dependency slips or never lands — which '
          'activities or milestones move, by roughly how much, and what '
          'fallback (if any) exists.');
  }
  return RaidAssistPrompt(
      system: _system(projectContext), user: sb.toString());
}

/// Builds the prompt for one field of a decision.
RaidAssistPrompt decisionAssistPrompt({
  required DecisionAssistField field,
  required String description,
  required String status,
  String? decisionMaker,
  String? dueDate,
  String? rationale,
  String? optionsConsidered,
  String? impactStatement,
  String? outcome,
  String? linkedActivity,
  String? projectContext,
}) {
  final sb = StringBuffer();
  sb.writeln('DECISION');
  sb.write(_field('Decision required', description));
  sb.writeln('Status: $status');
  sb.write(_field('Decision maker', decisionMaker));
  sb.write(_field('Needed by', dueDate));
  sb.write(_field('Plan activity waiting on it', linkedActivity));
  sb.write(_field('Outcome (existing)', outcome));
  if (field != DecisionAssistField.rationale) {
    sb.write(_field('Rationale (existing)', rationale));
  }
  if (field != DecisionAssistField.optionsConsidered) {
    sb.write(_field('Options considered (existing)', optionsConsidered));
  }
  if (field != DecisionAssistField.impactStatement) {
    sb.write(_field('Impact of leaving it open (existing)', impactStatement));
  }
  sb.writeln();
  switch (field) {
    case DecisionAssistField.rationale:
      sb.writeln(
          'Write the rationale: 2-3 sentences on why this is the right '
          'call (or, if still pending, the case the decision maker will '
          'need to weigh) — the drivers, constraints and trade-offs that '
          'settle it.');
    case DecisionAssistField.optionsConsidered:
      sb.writeln(
          'Write the options considered as 2-4 short bullet points, each '
          'on its own line starting with "- ": the realistic alternatives '
          'including "do nothing / defer", with a few words on the main '
          'pro and con of each. Keep each bullet under 30 words.');
    case DecisionAssistField.impactStatement:
      sb.writeln(
          'Write the impact of leaving this undecided: 2-3 sentences on '
          'what is blocked or at risk while it stays open, which '
          'activities or milestones move, and by when a decision is '
          'needed to avoid that.');
  }
  return RaidAssistPrompt(
      system: _system(projectContext), user: sb.toString());
}
