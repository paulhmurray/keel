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
