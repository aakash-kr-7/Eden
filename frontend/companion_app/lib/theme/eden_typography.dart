// ═══════════════════════════════════════════════════════════════════
// FILE: theme/eden_typography.dart
// PURPOSE: All text styles for Eden. Font families, sizes, weights, tracking.
// CONTEXT: Used by eden_theme.dart and directly in widgets.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'eden_colors.dart';

class EdenTypography {
  EdenTypography._();

  static const String _fontDisplay = 'CormorantGaramond';
  static const String _fontBody = 'PlusJakartaSans';

  // ─── Display Styles (Cormorant Garamond Light) ─────────────────────
  static const TextStyle displayXl = TextStyle(
    fontFamily: _fontDisplay,
    fontWeight: FontWeight.w300,
    fontSize: 48.0,
    letterSpacing: -0.5,
    color: EdenColors.textPrimary,
    height: 1.12,
  );

  static const TextStyle displayLg = TextStyle(
    fontFamily: _fontDisplay,
    fontWeight: FontWeight.w300,
    fontSize: 36.0,
    letterSpacing: -0.5,
    color: EdenColors.textPrimary,
    height: 1.12,
  );

  static const TextStyle displayMd = TextStyle(
    fontFamily: _fontDisplay,
    fontWeight: FontWeight.w300,
    fontSize: 28.0,
    letterSpacing: 0.0,
    color: EdenColors.textPrimary,
    height: 1.15,
  );

  // ─── Body Styles (Plus Jakarta Sans Regular) ───────────────────────
  static const TextStyle bodyXl = TextStyle(
    fontFamily: _fontBody,
    fontWeight: FontWeight.w400,
    fontSize: 18.0,
    letterSpacing: 0.0,
    color: EdenColors.textPrimary,
    height: 1.45,
  );

  static const TextStyle bodyLg = TextStyle(
    fontFamily: _fontBody,
    fontWeight: FontWeight.w400,
    fontSize: 16.0,
    letterSpacing: 0.0,
    color: EdenColors.textPrimary,
    height: 1.45,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: _fontBody,
    fontWeight: FontWeight.w400,
    fontSize: 14.0,
    letterSpacing: 0.0,
    color: EdenColors.textPrimary,
    height: 1.45,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: _fontBody,
    fontWeight: FontWeight.w400,
    fontSize: 12.0,
    letterSpacing: 0.2,
    color: EdenColors.textSecondary,
    height: 1.45,
  );

  // ─── Eyebrow / Tag Styles (Plus Jakarta Sans Bold) ─────────────────
  static const TextStyle label = TextStyle(
    fontFamily: _fontBody,
    fontWeight: FontWeight.w700,
    fontSize: 13.0,
    letterSpacing: 0.5,
    color: EdenColors.edenIris,
    height: 1.2,
  );

  static const TextStyle button = TextStyle(
    fontFamily: _fontBody,
    fontWeight: FontWeight.w700,
    fontSize: 15.0,
    letterSpacing: 0.3,
    color: EdenColors.textPrimary,
    height: 1.2,
  );
}
