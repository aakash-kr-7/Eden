import 'package:flutter/material.dart';

class EdenColors {
  EdenColors._();

  // Core brand palette
  static const Color black = Color(0xFF050507);
  static const Color edenVoid = Color(0xFF070711);
  static const Color edenDepth = Color(0xFF100D26);
  static const Color edenSurface = Color(0xFF18132F);
  static const Color edenElevated = Color(0xFF22183F);
  static const Color deepPurple = Color(0xFF2D0B4E);

  static const Color edenIris = Color(0xFF8B5CF6);
  static const Color edenIrisDim = Color(0x338B5CF6);
  static const Color edenIrisGlow = Color(0x668B5CF6);
  static const Color edenBlush = Color(0xFFFF7C91);
  static const Color edenGold = Color(0xFFFFD18A);
  static const Color electricBlue = Color(0xFF00E5FF);
  static const Color orangeGlow = Color(0xFFFF6D00);
  static const Color amberGlow = Color(0xFFFFAB00);
  static const Color softGlow = Color(0x40FFFFFF);

  // Atmospheric accents
  static const Color presenceBlue = Color(0xFF55D6FF);
  static const Color warmViolet = Color(0xFFA778FF);
  static const Color humanWarmth = Color(0xFFFF9B80);
  static const Color edenSage = Color(0xFF9AD9B5);

  // Text
  static const Color textPrimary = Color(0xFFF8F5FF);
  static const Color textSecondary = Color(0xB8F8F5FF);
  static const Color textTertiary = Color(0x73F8F5FF);
  static const Color textAccent = edenGold;
  static const Color textPartner = Color(0xFFEDE4FF);

  // Glass
  static const Color glassLight = Color(0x14FFFFFF);
  static const Color glassMedium = Color(0x24FFFFFF);
  static const Color glassStrong = Color(0x36FFFFFF);
  static const Color glassBorder = Color(0x26FFFFFF);
  static const Color glassShimmer = Color(0x45FFFFFF);
  static const Color edenRim = glassBorder;

  // Semantics
  static const Color semanticError = Color(0xFFFF6B86);
  static const Color semanticSuccess = Color(0xFF79E6A3);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      edenVoid,
      edenDepth,
      deepPurple,
      edenSurface,
      black,
    ],
    stops: [0.0, 0.28, 0.55, 0.78, 1.0],
  );

  static const LinearGradient logoGlowGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      edenGold,
      edenBlush,
      edenIris,
    ],
  );
}
