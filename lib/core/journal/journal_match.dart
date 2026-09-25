/// Finds the passage of a journal entry an extracted item most likely
/// came from. The parser paraphrases, so there's no exact substring to
/// look for; instead the entry is split into paragraphs and the one
/// sharing the most distinctive words with the item's text wins. Pure
/// Dart so it's unit-testable.
library;

class JournalMatch {
  /// Index of the matched paragraph in [splitParagraphs] order.
  final int paragraphIndex;
  final String paragraph;

  /// Share of the needle's distinctive words found in the paragraph,
  /// 0–1. Only matches at or above [kMinMatchScore] are returned.
  final double score;

  const JournalMatch({
    required this.paragraphIndex,
    required this.paragraph,
    required this.score,
  });
}

/// Below this share of overlapping words the match is noise and callers
/// should show the entry without a highlight.
const double kMinMatchScore = 0.34;

/// Words too common to tell paragraphs apart.
const Set<String> _kStopWords = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from', 'has',
  'have', 'in', 'is', 'it', 'its', 'of', 'on', 'or', 'that', 'the', 'to',
  'was', 'were', 'will', 'with', 'we', 'our', 'this', 'not', 'but', 'if',
  'so', 'do', 'does', 'did', 'can', 'need', 'needs', 'should', 'would',
  'could', 'may', 'might', 'than', 'then', 'they', 'them', 'their', 'there',
  'he', 'she', 'his', 'her', 'i', 'you', 'your', 'up', 'out', 'about',
  'into', 'over', 'also', 'been', 'being', 'no', 'yes', 'all', 'any',
};

/// Splits an entry body into non-empty paragraphs (blank-line separated;
/// single newlines inside a paragraph are kept).
List<String> splitParagraphs(String body) => body
    .split(RegExp(r'\n\s*\n'))
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty)
    .toList();

/// Distinctive lowercase word stems of [text]: letters/digits only,
/// three or more characters, stop words removed, a crude plural/verb
/// suffix strip so "delivers" and "delivery" still meet at "deliver".
Set<String> distinctiveWords(String text) {
  final out = <String>{};
  for (final m in RegExp(r'[A-Za-z0-9]+').allMatches(text.toLowerCase())) {
    var w = m.group(0)!;
    if (w.length < 3 || _kStopWords.contains(w)) continue;
    out.add(_stem(w));
  }
  return out;
}

String _stem(String w) {
  for (final suffix in const ['ies', 'ing', 'ed', 'es', 's', 'y']) {
    // Keep at least a three-letter base ("keys" → "key").
    if (w.length - suffix.length >= 3 && w.endsWith(suffix)) {
      var base = w.substring(0, w.length - suffix.length);
      if (suffix == 'ies') base = '${base}y';
      return base;
    }
  }
  return w;
}

/// The paragraph of [body] that best matches [needle], or null when
/// the overlap is too weak to be meaningful. Ties go to the earlier
/// paragraph (the note is usually chronological).
JournalMatch? bestMatchingParagraph(String body, String needle) {
  final want = distinctiveWords(needle);
  if (want.isEmpty) return null;
  final paragraphs = splitParagraphs(body);
  JournalMatch? best;
  for (var i = 0; i < paragraphs.length; i++) {
    final have = distinctiveWords(paragraphs[i]);
    if (have.isEmpty) continue;
    final overlap = want.intersection(have).length;
    final score = overlap / want.length;
    if (score >= kMinMatchScore && (best == null || score > best.score)) {
      best = JournalMatch(
          paragraphIndex: i, paragraph: paragraphs[i], score: score);
    }
  }
  return best;
}
