// FILE: theme/eden_colors.dart
// PURPOSE: Backward-compatible color aliases while Nocturne becomes the single source of truth.
// RESPONSIBILITIES: Forward legacy color references to Nocturne without owning design decisions.
// NEVER: Define independent palette values or diverge from Nocturne.
import 'package:flutter/material.dart';

import 'nocturne.dart';

class EdenColors {
  EdenColors._();

  static const Color black = Nocturne.black;
  static const Color edenVoid = Nocturne.bgPrimary;
  static const Color edenDepth = Nocturne.bgPrimary;
  static const Color edenSurface = Nocturne.bgSurface;
  static const Color edenElevated = Nocturne.bgElevated;
  static const Color deepPurple = Nocturne.bgSurface;

  static const Color edenIris = Nocturne.accentCool;
  static const Color edenIrisDim = Color(0x3398A7FF);
  static const Color edenIrisGlow = Color(0x6698A7FF);
  static const Color edenBlush = Nocturne.accentRose;
  static const Color edenGold = Nocturne.accentWarm;
  static const Color electricBlue = Nocturne.accentCool;
  static const Color orangeGlow = Nocturne.destructive;
  static const Color amberGlow = Nocturne.accentWarm;
  static const Color softGlow = Color(0x26FFFFFF);

  static const Color presenceBlue = Nocturne.accentCool;
  static const Color warmViolet = Nocturne.accentCool;
  static const Color humanWarmth = Nocturne.accentWarm;
  static const Color edenSage = Nocturne.success;

  static const Color textPrimary = Nocturne.textPrimary;
  static const Color textSecondary = Nocturne.textSecondary;
  static const Color textTertiary = Nocturne.textTertiary;
  static const Color textAccent = Nocturne.accentWarm;
  static const Color textPartner = Nocturne.textPrimary;

  static const Color glassLight = Color(0xCC111317);
  static const Color glassMedium = Color(0xDD171A1F);
  static const Color glassStrong = Color(0xF014171C);
  static const Color glassBorder = Nocturne.borderStrong;
  static const Color glassShimmer = Nocturne.borderSubtle;
  static const Color edenRim = Nocturne.borderSubtle;

  static const Color semanticError = Nocturne.destructive;
  static const Color semanticSuccess = Nocturne.success;
}
