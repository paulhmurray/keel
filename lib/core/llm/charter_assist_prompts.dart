/// Prompt builders for the per-section "AI draft" buttons on the Charter.
///
/// Pure, like the RAID prompts: the charter's other sections plus the
/// project context are the raw material; the draft fills or sharpens ONE
/// section and never invents facts. Wording is project-or-programme
/// aware so a project charter never calls itself a programme.
library;

import 'raid_assist_prompts.dart' show RaidAssistPrompt;

enum CharterField {
  vision,
  objectives,
  scopeIn,
  scopeOut,
  deliveryApproach,
  successCriteria,
  keyConstraints,
  assumptions,
}

String charterFieldLabel(CharterField f) => switch (f) {
      CharterField.vision => 'Vision',
      CharterField.objectives => 'Objectives',
      CharterField.scopeIn => 'In scope',
      CharterField.scopeOut => 'Out of scope',
      CharterField.deliveryApproach => 'Delivery approach',
      CharterField.successCriteria => 'Success criteria',
      CharterField.keyConstraints => 'Key constraints',
      CharterField.assumptions => 'Assumptions',
    };

String _field(String label, String? value) =>
    value == null || value.trim().isEmpty ? '' : '$label:\n${value.trim()}\n\n';

RaidAssistPrompt charterAssistPrompt({
  required CharterField field,
  required bool isProgramme,
  String? vision,
  String? objectives,
  String? scopeIn,
  String? scopeOut,
  String? deliveryApproach,
  String? successCriteria,
  String? keyConstraints,
  String? assumptions,
  String? projectContext,
}) {
  final entity = isProgramme ? 'programme' : 'project';
  final persona =
      'You are helping a $entity manager write one section of the $entity '
      'charter. Call it "the $entity" throughout'
      '${isProgramme ? '' : ' — "programme" means only the wider programme it reports into, if the context names one'}. '
      'Write plain, direct English a sponsor would sign off. Output ONLY the '
      'text for the section: no heading, no preamble, no markdown emphasis. '
      'Never invent facts (dates, names, figures, systems) that are not in '
      'the material you were given; where something is unknown, write it as '
      'a bracketed point to confirm, e.g. "[go-live date to confirm]".';
  final system = projectContext == null || projectContext.trim().isEmpty
      ? persona
      : '$projectContext\n\n---\n\n$persona';

  final sb = StringBuffer();
  sb.writeln('CHARTER (existing sections)');
  sb.writeln();
  final current = switch (field) {
    CharterField.vision => vision,
    CharterField.objectives => objectives,
    CharterField.scopeIn => scopeIn,
    CharterField.scopeOut => scopeOut,
    CharterField.deliveryApproach => deliveryApproach,
    CharterField.successCriteria => successCriteria,
    CharterField.keyConstraints => keyConstraints,
    CharterField.assumptions => assumptions,
  };
  if (field != CharterField.vision) sb.write(_field('Vision', vision));
  if (field != CharterField.objectives) sb.write(_field('Objectives', objectives));
  if (field != CharterField.scopeIn) sb.write(_field('In scope', scopeIn));
  if (field != CharterField.scopeOut) sb.write(_field('Out of scope', scopeOut));
  if (field != CharterField.deliveryApproach) {
    sb.write(_field('Delivery approach', deliveryApproach));
  }
  if (field != CharterField.successCriteria) {
    sb.write(_field('Success criteria', successCriteria));
  }
  if (field != CharterField.keyConstraints) {
    sb.write(_field('Key constraints', keyConstraints));
  }
  if (field != CharterField.assumptions) sb.write(_field('Assumptions', assumptions));
  sb.write(_field('${charterFieldLabel(field)} (existing draft, to improve)', current));

  sb.writeln(switch (field) {
    CharterField.vision =>
      'Write the VISION: one or two sentences on what success looks like for '
      'the $entity when it is done — the outcome for the business, not the '
      'activity. No bullet points.',
    CharterField.objectives =>
      'Write the OBJECTIVES as 3-6 bullet points, each on its own line '
      'starting with "- ", each a measurable outcome the $entity must '
      'deliver (what, by when where known, how measured). Keep each under '
      '25 words.',
    CharterField.scopeIn =>
      'Write IN SCOPE as 4-8 bullet points, each on its own line starting '
      'with "- ": the systems, processes, teams and deliverables this '
      '$entity explicitly covers. Concrete nouns, no verbs of intent.',
    CharterField.scopeOut =>
      'Write OUT OF SCOPE as 3-6 bullet points, each on its own line '
      'starting with "- ": what a reasonable stakeholder might assume is '
      'included but is not, and who owns it instead where known.',
    CharterField.deliveryApproach =>
      'Write the DELIVERY APPROACH: one short paragraph on how the $entity '
      'will be delivered — phasing, methodology, key partners, governance '
      'cadence — drawn from the plan and people in the context. Under 120 '
      'words.',
    CharterField.successCriteria =>
      'Write SUCCESS CRITERIA as 3-6 bullet points, each on its own line '
      'starting with "- ": the tests a sponsor would apply at the end to say '
      'it worked. Each must be observable; pair with a measure where the '
      'material gives one.',
    CharterField.keyConstraints =>
      'Write KEY CONSTRAINTS as 3-6 bullet points, each on its own line '
      'starting with "- ": the fixed boundaries — budget, dates, regulation, '
      'contracts, dependencies on others — that the $entity cannot move. '
      'Use the hard deadline, budget and dependencies in the context where '
      'present.',
    CharterField.assumptions =>
      'Write ASSUMPTIONS as 3-6 bullet points, each on its own line starting '
      'with "- ", each in the form "We are assuming [statement] because '
      '[basis]; if false, [consequence]". Draw on the risk and assumption '
      'registers in the context.',
  });
  return RaidAssistPrompt(system: system, user: sb.toString());
}
