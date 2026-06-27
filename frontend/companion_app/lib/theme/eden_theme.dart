// FILE: theme/eden_theme.dart
// PURPOSE: Backward-compatible theme aliases while Nocturne owns the design system.
// RESPONSIBILITIES: Forward legacy theme accessors to Nocturne.
// NEVER: Define an independent theme implementation.
import 'package:flutter/material.dart';

import 'nocturne.dart';

class EdenTheme {
  EdenTheme._();

  static const Color bgPrimary = Nocturne.bgPrimary;
  static const Color bgSurface = Nocturne.bgSurface;
  static const Color bgElevated = Nocturne.bgElevated;
  static const Color accentPrimary = Nocturne.accentCool;
  static const Color accentSecondary = Nocturne.accentWarm;
  static const Color textPrimary = Nocturne.textPrimary;
  static const Color textSecondary = Nocturne.textSecondary;
  static const Color textTertiary = Nocturne.textTertiary;
  static const Color destructive = Nocturne.destructive;
  static const Color success = Nocturne.success;

  static const String fontDisplay = Nocturne.fontDisplay;
  static const String fontBody = Nocturne.fontBody;

  static const TextStyle displayLarge = Nocturne.displayXl;
  static const TextStyle displayMedium = Nocturne.displayLg;
  static const TextStyle displaySmall = Nocturne.displayMd;
  static const TextStyle bodyLarge = Nocturne.bodyXl;
  static const TextStyle bodyMedium = Nocturne.bodyLg;
  static const TextStyle bodySmall = Nocturne.bodyMd;
  static const TextStyle labelMedium = Nocturne.label;

  static const TextStyle labelSmall = Nocturne.bodySm;
  static final TextStyle emphasisLarge =
      Nocturne.bodyXl.copyWith(fontWeight: FontWeight.w600);
  static final TextStyle emphasisMedium =
      Nocturne.bodyLg.copyWith(fontWeight: FontWeight.w600);

  static ThemeData dark() => Nocturne.theme;
  static ThemeData get themeData => Nocturne.theme;
}
