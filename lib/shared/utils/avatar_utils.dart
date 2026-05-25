import 'package:flutter/material.dart';

/// Returns up to two upper-case letters representing the person's initials.
///
///   "Paul Murray"        -> "PM"
///   "alice"              -> "AL"
///   "Mary-Jane Smith"    -> "MS"
///   "O'Connor"           -> "OC"
///   ""                   -> "?"
String initialsFromName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';

  final words = trimmed
      .split(RegExp(r"\s+"))
      .where((w) => w.isNotEmpty)
      .toList();

  if (words.length >= 2) {
    final a = _firstLetter(words.first);
    final b = _firstLetter(words[1]);
    if (a != null && b != null) return '$a$b'.toUpperCase();
  }
  if (words.length == 1) {
    final letters = words.first.replaceAll(RegExp(r"[^A-Za-z]"), '');
    if (letters.length >= 2) {
      return letters.substring(0, 2).toUpperCase();
    }
    if (letters.length == 1) {
      return letters.toUpperCase();
    }
  }
  return '?';
}

String? _firstLetter(String word) {
  for (final r in word.runes) {
    final ch = String.fromCharCode(r);
    if (RegExp(r"[A-Za-z]").hasMatch(ch)) return ch;
  }
  return null;
}

/// Deterministic muted hue derived from the name. Same name → same colour.
Color colorFromName(String name) {
  final src = name.trim().toLowerCase();
  if (src.isEmpty) return const Color(0xFF607d94);
  var hash = 0;
  for (final c in src.codeUnits) {
    hash = (hash * 31 + c) & 0xffffffff;
  }
  final hue = (hash.abs() % 360).toDouble();
  return HSLColor.fromAHSL(1.0, hue, 0.42, 0.58).toColor();
}
