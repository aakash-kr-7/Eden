// ═══════════════════════════════════════════════════════════════════
// FILE: theme/eden_theme.dart
// PURPOSE: MaterialApp ThemeData for Eden. Dark theme only.
// CONTEXT: Passed to MaterialApp.theme in main.dart.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'eden_colors.dart';
import 'eden_typography.dart';

class EdenTheme {
  EdenTheme._();

  // ─── Color Bridges for Legacy Code Compatibility ──────────────────
  static const Color bgPrimary = EdenColors.edenVoid;
  static const Color bgSurface = EdenColors.edenSurface;
  static const Color bgElevated = EdenColors.edenElevated;
  static const Color accentPrimary = EdenColors.edenIris;
  static const Color accentSecondary = EdenColors.edenGold;
  static const Color textPrimary = EdenColors.textPrimary;
  static const Color textSecondary = EdenColors.textSecondary;
  static const Color textTertiary = EdenColors.textTertiary;
  static const Color destructive = EdenColors.semanticError;
  static const Color success = EdenColors.semanticSuccess;

  // ─── Font Families ────────────────────────────────────────────────
  static const String fontDisplay = 'CormorantGaramond';
  static const String fontBody = 'PlusJakartaSans';

  // ─── Typography Bridges for Legacy Code Compatibility ─────────────
  static const TextStyle displayLarge = EdenTypography.displayXl;
  static const TextStyle displayMedium = EdenTypography.displayLg;
  static const TextStyle displaySmall = EdenTypography.displayMd;
  static const TextStyle bodyLarge = EdenTypography.bodyXl;
  static const TextStyle bodyMedium = EdenTypography.bodyLg;
  static const TextStyle bodySmall = EdenTypography.bodyMd;
  static const TextStyle labelMedium = EdenTypography.label;
  
  static final TextStyle labelSmall = EdenTypography.bodySm.copyWith(
    color: EdenColors.textTertiary,
    letterSpacing: 1.0,
  );

  static final TextStyle emphasisLarge = EdenTypography.bodyXl.copyWith(
    fontWeight: FontWeight.bold,
  );

  static final TextStyle emphasisMedium = EdenTypography.bodyLg.copyWith(
    fontWeight: FontWeight.bold,
  );

  static ThemeData dark() => themeData;

  // ─── MaterialApp Dark ThemeData ───────────────────────────────────
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: EdenColors.edenDepth,
      cardColor: EdenColors.edenSurface,
      dialogTheme: const DialogThemeData(
        backgroundColor: EdenColors.edenSurface,
      ),
      primaryColor: EdenColors.edenIris,
      colorScheme: const ColorScheme.dark(
        primary: EdenColors.edenIris,
        secondary: EdenColors.edenIris,
        surface: EdenColors.edenSurface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: EdenColors.textPrimary,
        error: EdenColors.semanticError,
      ),
      // Apply the typography scale to textTheme
      textTheme: const TextTheme(
        displayLarge: EdenTypography.displayXl,
        displayMedium: EdenTypography.displayLg,
        displaySmall: EdenTypography.displayMd,
        bodyLarge: EdenTypography.bodyXl,
        bodyMedium: EdenTypography.bodyLg,
        bodySmall: EdenTypography.bodyMd,
        labelMedium: EdenTypography.label,
        labelSmall: EdenTypography.bodySm,
      ),
      // No Material ripple on most surfaces by default
      splashFactory: NoSplash.splashFactory,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: EdenColors.edenIris,
        selectionColor: EdenColors.edenIrisDim,
        selectionHandleColor: EdenColors.edenIris,
      ),
      // AppBar defaults removed (we construct custom floating appbars/headers)
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        shadowColor: Colors.transparent,
        iconTheme: IconThemeData(color: EdenColors.textPrimary),
        titleTextStyle: EdenTypography.displayMd,
      ),
      // Custom input decoration defaults (no default underlines)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EdenColors.edenElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
        hintStyle: EdenTypography.bodyXl.copyWith(color: EdenColors.textTertiary),
        labelStyle: EdenTypography.bodyLg.copyWith(color: EdenColors.textSecondary),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: EdenColors.edenIrisDim, width: 1.0),
          borderRadius: BorderRadius.circular(28.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: EdenColors.edenRim, width: 1.0),
          borderRadius: BorderRadius.circular(28.0),
        ),
        disabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: EdenColors.edenRim.withValues(alpha: 0.5), width: 1.0),
          borderRadius: BorderRadius.circular(28.0),
        ),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: EdenColors.edenRim, width: 1.0),
          borderRadius: BorderRadius.circular(28.0),
        ),
      ),
      // Fade transition on routes everywhere
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      dividerTheme: const DividerThemeData(
        color: EdenColors.edenRim,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
