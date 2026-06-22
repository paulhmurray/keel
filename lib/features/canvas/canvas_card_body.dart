import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../shared/theme/keel_colors.dart';

/// Renders a card's body as markdown using a tight stylesheet sized for
/// the small Canvas card surface. Bold/italic/code/lists/links work;
/// large block elements (h1/h2/h3, blockquote, fenced code) are styled
/// down so they never blow the card height out of proportion.
///
/// The widget clips overflow rather than scrolling — the editor side
/// panel is the place to read long bodies; the card itself is the
/// at-a-glance representation.
class CanvasCardBody extends StatelessWidget {
  final String body;
  final TextStyle baseStyle;

  const CanvasCardBody({
    super.key,
    required this.body,
    this.baseStyle = const TextStyle(
      color: KColors.textDim,
      fontSize: 11.5,
      height: 1.3,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final stylesheet = MarkdownStyleSheet(
      p: baseStyle,
      pPadding: EdgeInsets.zero,
      // All heading levels collapse to a slightly bigger, still-tight
      // style so a stray `#` in a body doesn't blow up the card.
      h1: baseStyle.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: KColors.text,
      ),
      h2: baseStyle.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: KColors.text,
      ),
      h3: baseStyle.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: KColors.text,
      ),
      h1Padding: EdgeInsets.zero,
      h2Padding: EdgeInsets.zero,
      h3Padding: EdgeInsets.zero,
      strong: baseStyle.copyWith(
        fontWeight: FontWeight.w700,
        color: KColors.text,
      ),
      em: baseStyle.copyWith(fontStyle: FontStyle.italic),
      code: baseStyle.copyWith(
        fontFamily: 'monospace',
        backgroundColor: KColors.surface2,
        fontSize: 11,
      ),
      codeblockDecoration: BoxDecoration(
        color: KColors.surface2,
        borderRadius: BorderRadius.circular(3),
      ),
      codeblockPadding: const EdgeInsets.symmetric(
          horizontal: 6, vertical: 4),
      blockquote: baseStyle.copyWith(
        color: KColors.textMuted,
        fontStyle: FontStyle.italic,
      ),
      blockquotePadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      blockquoteDecoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: KColors.border2, width: 2),
        ),
      ),
      listBullet: baseStyle,
      a: baseStyle.copyWith(
        color: KColors.amber,
        decoration: TextDecoration.underline,
      ),
      listIndent: 14,
      blockSpacing: 4,
    );
    // MarkdownBody builds an internal Column at its natural height. When
    // the parent gives us less vertical space than the rendered markdown
    // needs (common on small cards), that Column overflows and Flutter
    // throws a layout assertion. ClipRect alone doesn't help — it only
    // clips the visual paint, not the layout constraint.
    //
    // OverflowBox releases the height constraint so the inner Column
    // can lay out at its natural size; the surrounding ClipRect cuts
    // the painted overflow at the card edge.
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minHeight: 0,
            maxHeight: double.infinity,
            minWidth: constraints.minWidth,
            maxWidth: constraints.maxWidth,
            child: MarkdownBody(
              data: body,
              styleSheet: stylesheet,
              shrinkWrap: true,
              softLineBreak: true,
              // Tapping links opens nothing for now — Phase 1 wires
              // #tag and @person mention handlers; bare URLs can route
              // via url_launcher later if the user starts pasting links.
              onTapLink: (_, __, ___) {},
            ),
          ),
        );
      },
    );
  }
}
