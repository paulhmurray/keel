import 'package:flutter/material.dart';

/// Guarantees [minWidth] for [child]: when the viewport is narrower
/// (e.g. the journal dock or Claude panel is squeezing the content
/// area), the content becomes horizontally scrollable at [minWidth]
/// instead of overflowing. At full width it's a transparent pass-through.
class MinWidthHScroll extends StatelessWidget {
  final double minWidth;
  final Widget child;

  const MinWidthHScroll({
    super.key,
    required this.minWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= minWidth) return child;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: minWidth, child: child),
      );
    });
  }
}
