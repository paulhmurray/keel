/// Computes the portion of a journal body that still needs parsing,
/// given the snapshot of what was parsed last time.
///
/// The common running-note flow is a pure append, which returns just the
/// added suffix. Edits elsewhere in the note fall back to a line-level
/// diff: any line not present verbatim in the parsed snapshot counts as
/// new (so an *edited* statement is re-parsed, an untouched one isn't).
///
/// Returns the full [body] when there's no snapshot, and an empty string
/// when nothing new needs parsing.
String unparsedText({
  required String? lastParsedBody,
  required String body,
}) {
  final cur = body.trim();
  final last = lastParsedBody?.trim() ?? '';
  if (last.isEmpty) return cur;
  if (cur == last) return '';

  // Pure append — parse only what came after the parsed snapshot.
  if (cur.startsWith(last)) {
    return cur.substring(last.length).trim();
  }

  // Edited elsewhere — line diff against the parsed snapshot.
  final parsedLines = last
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toSet();
  final freshLines = cur
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !parsedLines.contains(l));
  return freshLines.join('\n');
}
