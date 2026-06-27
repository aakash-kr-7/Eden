// FILE: components/app_background.dart
// PURPOSE: Shared animated background behind the active application flow.
// RESPONSIBILITIES: Render the app-wide ambient backdrop without owning screen state.
// NEVER: Contain navigation logic, user interaction flow, or backend calls.
import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF07080B),
                  Color(0xFF050608),
                  Color(0xFF000000),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -140,
          left: -120,
          child: _AtmosphereGlow(
            size: 360,
            colors: [
              Nocturne.accentRose.withValues(alpha: 0.22),
              Colors.transparent,
            ],
          ),
        ),
        Positioned(
          top: 80,
          right: -110,
          child: _AtmosphereGlow(
            size: 340,
            colors: [
              Nocturne.accentCool.withValues(alpha: 0.20),
              Colors.transparent,
            ],
          ),
        ),
        Positioned(
          bottom: -120,
          left: 20,
          child: _AtmosphereGlow(
            size: 300,
            colors: [
              Nocturne.accentWarm.withValues(alpha: 0.16),
              Colors.transparent,
            ],
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.02),
                  Colors.black.withValues(alpha: 0.16),
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AtmosphereGlow extends StatelessWidget {
  const _AtmosphereGlow({
    required this.size,
    required this.colors,
  });

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: colors,
          ),
        ),
      ),
    );
  }
}
