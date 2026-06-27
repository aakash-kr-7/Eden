// FILE: components/glass.dart
// PURPOSE: Stable local surface primitives for shared frontend presentation.
// RESPONSIBILITIES: Provide reusable panel, shape, and halo primitives for screens and components.
// NEVER: Contain app routing, provider logic, or backend/service behavior.
import 'dart:ui';

import 'package:flutter/material.dart';

class LiquidGlassSettings {
  const LiquidGlassSettings({
    this.thickness = 0,
    this.blur = 0,
    this.glassColor = const Color(0xCC111317),
    this.saturation = 1,
    this.refractiveIndex = 1,
    this.lightIntensity = 1,
  });

  final double thickness;
  final double blur;
  final Color glassColor;
  final double saturation;
  final double refractiveIndex;
  final double lightIntensity;
}

abstract class GlassShape {
  const GlassShape();

  BorderRadius get clipBorderRadius;
}

class LiquidRoundedSuperellipse extends GlassShape {
  const LiquidRoundedSuperellipse({required this.borderRadius});

  final double borderRadius;

  @override
  BorderRadius get clipBorderRadius => BorderRadius.circular(borderRadius);
}

class LiquidOval extends GlassShape {
  const LiquidOval();

  @override
  BorderRadius get clipBorderRadius => BorderRadius.circular(999);
}

class FakeGlass extends StatelessWidget {
  const FakeGlass({
    super.key,
    required this.shape,
    required this.settings,
    required this.child,
  });

  final GlassShape shape;
  final LiquidGlassSettings settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderOpacity =
        (0.12 + (settings.lightIntensity * 0.03)).clamp(0.10, 0.18).toDouble();
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: settings.glassColor,
        borderRadius: shape.clipBorderRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: borderOpacity),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: settings.blur + 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );

    final blurred = settings.blur <= 0
        ? content
        : BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: settings.blur / 2,
              sigmaY: settings.blur / 2,
            ),
            child: content,
          );

    return ClipRRect(
      borderRadius: shape.clipBorderRadius,
      child: blurred,
    );
  }
}

class GlassGlow extends StatelessWidget {
  const GlassGlow({
    super.key,
    required this.glowColor,
    required this.child,
    this.glowRadius = 1,
  });

  final Color glowColor;
  final double glowRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.12),
            blurRadius: 18 * glowRadius,
            spreadRadius: 0.5 * glowRadius,
          ),
        ],
      ),
      child: child,
    );
  }
}

class LiquidGlassLayer extends StatelessWidget {
  const LiquidGlassLayer({
    super.key,
    required this.child,
    this.settings,
  });

  final Widget child;
  final LiquidGlassSettings? settings;

  @override
  Widget build(BuildContext context) => child;
}

class LiquidGlass {
  const LiquidGlass._();

  static Widget withOwnLayer({
    Key? key,
    required GlassShape shape,
    required LiquidGlassSettings settings,
    required Widget child,
  }) {
    return FakeGlass(
      key: key,
      shape: shape,
      settings: settings,
      child: child,
    );
  }
}
