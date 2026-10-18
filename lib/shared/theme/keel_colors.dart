import 'package:flutter/material.dart';

import 'keel_palettes.dart';

export 'keel_palettes.dart'
    show KeelPalette, kPalettes, kKeelPalette, paletteById;

/// The UI palette, read everywhere as `KColors.amber` and friends.
///
/// Backed by the palette the user picked in Settings → Appearance; the
/// role names are historical (see [KeelPalette]). These are getters, not
/// constants, so a theme change takes effect without touching call
/// sites — the app keys its root on the palette id so every widget
/// rebuilds.
abstract class KColors {
  static KeelPalette _current = kKeelPalette;

  static KeelPalette get palette => _current;

  /// Switches the palette. The caller is responsible for rebuilding the
  /// widget tree (see app.dart).
  static void apply(KeelPalette palette) => _current = palette;

  static Color get bg => _current.bg;
  static Color get surface => _current.surface;
  static Color get surface2 => _current.surface2;
  static Color get border => _current.border;
  static Color get border2 => _current.border2;
  static Color get amber => _current.amber;
  static Color get amberDim => _current.amberDim;
  static Color get phosphor => _current.phosphor;
  static Color get phosDim => _current.phosDim;
  static Color get red => _current.red;
  static Color get redDim => _current.redDim;
  static Color get blue => _current.blue;
  static Color get blueDim => _current.blueDim;
  static Color get violet => _current.violet;
  static Color get violetDim => _current.violetDim;
  static Color get text => _current.text;
  static Color get textDim => _current.textDim;
  static Color get textMuted => _current.textMuted;

  /// Text on a primary or positive fill.
  static Color get onAccent => _current.onAccent;
}
