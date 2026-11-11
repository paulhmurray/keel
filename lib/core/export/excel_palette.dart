/// Light, print-friendly palette + contrast helpers for Excel exports.
///
/// Excel's ground is WHITE, not Keel's dark surface — an exported sheet
/// must be readable on someone else's machine with zero touch-up. The
/// invariant every cell style must satisfy: dark text on white/tinted
/// backgrounds, light text only on genuinely dark fills, and never
/// fg == bg. All hex values are 8-digit ARGB with an opaque FF alpha.
library;

// ── Ink (text) ─────────────────────────────────────────────────────────
const kXlInk = 'FF1F2937'; // near-black body text
const kXlInkDim = 'FF6B7280'; // secondary text
const kXlWhite = 'FFFFFFFF';

// ── Structure ──────────────────────────────────────────────────────────
const kXlTitleBand = 'FF1F2937'; // dark title band (white text on it)
const kXlHeaderBg = 'FFE5E7EB'; // column-header / group band fill
const kXlBorder = 'FFD1D5DB'; // light grid lines

// ── Status tints (light fill + matching dark text, always paired) ──────
const kXlRedText = 'FFB91C1C';
const kXlRedTint = 'FFFDE8E8';
const kXlAmberText = 'FF92400E';
const kXlAmberTint = 'FFFEF3C7';
const kXlGreenText = 'FF046C4E';
const kXlGreenTint = 'FFDEF7EC';
const kXlVioletText = 'FF6D28D9';
const kXlVioletTint = 'FFEDE9FE';

/// Blends the RGB channels of an 8-digit ARGB hex toward white by
/// [factor] (0 = unchanged, 1 = white). Alpha is always forced to FF and
/// the result is always exactly 8 hex digits — this helper exists partly
/// so the old `'${hex}44'` 10-digit malformation can't come back.
String xlTint(String argbHex, [double factor = 0.8]) {
  assert(argbHex.length == 8, 'expected 8-digit ARGB hex');
  int channel(int offset) =>
      int.parse(argbHex.substring(offset, offset + 2), radix: 16);
  String mix(int c) {
    final mixed = (c + (255 - c) * factor).round().clamp(0, 255);
    return mixed.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  return 'FF${mix(channel(2))}${mix(channel(4))}${mix(channel(6))}';
}

/// Picks black-ish ink or white for text sitting on [argbHex], using the
/// standard YIQ luminance formula — removes per-colour judgment calls
/// (white on an amber work-package band is unreadable; ink is not).
String xlContrastText(String argbHex) {
  assert(argbHex.length == 8, 'expected 8-digit ARGB hex');
  final r = int.parse(argbHex.substring(2, 4), radix: 16);
  final g = int.parse(argbHex.substring(4, 6), radix: 16);
  final b = int.parse(argbHex.substring(6, 8), radix: 16);
  final yiq = (r * 299 + g * 587 + b * 114) / 1000;
  return yiq >= 150 ? kXlInk : kXlWhite;
}

// ── Row layout ─────────────────────────────────────────────────────────
//
// Excel never autofits a row the file gives an explicit height, and a
// row with no height is left at the default by Excel and by the Teams
// and browser previews the workbook is opened in. So every row that
// carries wrapped text gets a height worked out here from the text and
// the column it sits in. Over-estimating slightly is harmless (a little
// air under the text); under-estimating hides the text behind the next
// row, which is the bug this exists to prevent.

/// Points per line of 10pt text, plus the cell's vertical padding.
const double kXlLineHeight = 13.5;
const double kXlRowPadding = 4.0;

/// Excel's hard ceiling for a row height, in points.
const double kXlMaxRowHeight = 409.0;

/// Characters of 10pt body text that fit per Excel column-width unit.
/// A unit is one digit of the default 11pt font; 10pt prose averages
/// narrower, so a touch more than one fits. Measured against a real
/// register: 1.15 leaves a little air under long rows without ever
/// clipping them. Err low, never high.
const double kXlCharsPerWidthUnit = 1.15;

/// Lines [text] takes when wrapped in a column [widthUnits] wide:
/// explicit line breaks count, and each paragraph wraps by length.
int xlWrappedLines(String text, double widthUnits) {
  final perLine = (widthUnits * kXlCharsPerWidthUnit).floor().clamp(1, 1 << 20);
  var lines = 0;
  for (final para in text.split('\n')) {
    final len = para.trimRight().length;
    lines += len == 0 ? 1 : (len / perLine).ceil();
  }
  return lines < 1 ? 1 : lines;
}

/// The height for a row whose wrapped cells are [cells] (text, column
/// width in Excel units), never under [min]. Unwrapped cells are not
/// passed: they stay one line whatever they hold.
double xlRowHeight(Iterable<(String, double)> cells, {double min = 18}) {
  var lines = 1;
  for (final (text, width) in cells) {
    final n = xlWrappedLines(text, width);
    if (n > lines) lines = n;
  }
  final h = lines * kXlLineHeight + kXlRowPadding;
  final clamped = h > kXlMaxRowHeight ? kXlMaxRowHeight : h;
  return clamped < min ? min : clamped;
}
