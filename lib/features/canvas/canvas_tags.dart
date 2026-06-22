import 'dart:convert';

/// Pure helpers for the Canvas tag feature. Two responsibilities:
///   - Parse `#tagname` patterns out of free-text card bodies.
///   - Serialise/deserialise the resulting list to/from the JSON-string
///     stored in `CanvasCards.tags`.
///
/// Pure (no Drift, no Flutter) so it can be unit-tested in isolation.
class CanvasTags {
  /// Matches `#tag` patterns: a hash sign that's at start-of-string or
  /// after a non-word character, followed by 1+ chars from
  /// `[A-Za-z0-9_-]`. The leading look-behind prevents URL fragments
  /// (`page.com#section`) and middle-of-word hashes from being treated
  /// as tags.
  static final RegExp _pattern = RegExp(r'(?<![\w/])#([A-Za-z0-9_-]+)');

  /// Extracts tags from a free-text body string. Returns a list of
  /// lowercased tag strings (no `#` prefix), in first-appearance order,
  /// deduplicated. Returns an empty list when [body] is null or has no
  /// tag patterns.
  static List<String> extractFromBody(String? body) {
    if (body == null || body.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final match in _pattern.allMatches(body)) {
      final raw = match.group(1);
      if (raw == null || raw.isEmpty) continue;
      final tag = raw.toLowerCase();
      if (seen.add(tag)) out.add(tag);
    }
    return out;
  }

  /// Serialise a tag list to the string stored in the DB. Returns null
  /// for empty lists so the column stays null (saves bytes and makes
  /// "no tags" filter checks trivial).
  static String? encode(List<String> tags) {
    if (tags.isEmpty) return null;
    return jsonEncode(tags);
  }

  /// Parse the stored string back into a tag list. Returns an empty list
  /// when [raw] is null, empty, or invalid JSON — never throws.
  static List<String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } catch (_) {
      // Malformed payload — treat as no tags rather than crashing the
      // canvas. The next save rewrites the column.
    }
    return const [];
  }

  /// Inspects [body] at [caret] and decides whether the user is currently
  /// typing a `#tag`. When yes, returns a [TagSuggestion] describing the
  /// in-progress word and the matching candidates drawn from [knownTags].
  /// When the caret is not in a tag context (no preceding `#` since the
  /// last non-tag char, or the `#` is glued to a word char), returns null.
  ///
  /// Matching is case-insensitive against [knownTags] and ordered:
  ///   1. exact-prefix matches by length of overlap (shorter first)
  ///   2. then alphabetical
  /// Limited to [maxResults] entries to keep the popup compact.
  static TagSuggestion? suggestionAt(
    String body,
    int caret,
    Iterable<String> knownTags, {
    int maxResults = 6,
  }) {
    if (caret < 0 || caret > body.length) return null;
    // Walk left from the caret to find the `#` that starts the current
    // tag word, stopping if we hit a char that can't appear inside a tag.
    var i = caret - 1;
    while (i >= 0) {
      final ch = body.codeUnitAt(i);
      if (_isTagBodyChar(ch)) {
        i--;
        continue;
      }
      if (ch == 0x23 /* '#' */) {
        // Match the look-behind rule from [_pattern]: `#` must be at
        // start-of-string or after a non-word character.
        if (i > 0) {
          final prev = body.codeUnitAt(i - 1);
          if (_isWordChar(prev) || prev == 0x2F /* '/' */) return null;
        }
        break;
      }
      // Hit a non-tag, non-hash char — caret is not in a tag context.
      return null;
    }
    if (i < 0 || body.codeUnitAt(i) != 0x23) return null;
    final start = i;
    // Walk right from the caret to find the end of the tag word so we
    // know what range to replace when the user accepts a suggestion.
    var j = caret;
    while (j < body.length && _isTagBodyChar(body.codeUnitAt(j))) {
      j++;
    }
    final prefix = body.substring(start + 1, j).toLowerCase();
    final known = <String>{
      for (final t in knownTags) t.toLowerCase(),
    }.toList();
    final matches = <String>[];
    for (final t in known) {
      if (t == prefix) continue;
      if (t.startsWith(prefix)) matches.add(t);
    }
    matches.sort((a, b) {
      final byLen = a.length.compareTo(b.length);
      if (byLen != 0) return byLen;
      return a.compareTo(b);
    });
    return TagSuggestion(
      prefix: prefix,
      start: start,
      end: j,
      matches: matches.take(maxResults).toList(growable: false),
    );
  }

  /// Returns whether [ch] is a code unit that can appear inside the body
  /// of a tag (after the `#`). Mirrors the `[A-Za-z0-9_-]` character set
  /// used by [_pattern].
  static bool _isTagBodyChar(int ch) {
    return (ch >= 0x30 && ch <= 0x39) || // 0-9
        (ch >= 0x41 && ch <= 0x5A) || // A-Z
        (ch >= 0x61 && ch <= 0x7A) || // a-z
        ch == 0x5F || // _
        ch == 0x2D; // -
  }

  /// Word chars per the `\w` look-behind: letters, digits, underscore.
  static bool _isWordChar(int ch) {
    return (ch >= 0x30 && ch <= 0x39) ||
        (ch >= 0x41 && ch <= 0x5A) ||
        (ch >= 0x61 && ch <= 0x7A) ||
        ch == 0x5F;
  }
}

/// Snapshot of the in-progress `#tag` at the caret plus the matching
/// candidate tags. The editor uses this to render an autocomplete row
/// and to compute the body-text replacement when a suggestion is picked.
class TagSuggestion {
  /// Characters typed after `#`, already lowercased. May be empty when
  /// the user has just typed `#` with no following letters yet.
  final String prefix;

  /// Index of the `#` in the source body string. Inclusive.
  final int start;

  /// Exclusive end of the current tag word in the source body string.
  /// Equal to [start] + 1 + length-of-typed-chars (may extend past the
  /// caret if the cursor is mid-word).
  final int end;

  /// Candidate tags from the known set that start with [prefix], in
  /// "best match first" order (shortest first, then alphabetical). Does
  /// not include the prefix itself when it exactly matches a known tag.
  final List<String> matches;

  const TagSuggestion({
    required this.prefix,
    required this.start,
    required this.end,
    required this.matches,
  });

  bool get isEmpty => matches.isEmpty;
  bool get isNotEmpty => matches.isNotEmpty;

  /// Builds the (newBody, newCaret) pair that results from replacing the
  /// in-progress tag word with the chosen [tag]. The caret lands just
  /// after the completed tag.
  ({String body, int caret}) accept(String body, String tag) {
    final replacement = '#$tag';
    final newBody = body.replaceRange(start, end, replacement);
    return (body: newBody, caret: start + replacement.length);
  }
}
