import 'package:flutter/material.dart';

import '../../shared/theme/keel_colors.dart';

/// Layout and visual constants for the Canvas view. Kept here so every
/// canvas widget agrees on band heights, default card sizes, drop-target
/// padding, etc.
class CanvasLayout {
  /// Header strip above the bands.
  static const double headerHeight = 56;

  /// Visible height of each band before internal scroll kicks in.
  static const double bandHeight = 300;

  /// Padding inside a band where cards may not be placed (drop-targets
  /// still accept hits in this margin).
  static const double bandInnerPadding = 16;

  /// Default new-card position when no drop point is supplied.
  static const Offset defaultDropOffset = Offset(16, 16);
}

class CanvasCardDimensions {
  static const Size small = Size(200, 120);
  static const Size medium = Size(240, 160);
  static const Size large = Size(280, 220);

  static Size forSize(String? size) {
    switch (size) {
      case 'small':
        return small;
      case 'large':
        return large;
      case 'medium':
      default:
        return medium;
    }
  }
}

/// Visual colour mapping for the optional bottom colour band on each card.
class CanvasCardColours {
  static const Map<String, Color> palette = {
    'amber': KColors.amber,
    'green': KColors.phosphor,
    'red': KColors.red,
    'blue': KColors.blue,
    'purple': Color(0xFFb46cff),
  };

  static const List<String> all = ['amber', 'green', 'red', 'blue', 'purple'];

  static Color? colourFor(String? key) =>
      key == null ? null : palette[key];
}

/// Subtle band background — slightly brighter for the active "This Week"
/// focus band, dimmer as the horizon recedes.
class CanvasBandTheme {
  static Color backgroundFor(String band) {
    switch (band) {
      case 'this_week':
        return KColors.surface2;
      case 'next_30_days':
        return KColors.surface;
      case 'horizon':
        return const Color(0xFF101820);
      default:
        return KColors.surface;
    }
  }

  static String emptyHint(String band) {
    switch (band) {
      case 'this_week':
        return 'Drop a card here. Pull in a risk, action, or decision. '
            'Or just start thinking.';
      case 'next_30_days':
        return 'What\'s coming up in the next month? Sequence your moves.';
      case 'horizon':
        return 'The longer game — end-of-programme thinking, exits, '
            'handovers.';
      default:
        return 'Drop a card here.';
    }
  }
}
