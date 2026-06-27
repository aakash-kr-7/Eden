// FILE: theme/nocturne.dart
// PURPOSE: Define the complete Nocturne design language for the frontend.
// RESPONSIBILITIES: Centralize color, type, spacing, motion, radius, icon, elevation, and surface rules.
// NEVER: Contain feature state, routing logic, or backend behavior.
import 'package:flutter/material.dart';

import '../components/glass.dart';

class Nocturne {
  Nocturne._();

  static const String fontDisplay = 'CormorantGaramond';
  static const String fontBody = 'PlusJakartaSans';

  static const Color black = Color(0xFF000000);
  static const Color bgPrimary = Color(0xFF050608);
  static const Color bgSurface = Color(0xFF111317);
  static const Color bgElevated = Color(0xFF171A1F);
  static const Color bgOverlay = Color(0xE6111317);

  static const Color accentCool = Color(0xFF98A7FF);
  static const Color accentWarm = Color(0xFFD8C2A3);
  static const Color accentRose = Color(0xFFB78A8D);

  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFF99A1AE);
  static const Color textTertiary = Color(0xFF6C7380);

  static const Color borderSubtle = Color(0x1FFFFFFF);
  static const Color borderStrong = Color(0x2EFFFFFF);
  static const Color success = Color(0xFF7BC099);
  static const Color destructive = Color(0xFFDC786D);

  static const double space2 = 4;
  static const double space3 = 8;
  static const double space4 = 12;
  static const double space5 = 16;
  static const double space6 = 20;
  static const double space7 = 24;
  static const double space8 = 32;
  static const double space9 = 40;

  static const double radiusSm = 14;
  static const double radiusMd = 18;
  static const double radiusLg = 24;
  static const double radiusXl = 28;
  static const double radiusPill = 999;

  static const double iconXs = 14;
  static const double iconSm = 16;
  static const double iconMd = 18;
  static const double iconLg = 20;
  static const double iconXl = 24;
  static const double iconHero = 44;

  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationStandard = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);
  static const Duration durationSettled = Duration(milliseconds: 600);
  static const Duration durationCinematic = Duration(milliseconds: 600);
  static const Duration durationAmbient = Duration(milliseconds: 600);

  static const LinearGradient heroAccent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      accentWarm,
      accentCool,
    ],
  );

  static final List<BoxShadow> elevationLow = [
    BoxShadow(
      color: black.withValues(alpha: 0.18),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static final List<BoxShadow> elevationMedium = [
    BoxShadow(
      color: black.withValues(alpha: 0.22),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];

  static final List<BoxShadow> elevationHigh = [
    BoxShadow(
      color: black.withValues(alpha: 0.28),
      blurRadius: 36,
      offset: const Offset(0, 18),
    ),
  ];

  static const LiquidGlassSettings surfaceCard = LiquidGlassSettings(
    blur: 8,
    glassColor: Color(0xCC111317),
    lightIntensity: 0.45,
  );

  static const LiquidGlassSettings surfaceProminent = LiquidGlassSettings(
    blur: 10,
    glassColor: Color(0xDD171A1F),
    lightIntensity: 0.6,
  );

  static const LiquidGlassSettings surfaceInteractive = LiquidGlassSettings(
    blur: 6,
    glassColor: Color(0xF014171C),
    lightIntensity: 0.7,
  );

  static const LiquidRoundedSuperellipse panelShape =
      LiquidRoundedSuperellipse(borderRadius: radiusXl);

  static const TextStyle displayXl = TextStyle(
    fontFamily: fontDisplay,
    fontWeight: FontWeight.w400,
    fontSize: 46,
    height: 1.06,
    letterSpacing: -0.8,
    color: textPrimary,
  );

  static const TextStyle displayLg = TextStyle(
    fontFamily: fontDisplay,
    fontWeight: FontWeight.w400,
    fontSize: 34,
    height: 1.08,
    letterSpacing: -0.6,
    color: textPrimary,
  );

  static const TextStyle displayMd = TextStyle(
    fontFamily: fontDisplay,
    fontWeight: FontWeight.w400,
    fontSize: 28,
    height: 1.1,
    letterSpacing: -0.4,
    color: textPrimary,
  );

  static const TextStyle bodyXl = TextStyle(
    fontFamily: fontBody,
    fontWeight: FontWeight.w400,
    fontSize: 18,
    height: 1.45,
    letterSpacing: -0.1,
    color: textPrimary,
  );

  static const TextStyle bodyLg = TextStyle(
    fontFamily: fontBody,
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 1.45,
    letterSpacing: -0.1,
    color: textPrimary,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: fontBody,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.45,
    letterSpacing: 0,
    color: textPrimary,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: fontBody,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 1.4,
    letterSpacing: 0.2,
    color: textSecondary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontBody,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    height: 1.2,
    letterSpacing: 0.5,
    color: textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontFamily: fontBody,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    height: 1.2,
    letterSpacing: -0.1,
    color: textPrimary,
  );

  static ThemeData get theme {
    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusXl),
      borderSide: const BorderSide(
        color: borderSubtle,
        width: 1,
      ),
    );

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      canvasColor: bgPrimary,
      cardColor: bgSurface,
      dialogTheme: const DialogThemeData(
        backgroundColor: bgSurface,
      ),
      primaryColor: accentCool,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: accentCool,
        secondary: accentWarm,
        surface: bgSurface,
        onPrimary: black,
        onSecondary: black,
        onSurface: textPrimary,
        error: destructive,
      ),
      textTheme: const TextTheme(
        displayLarge: displayXl,
        displayMedium: displayLg,
        displaySmall: displayMd,
        bodyLarge: bodyXl,
        bodyMedium: bodyLg,
        bodySmall: bodyMd,
        labelMedium: label,
        labelSmall: bodySm,
      ),
      iconTheme: const IconThemeData(
        color: textPrimary,
        size: iconLg,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: accentCool,
        selectionColor: Color(0x3398A7FF),
        selectionHandleColor: accentCool,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        titleTextStyle: displayMd,
        iconTheme: IconThemeData(
          color: textPrimary,
          size: iconMd,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space6,
          vertical: space5,
        ),
        hintStyle: bodyLg.copyWith(color: textTertiary),
        labelStyle: bodyMd.copyWith(color: textSecondary),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        disabledBorder: outlineBorder.copyWith(
          borderSide: const BorderSide(color: borderSubtle, width: 1),
        ),
        focusedBorder: outlineBorder.copyWith(
          borderSide: const BorderSide(color: borderStrong, width: 1),
        ),
        errorBorder: outlineBorder.copyWith(
          borderSide: const BorderSide(color: destructive, width: 1),
        ),
        focusedErrorBorder: outlineBorder.copyWith(
          borderSide: const BorderSide(color: destructive, width: 1),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      dividerTheme: const DividerThemeData(
        color: borderSubtle,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
