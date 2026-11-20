/// Forgiving search for pick-lists (e.g. "Link a RAID item"): every word
/// the user types must land somewhere, but a word may land as a whole
/// word, the start of a word, anywhere inside a word, with one or two
/// typos ("suplier" → supplier), or as letters in order ("vndr" →
/// vendor). Better landings score higher, and fields carry weights so a
/// ref or title hit beats the same word buried in a description.
library;

/// One searchable field of a candidate.
class FuzzyField {
  final String text;
  final double weight;
  const FuzzyField(this.text, [this.weight = 1.0]);
}

/// A half-open [start, end) character range to highlight.
typedef FuzzySpan = (int start, int end);

class FuzzyMatch {
  final double score;

  /// Field index → ranges to highlight in that field's text.
  final Map<int, List<FuzzySpan>> spans;
  const FuzzyMatch(this.score, this.spans);

  List<FuzzySpan> spansFor(int field) => spans[field] ?? const [];
}

// Landing quality, best first.
const double _kWhole = 100; // the whole field ("r19" = "R19") or a whole word
const double _kWordStart = 70;
const double _kInside = 45;
const double _kTypo = 30;
const double _kInOrder = 15;

/// Scores [query] against [fields]. Returns null when any query word
/// can't be placed. An empty query matches with score 0.
FuzzyMatch? fuzzyMatch(String query, List<FuzzyField> fields) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return const FuzzyMatch(0, {});
  final lowered = [for (final f in fields) f.text.toLowerCase()];
  var total = 0.0;
  final spans = <int, List<FuzzySpan>>{};
  for (final w in words) {
    _Landing? best;
    for (var i = 0; i < fields.length; i++) {
      final l = _land(w, lowered[i]);
      if (l == null) continue;
      final s = l.quality * fields[i].weight;
      if (best == null || s > best.score) {
        best = _Landing(i, s, l.spans);
      }
    }
    if (best == null) return null;
    total += best.score;
    spans.putIfAbsent(best.field, () => []).addAll(best.spans);
  }
  return FuzzyMatch(total, {
    for (final e in spans.entries) e.key: _merge(e.value),
  });
}

/// Filters and ranks [items] best-first. Ties keep the input order, so
/// an empty query returns the list as given.
List<T> fuzzyRank<T>(
  Iterable<T> items,
  String query,
  List<FuzzyField> Function(T) fieldsOf,
) {
  final scored = <(T, double, int)>[];
  var i = 0;
  for (final item in items) {
    final m = fuzzyMatch(query, fieldsOf(item));
    if (m != null) scored.add((item, m.score, i));
    i++;
  }
  scored.sort((a, b) {
    final s = b.$2.compareTo(a.$2);
    return s != 0 ? s : a.$3.compareTo(b.$3);
  });
  return [for (final s in scored) s.$1];
}

class _Landing {
  final int field;
  final double score;
  final List<FuzzySpan> spans;
  _Landing(this.field, this.score, this.spans);
}

final _wordRe = RegExp(r'[a-z0-9]+');

({double quality, List<FuzzySpan> spans})? _land(String w, String text) {
  if (text.isEmpty) return null;
  if (text.trim() == w) return (quality: _kWhole + 20, spans: [(0, text.length)]);

  // Exact substring: rate the best occurrence.
  ({double quality, List<FuzzySpan> spans})? best;
  var from = 0;
  while (true) {
    final at = text.indexOf(w, from);
    if (at < 0) break;
    final startsWord = at == 0 || !_isWordChar(text.codeUnitAt(at - 1));
    final end = at + w.length;
    final endsWord = end == text.length || !_isWordChar(text.codeUnitAt(end));
    final q = startsWord ? (endsWord ? _kWhole : _kWordStart) : _kInside;
    if (best == null || q > best.quality) {
      best = (quality: q, spans: [(at, end)]);
      if (q == _kWhole) break;
    }
    from = at + 1;
  }
  if (best != null) return best;

  // Typos: compare against each word (or its same-length start, so a
  // half-typed "suplie" still finds "supplier").
  if (w.length >= 4) {
    final allowed = w.length >= 8 ? 2 : 1;
    for (final m in _wordRe.allMatches(text)) {
      final word = m.group(0)!;
      if (word.length < w.length - allowed) continue;
      // The whole word, or a start of it within [allowed] of w's length.
      final maxLen = word.length < w.length + allowed
          ? word.length
          : w.length + allowed;
      for (var len = w.length - allowed; len <= maxLen; len++) {
        if (len < 1) continue;
        if (_editDistance(w, word.substring(0, len), allowed) <= allowed) {
          return (quality: _kTypo, spans: [(m.start, m.end)]);
        }
      }
    }
  }

  // Letters in order inside one word ("vndr" → vendor, "dbmig" no).
  if (w.length >= 3) {
    for (final m in _wordRe.allMatches(text)) {
      final word = m.group(0)!;
      if (word[0] != w[0]) continue;
      final hits = <int>[];
      var j = 0;
      for (var k = 0; k < word.length && j < w.length; k++) {
        if (word[k] == w[j]) {
          hits.add(m.start + k);
          j++;
        }
      }
      if (j == w.length) {
        return (
          quality: _kInOrder,
          spans: [for (final h in hits) (h, h + 1)],
        );
      }
    }
  }
  return null;
}

bool _isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7a) || c > 0x7f;

/// Optimal-string-alignment distance (a swap of two neighbours counts
/// as one edit), bailing out once it must exceed [cap].
int _editDistance(String a, String b, int cap) {
  if ((a.length - b.length).abs() > cap) return cap + 1;
  final rows = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    rows[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    rows[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    var rowMin = cap + 1;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = [
        rows[i - 1][j] + 1,
        rows[i][j - 1] + 1,
        rows[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          rows[i - 2][j - 2] + 1 < v) {
        v = rows[i - 2][j - 2] + 1;
      }
      rows[i][j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > cap) return cap + 1;
  }
  return rows[a.length][b.length];
}

List<FuzzySpan> _merge(List<FuzzySpan> spans) {
  if (spans.length < 2) return spans;
  final sorted = [...spans]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <FuzzySpan>[sorted.first];
  for (final s in sorted.skip(1)) {
    final last = out.last;
    if (s.$1 <= last.$2) {
      out[out.length - 1] = (last.$1, s.$2 > last.$2 ? s.$2 : last.$2);
    } else {
      out.add(s);
    }
  }
  return out;
}
