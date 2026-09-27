/// How a RAID entry should read, and a lint that says when it doesn't.
///
/// The house patterns (cause → event → effect for risks, and the
/// equivalents for the other kinds) are what the AI draft writes to and
/// what the quality hints check against. Pure Dart so both are testable.
library;

import 'raid_conversion_service.dart' show RaidKind;

/// The sentence shape each kind should follow. Shown as the field hint
/// and handed to the AI draft as its target form.
const Map<RaidKind, String> kRaidStatementPatterns = {
  RaidKind.risk:
      'If [cause], then [event] may occur, resulting in [impact].',
  RaidKind.assumption:
      'We are assuming [statement] because [basis]. If this proves false, '
      '[consequence]. Validated by [how/who] by [when].',
  RaidKind.issue:
      '[What has happened] because [cause]. It is [impact now] and blocks '
      '[what], so [resolution needed] by [when].',
  RaidKind.dependency:
      '[Counterparty] must deliver [what] by [date] so that [our activity] '
      'can [start/finish]; if late, [impact].',
};

/// Why the pattern matters, one line per kind — for tooltips and the
/// AI prompt.
const Map<RaidKind, String> kRaidStatementWhy = {
  RaidKind.risk:
      'A risk is an uncertain future event. Naming its cause tells you '
      'what to treat, the event tells you what to watch for, and the impact '
      'tells you why anyone should care.',
  RaidKind.assumption:
      'An assumption is a placeholder for a fact you do not yet have. '
      'Saying why you believe it, what breaks if it is wrong, and how it '
      'will be checked turns it into work rather than hope.',
  RaidKind.issue:
      'An issue has already happened. Write it in the present tense with '
      'its cause and the damage it is doing now — "may" and "could" belong '
      'in the risk register.',
  RaidKind.dependency:
      'A dependency is a promise from someone else. It needs a name, a '
      'deliverable, a date, what it gates on your side and the cost of it '
      'slipping.',
};

/// One thing the PM could improve. [severity] 2 = structural (the
/// statement is missing a part), 1 = polish.
class RaidQualityHint {
  final String text;
  final int severity;
  const RaidQualityHint(this.text, {this.severity = 2});

  @override
  bool operator ==(Object other) =>
      other is RaidQualityHint && other.text == text && other.severity == severity;
  @override
  int get hashCode => Object.hash(text, severity);
  @override
  String toString() => text;
}

const _kVague = [
  'issues',
  'problems',
  'resources',
  'resourcing',
  'things',
  'stuff',
  'various',
  'some',
  'etc',
  'delays', // as the whole description, not as the impact
];

bool _hasAny(String lower, List<String> needles) =>
    needles.any((n) => RegExp('\\b${RegExp.escape(n)}\\b').hasMatch(lower));

int _wordCount(String s) =>
    s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;

/// Quality hints for a RAID description in its form context. Empty means
/// well-formed by these rules; the rules are deliberately lenient about
/// wording (any cause word, any impact word) and strict about structure.
List<RaidQualityHint> raidQualityHints(
  RaidKind kind, {
  required String description,
  String? title,
  String? owner,
  String? dueDate,
  String? counterparty,
  String? validatedBy,
  String? impactStatement,
}) {
  final hints = <RaidQualityHint>[];
  final text = description.trim();
  final lower = text.toLowerCase();
  final words = _wordCount(text);

  if (words == 0) return const [];
  if (words < 8) {
    hints.add(const RaidQualityHint(
        'Too short to act on — a reader should know the cause, the event '
        'and the impact.'));
    return hints;
  }

  final hasCause = _hasAny(lower, [
    'if', 'because', 'due to', 'as a result of', 'caused by', 'given', 'since',
    'owing to', 'driven by', 'when',
  ]);
  final hasImpact = _hasAny(lower, [
    'resulting in', 'result in', 'results in', 'leading to', 'impact',
    'impacting', 'delay', 'delaying', 'delays', 'cost', 'costing', 'block',
    'blocking', 'blocks', 'slip', 'slipping', 'miss', 'missing', 'rework',
    'unable', 'cannot', "can't", 'lose', 'loss', 'breach', 'penalt',
    'exposure', 'outage', 'affecting', 'affects', 'jeopardis', 'jeopardiz',
    'so that', 'meaning', 'which means', 'which would',
  ]);
  final futureWords = _hasAny(lower, ['may', 'might', 'could', 'would', 'risk of', 'risk that', 'potential']);

  switch (kind) {
    case RaidKind.risk:
      if (lower.startsWith('risk of') || lower.startsWith('risk that') ||
          lower.startsWith('there is a risk')) {
        hints.add(const RaidQualityHint(
            'Drop "Risk of…" — the register already says it is a risk. Start '
            'with the cause: "If …".',
            severity: 1));
      }
      if (!hasCause) {
        hints.add(const RaidQualityHint(
            'Name the cause: what would have to happen for this event to occur '
            '("If …").'));
      }
      if (!futureWords && !lower.contains('then')) {
        hints.add(const RaidQualityHint(
            'State the uncertain event: what may occur ("then … may occur").'));
      }
      if (!hasImpact) {
        hints.add(const RaidQualityHint(
            'Say what it hits: schedule, cost, scope, quality or people '
            '("resulting in …").'));
      }
    case RaidKind.issue:
      if (futureWords && !_hasAny(lower, ['has', 'have', 'is', 'are', 'was', 'were'])) {
        hints.add(const RaidQualityHint(
            'This reads like a risk. An issue has already happened — write it '
            'in the present tense, or move it to Risks.'));
      } else if (futureWords) {
        hints.add(const RaidQualityHint(
            '"May" or "could" suggests uncertainty — is this an issue that has '
            'happened, or still a risk?',
            severity: 1));
      }
      if (!hasCause) {
        hints.add(const RaidQualityHint(
            'Say why it happened ("because …") — that is where the fix is.'));
      }
      if (!hasImpact &&
          (impactStatement == null || impactStatement.trim().isEmpty)) {
        hints.add(const RaidQualityHint(
            'Say what it is doing to the project now and what it blocks.'));
      }
      if (dueDate == null || dueDate.isEmpty) {
        hints.add(const RaidQualityHint(
            'Give it a resolution date — an issue without one drifts.',
            severity: 1));
      }
    case RaidKind.assumption:
      if (!_hasAny(lower, ['because', 'based on', 'as', 'since', 'given', 'per', 'according'])) {
        hints.add(const RaidQualityHint(
            'Say why you believe it ("because …", "based on …").'));
      }
      if (!_hasAny(lower, ['if this', 'if it', 'if not', 'if wrong', 'if false', 'otherwise', 'proves false', 'turns out', 'were wrong', 'is wrong', 'not true', 'fails'])) {
        hints.add(const RaidQualityHint(
            'Say what breaks if it turns out to be false.'));
      }
      final validationInText = _hasAny(lower, ['validate', 'validated', 'confirm', 'confirmed', 'verify', 'verified', 'check', 'checked', 'test', 'tested']);
      if (!validationInText && (validatedBy == null || validatedBy.trim().isEmpty)) {
        hints.add(const RaidQualityHint(
            'Say how and when it will be validated, and by whom.'));
      }
    case RaidKind.dependency:
      final hasParty = (counterparty != null && counterparty.trim().isNotEmpty) ||
          _hasAny(lower, ['from', 'by the', 'vendor', 'team', 'supplier', 'partner']);
      if (!hasParty) {
        hints.add(const RaidQualityHint(
            'Name who you depend on — a dependency without a counterparty '
            'cannot be chased.'));
      }
      if ((dueDate == null || dueDate.isEmpty) &&
          !RegExp(r'\b(by|before|until)\b').hasMatch(lower)) {
        hints.add(const RaidQualityHint(
            'Give it a needed-by date — that is what makes slack visible.'));
      }
      if (!hasImpact && (impactStatement == null || impactStatement.trim().isEmpty)) {
        hints.add(const RaidQualityHint(
            'Say what it gates on your side and what happens if it is late.'));
      }
    case RaidKind.decision:
      break;
  }

  // Vague nouns doing the work of specifics.
  final vague = _kVague.where((v) => RegExp('\\b$v\\b').hasMatch(lower)).toList();
  if (vague.isNotEmpty && words < 25) {
    hints.add(RaidQualityHint(
        'Vague: "${vague.first}" — name the specific system, team, '
        'deliverable or figure.',
        severity: 1));
  }

  // Title that just repeats the description (or vice versa).
  if (title != null && title.trim().isNotEmpty &&
      title.trim().toLowerCase() == lower) {
    hints.add(const RaidQualityHint(
        'Title and description are identical — the title is the headline, '
        'the description is the full statement.',
        severity: 1));
  }

  if (owner == null || owner.trim().isEmpty) {
    hints.add(const RaidQualityHint(
        'No owner — nothing in a register moves without one.',
        severity: 1));
  }
  return hints;
}
