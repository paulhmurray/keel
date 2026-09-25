import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/raid/risk_rating.dart';

void main() {
  group('normalise', () {
    test('scale words pass through, any case', () {
      expect(normaliseLikelihood('Likely'), 'likely');
      expect(normaliseLikelihood('ALMOST CERTAIN'), 'almost certain');
      expect(normaliseConsequence(' Severe '), 'severe');
    });

    test('legacy low/medium/high map onto the scale', () {
      expect(normaliseLikelihood('low'), 'unlikely');
      expect(normaliseLikelihood('medium'), 'possible');
      expect(normaliseLikelihood('high'), 'likely');
      expect(normaliseConsequence('low'), 'minor');
      expect(normaliseConsequence('medium'), 'moderate');
      expect(normaliseConsequence('high'), 'major');
    });

    test('unknown or null falls back to the middle', () {
      expect(normaliseLikelihood(null), 'possible');
      expect(normaliseLikelihood('banana'), 'possible');
      expect(normaliseConsequence(''), 'moderate');
    });

    test('common synonyms', () {
      expect(normaliseLikelihood('almost_certain'), 'almost certain');
      expect(normaliseConsequence('insignificant'), 'minimal');
      expect(normaliseConsequence('catastrophic'), 'severe');
    });
  });

  group('rank and score', () {
    test('ranks run 1–5 in scale order', () {
      expect(kLikelihoodScale.map(likelihoodRank), [1, 2, 3, 4, 5]);
      expect(kConsequenceScale.map(consequenceRank), [1, 2, 3, 4, 5]);
    });

    test('score is the product', () {
      expect(riskScore('likely', 'major'), 16);
      expect(riskScore('rare', 'minimal'), 1);
      expect(riskScore('almost certain', 'severe'), 25);
      expect(riskScore('low', 'high'), 8); // legacy words still score
    });
  });

  group('riskBand keeps the old colours', () {
    test('old high/high is still red', () {
      expect(riskBand('high', 'high'), 'high'); // likely/major = 16
    });
    test('old medium/high and high/medium are still amber', () {
      expect(riskBand('medium', 'high'), 'medium'); // 12
      expect(riskBand('high', 'medium'), 'medium'); // 12
    });
    test('old low/low, low/medium and medium/low are still green', () {
      expect(riskBand('low', 'low'), 'low'); // 4
      expect(riskBand('low', 'medium'), 'low'); // 6
      expect(riskBand('medium', 'low'), 'low'); // 6
    });
    test('boundaries', () {
      expect(riskBand('almost certain', 'moderate'), 'high'); // 15
      expect(riskBand('possible', 'major'), 'medium'); // 12
      expect(riskBand('unlikely', 'major'), 'medium'); // 8
      expect(riskBand('possible', 'minor'), 'low'); // 6
    });
    test('single-level bands', () {
      expect(levelBand(5), 'high');
      expect(levelBand(4), 'high');
      expect(levelBand(3), 'medium');
      expect(levelBand(2), 'low');
    });
  });

  group('labels and summary', () {
    test('labels are title-cased scale words', () {
      expect(likelihoodLabel('almost certain'), 'Almost certain');
      expect(consequenceLabel('high'), 'Major');
      expect(ratingSummary('likely', 'major'), 'Likely / Major (16)');
    });
  });

  group('review cadence', () {
    test('next review is 14 days on', () {
      expect(nextReviewFrom(DateTime(2026, 9, 9)), '2026-09-23');
      expect(nextReviewFrom(DateTime(2026, 12, 25)), '2027-01-08');
    });
    test('overdue compares ISO dates', () {
      final today = DateTime(2026, 9, 25);
      expect(reviewOverdue('2026-09-23', today), isTrue);
      expect(reviewOverdue('2026-09-25', today), isFalse);
      expect(reviewOverdue('2026-10-01', today), isFalse);
      expect(reviewOverdue(null, today), isFalse);
    });
  });
}
