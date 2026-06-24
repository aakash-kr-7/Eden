// ═══════════════════════════════════════════════════════════════════
// FILE: theme/eden_colors.dart
// PURPOSE: Complete Eden color system. Every color used in the app lives here.
// CONTEXT: Imported by eden_theme.dart and any widget needing color access.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class EdenColors {
  EdenColors._();

  // ─── EdenBase (Backgrounds) ────────────────────────────────────────
  static const Color edenVoid = Color(0xFF07070E);
  static const Color edenDepth = Color(0xFF0D0D1A);
  static const Color edenSurface = Color(0xFF13131F);
  static const Color edenElevated = Color(0xFF1A1A2E);
  static const Color edenRim = Color(0xFF252538);

  // ─── EdenGlass (The Core Aesthetic) ────────────────────────────────
  static const Color glassLight = Color(0x0AFFFFFF);      // rgba(255, 255, 255, 0.04)
  static const Color glassMedium = Color(0x12FFFFFF);     // rgba(255, 255, 255, 0.07)
  static const Color glassStrong = Color(0x1CFFFFFF);     // rgba(255, 255, 255, 0.11)
  static const Color glassBorder = Color(0x14FFFFFF);     // rgba(255, 255, 255, 0.08)
  static const Color glassShimmer = Color(0x26FFFFFF);    // rgba(255, 255, 255, 0.15)

  // ─── EdenAccent Palette (Diffused, Never Vivid) ────────────────────
  static const Color edenIris = Color(0xFFA594F9);
  static const Color edenIrisDim = Color(0x1EA594F9);     // rgba(165, 148, 249, 0.12)
  static const Color edenIrisGlow = Color(0x40A594F9);    // rgba(165, 148, 249, 0.25)
  static const Color edenBlush = Color(0xFFF4A7B9);
  static const Color edenBlushDim = Color(0x1EF4A7B9);    // rgba(244, 167, 185, 0.12)
  static const Color edenBlushGlow = Color(0x33F4A7B9);   // rgba(244, 167, 185, 0.20)
  static const Color edenSage = Color(0xFF94C9B0);
  static const Color edenSageDim = Color(0x1E94C9B0);     // rgba(148, 201, 176, 0.12)
  static const Color edenSageGlow = Color(0x3394C9B0);    // rgba(148, 201, 176, 0.20)
  static const Color edenGold = Color(0xFFE8C98A);
  static const Color edenGoldDim = Color(0x1EE8C98A);    // rgba(232, 201, 138, 0.12)

  // ─── Sol Atmospheric Orbs (Breathing Backgrounds) ─────────────────
  static const Color presenceBlue = Color(0xFF7DA2FF);   // presence blue - emotional core
  static const Color warmViolet = Color(0xFFA78BFA);    // warm violet - vulnerability
  static const Color humanWarmth = Color(0xFFF2B8A0);   // human warmth - subtle

  // ─── EdenText ──────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0EDF8);
  static const Color textSecondary = Color(0xFF9895AE);
  static const Color textTertiary = Color(0xFF514F6B);
  static const Color textAccent = Color(0xFFA594F9);
  static const Color textPartner = Color(0xFFE8E5F5);

  // ─── EdenSemantic ──────────────────────────────────────────────────
  static const Color semanticError = Color(0xFFE87676);
  static const Color semanticSuccess = Color(0xFF7ECBA1);
}
