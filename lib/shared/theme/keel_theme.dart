import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'keel_colors.dart';

/// The app theme for whatever palette [KColors] currently holds.
ThemeData get keelTheme => keelThemeFor(KColors.palette);

/// The colour scheme for [palette], read through [KColors] (apply the
/// palette first). Pure, so tests can pin brightness and accents without
/// building a full theme, which pulls Google Fonts.
ColorScheme keelColorSchemeFor(KeelPalette palette) => palette.isLight
    ? ColorScheme.light(
        primary: KColors.amber,
        onPrimary: KColors.onAccent,
        primaryContainer: KColors.amberDim,
        onPrimaryContainer: KColors.amber,
        secondary: KColors.phosphor,
        onSecondary: KColors.onAccent,
        secondaryContainer: KColors.phosDim,
        onSecondaryContainer: KColors.phosphor,
        surface: KColors.surface,
        onSurface: KColors.text,
        error: KColors.red,
        onError: KColors.onAccent,
        outline: KColors.border,
        outlineVariant: KColors.border2,
      )
    : ColorScheme.dark(
        primary: KColors.amber,
        onPrimary: KColors.onAccent,
        primaryContainer: KColors.amberDim,
        onPrimaryContainer: KColors.amber,
        secondary: KColors.phosphor,
        onSecondary: KColors.onAccent,
        secondaryContainer: KColors.phosDim,
        onSecondaryContainer: KColors.phosphor,
        surface: KColors.surface,
        onSurface: KColors.text,
        error: KColors.red,
        onError: KColors.onAccent,
        outline: KColors.border,
        outlineVariant: KColors.border2,
      );

/// Builds the theme for [palette]. Reads the roles through [KColors], so
/// the caller must have applied the palette first (app.dart does).
ThemeData keelThemeFor(KeelPalette palette) {
  final scheme = keelColorSchemeFor(palette);
  final base = ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: scheme,
  );

  // Inter for body text; JetBrains Mono applied selectively below for
  // labels, metadata, inputs and chips.
  final interBase = GoogleFonts.interTextTheme(base.textTheme);

  return base.copyWith(
    scaffoldBackgroundColor: KColors.bg,
    cardColor: KColors.surface,
    cardTheme: CardThemeData(
      color: KColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: KColors.border, width: 1),
      ),
      margin: const EdgeInsets.all(0),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: KColors.surface,
      foregroundColor: KColors.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.syne(
        color: KColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: KColors.bg,
      selectedIconTheme: IconThemeData(color: KColors.amber, size: 20),
      unselectedIconTheme: IconThemeData(color: KColors.textMuted, size: 20),
      selectedLabelTextStyle: TextStyle(
        color: KColors.amber,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: KColors.textMuted,
        fontSize: 10,
      ),
      indicatorColor: KColors.amberDim,
      minWidth: 56,
      labelType: NavigationRailLabelType.all,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KColors.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: KColors.border2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: KColors.border2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: KColors.amber, width: 1.5),
      ),
      labelStyle: GoogleFonts.jetBrainsMono(
        color: KColors.textDim,
        fontSize: 12,
      ),
      hintStyle: GoogleFonts.jetBrainsMono(
        color: KColors.textMuted,
        fontSize: 12,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: KColors.amber,
        foregroundColor: KColors.onAccent,
        elevation: 0,
        textStyle: GoogleFonts.jetBrainsMono(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: KColors.textDim,
        side: BorderSide(color: KColors.border2),
        textStyle: GoogleFonts.jetBrainsMono(
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: KColors.amber,
        textStyle: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: KColors.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: KColors.textDim, size: 20),
    chipTheme: ChipThemeData(
      backgroundColor: KColors.surface2,
      labelStyle: GoogleFonts.jetBrainsMono(fontSize: 11, color: KColors.text),
      side: BorderSide(color: KColors.border2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    textTheme: interBase.copyWith(
      // Syne for all headings and titles
      displayLarge: GoogleFonts.syne(color: KColors.text, fontSize: 48),
      displayMedium: GoogleFonts.syne(color: KColors.text, fontSize: 40),
      displaySmall: GoogleFonts.syne(color: KColors.text, fontSize: 32),
      headlineLarge: GoogleFonts.syne(
        color: KColors.text,
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: GoogleFonts.syne(
        color: KColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: GoogleFonts.syne(
        color: KColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.syne(
        color: KColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.syne(
        color: KColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: GoogleFonts.syne(
        color: KColors.text,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      // Inter for body text — prose, descriptions, notes, narratives
      bodyLarge: GoogleFonts.inter(color: KColors.text, fontSize: 14),
      bodyMedium: GoogleFonts.inter(color: KColors.text, fontSize: 13),
      bodySmall: GoogleFonts.inter(color: KColors.textDim, fontSize: 12),
      // JetBrains Mono for labels — refs, status, metadata, compact UI text
      labelLarge: GoogleFonts.jetBrainsMono(
        color: KColors.text,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: GoogleFonts.jetBrainsMono(
        color: KColors.textDim,
        fontSize: 11,
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        color: KColors.textMuted,
        fontSize: 10,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: KColors.surface2,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(color: KColors.border2),
      ),
      textStyle: GoogleFonts.jetBrainsMono(color: KColors.text, fontSize: 12),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(KColors.surface2),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
            side: BorderSide(color: KColors.border2),
          ),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: KColors.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: KColors.border),
      ),
      titleTextStyle: GoogleFonts.syne(
        color: KColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: GoogleFonts.inter(color: KColors.text, fontSize: 13),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: KColors.surface2,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: KColors.border2),
      ),
      textStyle: GoogleFonts.jetBrainsMono(color: KColors.text, fontSize: 11),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(KColors.border2),
      radius: const Radius.circular(2),
      thickness: const WidgetStatePropertyAll(4),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: KColors.amber,
      labelColor: KColors.amber,
      unselectedLabelColor: KColors.textDim,
      labelStyle: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: GoogleFonts.jetBrainsMono(fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: KColors.surface2,
      contentTextStyle: GoogleFonts.inter(color: KColors.text, fontSize: 13),
    ),
  );
}
