import 'package:flutter/material.dart';

class EdenTheme {
  EdenTheme._();

  // --- Design System Colors ---
  static const Color bgPrimary = Color(0xFF0A0A0F);
  static const Color bgSurface = Color(0xFF13131A);
  static const Color bgElevated = Color(0xFF1C1C26);
  static const Color accentPrimary = Color(0xFF7B6EF6);
  static const Color accentSecondary = Color(0xFFC4A882);
  static const Color textPrimary = Color(0xFFF0EEF8);
  static const Color textSecondary = Color(0xFF8A8799);
  static const Color textTertiary = Color(0xFF4A4858);
  static const Color destructive = Color(0xFFE05454);
  static const Color success = Color(0xFF4EAF7A);

  // --- Font Families ---
  static const String fontDisplay = 'CormorantGaramond';
  static const String fontBody = 'PlusJakartaSans';

  // --- TextStyles ---
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 38,
    fontWeight: FontWeight.w300,
    color: textPrimary,
    letterSpacing: -0.5,
    height: 1.15,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 30,
    fontWeight: FontWeight.w300,
    color: textPrimary,
    letterSpacing: -0.3,
    height: 1.2,
  );

  static const TextStyle displaySmall = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 24,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    letterSpacing: -0.2,
    height: 1.25,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontBody,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontBody,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.45,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontBody,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.4,
  );

  static const TextStyle emphasisLarge = TextStyle(
    fontFamily: fontBody,
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    height: 1.4,
  );

  static const TextStyle emphasisMedium = TextStyle(
    fontFamily: fontBody,
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: textPrimary,
    height: 1.35,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: fontBody,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    letterSpacing: 0.5,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontBody,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: textTertiary,
    letterSpacing: 1.0,
  );

  // --- ThemeData ---
  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      cardColor: bgSurface,
      dialogTheme: const DialogThemeData(
        backgroundColor: bgSurface,
      ),
      primaryColor: accentPrimary,
      colorScheme: const ColorScheme.dark(
        primary: accentPrimary,
        secondary: accentSecondary,
        surface: bgSurface,
        onPrimary: textPrimary,
        onSecondary: textPrimary,
        onSurface: textPrimary,
        error: destructive,
      ),
      textTheme: const TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        displaySmall: displaySmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: accentPrimary,
        selectionColor: Color(0x4D7B6EF6),
        selectionHandleColor: accentPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgPrimary,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: displaySmall,
      ),
      dividerTheme: const DividerThemeData(
        color: bgElevated,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
