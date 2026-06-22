import 'dart:ui' show Offset;

/// Layout math for quick-capture and multi-line paste — both flows drop
/// many cards in rapid succession and want a sensible cascade so cards
/// don't all stack on the same pixel.
///
/// Cards cascade diagonally within a "column"; once a column fills up
/// vertically, the next column begins to the right. This gives a
/// visible-on-glance grid of newly-captured ideas inside the This Week
/// band without overlapping.
class QuickCaptureLayout {
  /// Vertical distance between consecutive cards in the same column.
  static const double rowStep = 24;

  /// Horizontal distance between cascade columns.
  static const double columnStep = 256;

  /// Top-left offset for the very first card.
  static const Offset origin = Offset(16, 16);

  /// Number of cards stacked per column before we wrap to the next.
  static const int rowsPerColumn = 11;

  /// Returns the position of the [index]-th card in a cascade.
  /// Index 0 is the origin; higher indices step diagonally.
  static Offset positionFor(int index) {
    if (index < 0) return origin;
    final col = index ~/ rowsPerColumn;
    final row = index % rowsPerColumn;
    return Offset(
      origin.dx + col * columnStep,
      origin.dy + row * rowStep,
    );
  }

  /// Splits clipboard text into trimmed, non-blank lines. Used by both
  /// paste-to-multi-card and any future "import from clipboard" flow.
  /// Returns an empty list when the input has no usable content.
  static List<String> splitLines(String? text) {
    if (text == null) return const [];
    return text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }
}
