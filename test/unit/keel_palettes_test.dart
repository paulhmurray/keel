import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keel/providers/settings_provider.dart';
import 'package:keel/shared/theme/keel_colors.dart';
import 'package:keel/shared/theme/keel_theme.dart';

/// Themes: every palette is complete and distinct, switching changes
/// what KColors reports, the theme builds for each, and the choice
/// survives the settings JSON round trip.
void main() {
  tearDown(() => KColors.apply(kKeelPalette));

  test('palette ids are unique and every role is set', () {
    final ids = kPalettes.map((p) => p.id).toSet();
    expect(ids.length, kPalettes.length);
    for (final p in kPalettes) {
      expect(p.roles.length, 19, reason: p.id);
      expect(p.name, isNotEmpty);
    }
    expect(kPalettes.where((p) => p.isLight).map((p) => p.id), [
      'catppuccin-latte',
    ]);
  });

  test('applying a palette changes what KColors reports, and back', () {
    final before = KColors.amber;
    KColors.apply(paletteById('nord'));
    expect(KColors.amber, const Color(0xFFebcb8b));
    expect(KColors.palette.id, 'nord');
    KColors.apply(kKeelPalette);
    expect(KColors.amber, before);
    expect(paletteById('nope').id, 'keel', reason: 'unknown ids fall back');
  });

  test('the colour scheme follows each palette\'s brightness and accents', () {
    for (final p in kPalettes) {
      KColors.apply(p);
      final scheme = keelColorSchemeFor(p);
      expect(scheme.brightness, p.brightness, reason: p.id);
      expect(scheme.primary, p.amber, reason: p.id);
      expect(scheme.onPrimary, p.onAccent, reason: p.id);
      expect(scheme.surface, p.surface, reason: p.id);
    }
  });

  test('the chosen theme round-trips through settings JSON', () {
    const s = AppSettings(themeId: 'rose-pine');
    final back = AppSettings.fromJson(s.toJson());
    expect(back.themeId, 'rose-pine');
    expect(AppSettings.fromJson(const {}).themeId, 'keel');
  });
}
