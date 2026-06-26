// FILE: widgets/atmospheric_background.dart
// PURPOSE: A warm, breathing dark background widget with animated orbs.
// CONTEXT: Replaces standard black backgrounds with a soft atmosphere.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:eden/theme/eden_colors.dart';
import 'package:flutter/material.dart';

class AtmosphericBackground extends StatefulWidget {
  final Widget? child;

  const AtmosphericBackground({super.key, this.child});

  @override
  State<AtmosphericBackground> createState() => _AtmosphericBackgroundState();
}

class _AtmosphericBackgroundState extends State<AtmosphericBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: AtmosphericBackgroundPainter(progress: _controller.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class AtmosphericBackgroundPainter extends CustomPainter {
  final double progress;

  AtmosphericBackgroundPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint bgPaint = Paint()..color = EdenColors.edenVoid;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    final double maxDimension = math.max(w, h);

    final double angle1 = progress * 2.0 * math.pi;
    final Offset center1 = Offset(
      w * 0.15 + w * 0.08 * math.cos(angle1),
      h * 0.2 + h * 0.06 * math.sin(angle1),
    );
    final double radius1 = maxDimension * 0.85;
    final Paint paint1 = Paint()
      ..shader = ui.Gradient.radial(
        center1,
        radius1,
        [
          EdenColors.presenceBlue.withValues(
            alpha: 0.045 + 0.015 * math.sin(angle1),
          ),
          Colors.transparent,
        ],
      );
    canvas.drawCircle(center1, radius1, paint1);

    final double angle2 = (progress + 0.33) * 2.0 * math.pi;
    final Offset center2 = Offset(
      w * 0.85 + w * 0.06 * math.sin(angle2),
      h * 0.75 + h * 0.08 * math.cos(angle2),
    );
    final double radius2 = maxDimension * 0.95;
    final Paint paint2 = Paint()
      ..shader = ui.Gradient.radial(
        center2,
        radius2,
        [
          EdenColors.warmViolet.withValues(
            alpha: 0.035 + 0.012 * math.cos(angle2),
          ),
          Colors.transparent,
        ],
      );
    canvas.drawCircle(center2, radius2, paint2);

    final double angle3 = (progress + 0.66) * 2.0 * math.pi;
    final Offset center3 = Offset(
      w * 0.5 + w * 0.12 * math.cos(angle3),
      h * 0.9 + h * 0.04 * math.sin(angle3),
    );
    final double radius3 = maxDimension * 0.8;
    final Paint paint3 = Paint()
      ..shader = ui.Gradient.radial(
        center3,
        radius3,
        [
          EdenColors.humanWarmth.withValues(
            alpha: 0.025 + 0.01 * math.sin(angle3),
          ),
          Colors.transparent,
        ],
      );
    canvas.drawCircle(center3, radius3, paint3);
  }

  @override
  bool shouldRepaint(covariant AtmosphericBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
