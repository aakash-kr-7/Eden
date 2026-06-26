import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

// ignore: unused_import
import 'eden_colors.dart';

class GlassTheme {
  static const double cardOutlineIntensity = 0.5;
  static const double prominentOutlineIntensity = 0.7;
  static const double buttonOutlineIntensity = 0.3;

  static const LiquidGlassSettings card = LiquidGlassSettings(
    thickness: 18,
    blur: 12,
    glassColor: Color(0x18FFFFFF),
    saturation: 1.3,
    refractiveIndex: 1.45,
    lightIntensity: 1.3,
  );

  static const LiquidGlassSettings prominent = LiquidGlassSettings(
    thickness: 24,
    blur: 20,
    glassColor: Color(0x28FFFFFF),
    saturation: 1.4,
    refractiveIndex: 1.55,
    lightIntensity: 1.8,
  );

  static const LiquidGlassSettings button = LiquidGlassSettings(
    blur: 10,
    glassColor: Color(0x30FFFFFF),
    saturation: 1.1,
    lightIntensity: 1.0,
  );

  // Keep this runtime-created; some renderer builds reject this shape in const contexts.
  // ignore: prefer_const_constructors
  static final shape = LiquidRoundedSuperellipse(borderRadius: 30);
}
