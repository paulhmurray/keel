import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/export/pdf_exporter.dart';

/// Helvetica cannot draw the glyphs Keel uses on screen; the PDF must
/// carry their meaning in words or drop them, never print boxes.
void main() {
  test('trend arrows drop and the label stands alone', () {
    expect(sanitizeForPdf('→  Steady'), 'Steady');
    expect(sanitizeForPdf('↑ Improved'), 'Improved');
    expect(sanitizeForPdf('↓ Worsened'), 'Worsened');
  });
  test('register and plan glyphs become words or vanish', () {
    expect(sanitizeForPdf('▲ ESCALATED'), 'ESCALATED');
    expect(sanitizeForPdf('▲ was possible/major'), 'was possible/major');
    expect(sanitizeForPdf('◆ SIT exit'), 'SIT exit');
    expect(sanitizeForPdf('◈ Go/no-go'), '[gate] Go/no-go');
    expect(sanitizeForPdf('⚠ Contract end'), '[deadline] Contract end');
  });
  test('typographic punctuation maps to ASCII; unknown symbols are dropped',
      () {
    expect(sanitizeForPdf('Vendor — late… “quoted”'), 'Vendor -- late... "quoted"');
    expect(sanitizeForPdf('R3 · owner Sam'), 'R3 - owner Sam');
    expect(sanitizeForPdf('odd ✨ glyph'), 'odd glyph');
    expect(sanitizeForPdf('café'), 'café'); // Latin-1 is fine
    expect(sanitizeForPdf('€1,200'), 'EUR 1,200');
  });
}
