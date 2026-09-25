/// The risk rating scale, in one place.
///
/// Risks are rated on the 5-level scale TAC's Planview uses — five words
/// for likelihood, five for consequence — and every consumer (register
/// colours, exports, status roll-ups, the LLM context) derives what it
/// needs from here: a rank 1–5, a score 1–25, and a three-band summary
/// (low/medium/high) that keeps the older RAG colours working.
///
/// Legacy rows and legacy writers (the journal parser prompt, inbox
/// parsers, older sync blobs) still say low/medium/high; [normalise]
/// maps those onto the scale so nothing downstream ever sees them.
library;

const List<String> kLikelihoodScale = [
  'rare', 'unlikely', 'possible', 'likely', 'almost certain',
];

const List<String> kConsequenceScale = [
  'minimal', 'minor', 'moderate', 'major', 'severe',
];

const Map<String, String> kLikelihoodLabels = {
  'rare': 'Rare',
  'unlikely': 'Unlikely',
  'possible': 'Possible',
  'likely': 'Likely',
  'almost certain': 'Almost certain',
};

const Map<String, String> kConsequenceLabels = {
  'minimal': 'Minimal',
  'minor': 'Minor',
  'moderate': 'Moderate',
  'major': 'Major',
  'severe': 'Severe',
};

const List<String> kRiskStrategies = [
  'treat', 'tolerate', 'transfer', 'terminate',
];

const Map<String, String> kRiskStrategyLabels = {
  'treat': 'Treat — mitigation reduces likelihood or consequence',
  'tolerate': 'Tolerate — accepted, monitored, no spend',
  'transfer': 'Transfer — sits with another project or contract',
  'terminate': 'Terminate — cause removed; recommend closing',
};

/// The organisation's enterprise risk categories, as seen in its
/// register. Offered as suggestions; free text is allowed.
const List<String> kEnterpriseRiskLinks = [
  'Strategic Delivery',
  'Process Failure',
  'Business Continuity / Disruption',
  'Legal and Regulatory',
  'Scheme Sustainability',
  'Stakeholder Trust/Relationships',
  'Client Experience / Outcome',
  'Performance',
];

/// Review cadence: fortnightly, aligned to business-owner reporting.
const int kRiskReviewCadenceDays = 14;

const Map<String, String> _kLegacyLikelihood = {
  'low': 'unlikely',
  'medium': 'possible',
  'high': 'likely',
};

const Map<String, String> _kLegacyConsequence = {
  'low': 'minor',
  'medium': 'moderate',
  'high': 'major',
};

String _clean(String? v) => (v ?? '').trim().toLowerCase();

/// A likelihood value on the scale, whatever vocabulary it arrived in.
/// Unknown words fall back to the middle of the scale.
String normaliseLikelihood(String? raw) {
  final v = _clean(raw);
  if (kLikelihoodScale.contains(v)) return v;
  if (_kLegacyLikelihood.containsKey(v)) return _kLegacyLikelihood[v]!;
  if (v == 'almost_certain' || v == 'almost-certain' || v == 'certain') {
    return 'almost certain';
  }
  return 'possible';
}

/// A consequence value on the scale, whatever vocabulary it arrived in.
String normaliseConsequence(String? raw) {
  final v = _clean(raw);
  if (kConsequenceScale.contains(v)) return v;
  if (_kLegacyConsequence.containsKey(v)) return _kLegacyConsequence[v]!;
  if (v == 'insignificant' || v == 'negligible') return 'minimal';
  if (v == 'catastrophic' || v == 'critical' || v == 'extreme') {
    return 'severe';
  }
  return 'moderate';
}

/// 1 (rare) … 5 (almost certain).
int likelihoodRank(String? raw) =>
    kLikelihoodScale.indexOf(normaliseLikelihood(raw)) + 1;

/// 1 (minimal) … 5 (severe).
int consequenceRank(String? raw) =>
    kConsequenceScale.indexOf(normaliseConsequence(raw)) + 1;

/// likelihood × consequence, 1–25.
int riskScore(String? likelihood, String? consequence) =>
    likelihoodRank(likelihood) * consequenceRank(consequence);

/// Three-band summary of a score, tuned so the colours the old 3×3
/// matrix produced barely move: old high/high (now likely/major, 16)
/// stays red, old medium/high (possible/major, 12) stays amber, old
/// low/low (unlikely/minor, 4) stays green.
String riskBand(String? likelihood, String? consequence) {
  final s = riskScore(likelihood, consequence);
  if (s >= 15) return 'high';
  if (s >= 8) return 'medium';
  return 'low';
}

/// Three-band summary of a single level, for colouring one cell:
/// ranks 4–5 high, 3 medium, 1–2 low.
String levelBand(int rank) => rank >= 4 ? 'high' : rank == 3 ? 'medium' : 'low';

String likelihoodLabel(String? raw) =>
    kLikelihoodLabels[normaliseLikelihood(raw)]!;

String consequenceLabel(String? raw) =>
    kConsequenceLabels[normaliseConsequence(raw)]!;

/// "Likely / Major (16)" — the compact rating string for lists and prompts.
String ratingSummary(String? likelihood, String? consequence) =>
    '${likelihoodLabel(likelihood)} / ${consequenceLabel(consequence)} '
    '(${riskScore(likelihood, consequence)})';

/// The next review date: [from] plus the cadence, as an ISO date.
String nextReviewFrom(DateTime from) {
  final d = from.add(const Duration(days: kRiskReviewCadenceDays));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// True when the review is overdue against [today] (ISO date compare).
bool reviewOverdue(String? nextReviewAt, DateTime today) {
  if (nextReviewAt == null || nextReviewAt.isEmpty) return false;
  final t = '${today.year.toString().padLeft(4, '0')}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';
  return nextReviewAt.compareTo(t) < 0;
}
