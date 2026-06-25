// ═══════════════════════════════════════════════════════════════════
// FILE: widgets/eden_logo.dart
// PURPOSE: The core Eden logo widget. An ancient, hand-drawn symbol.
// CONTEXT: Custom-painted organic seed shell and a breathing ember of presence.
//          Used in the Splash and Auth screens for immersive branding.
// ═══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/eden_colors.dart';

class EdenLogo extends StatefulWidget {
  final double size;
  final bool animateOnStart;
  final VoidCallback? onAnimationComplete;

  const EdenLogo({
    super.key,
    this.size = 100.0,
    this.animateOnStart = true,
    this.onAnimationComplete,
  });

  @override
  State<EdenLogo> createState() => _EdenLogoState();
}

class _EdenLogoState extends State<EdenLogo> with TickerProviderStateMixin {
  late final AnimationController _drawController;
  late final AnimationController _pulseController;
  late final Animation<double> _drawAnimation;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Draw animation: natural slow-down at the end (easeInOutCubic)
    _drawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _drawAnimation = CurvedAnimation(
      parent: _drawController,
      curve: Curves.easeInOutCubic,
    );

    // 2. Pulse animation: 3 seconds loop for the ambient breathing ember
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.animateOnStart) {
      _drawController.forward().then((_) {
        if (mounted) {
          widget.onAnimationComplete?.call();
          _pulseController.repeat(reverse: true);
        }
      });
    } else {
      _drawController.value = 1.0;
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _drawController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_drawAnimation, _pulseAnimation]),
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: EdenLogoPainter(
            drawProgress: _drawAnimation.value,
            pulseProgress: _pulseAnimation.value,
          ),
        );
      },
    );
  }
}

class EdenLogoPainter extends CustomPainter {
  final double drawProgress;
  final double pulseProgress;

  EdenLogoPainter({
    required this.drawProgress,
    required this.pulseProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double centerX = w / 2;
    final double centerY = h / 2;
    
    // Scale factor based on layout size
    final double R = math.min(w, h) / 2;

    // Draw parameters: organic, soft lines matching text primary
    final Paint linePaint = Paint()
      ..color = EdenColors.textPrimary.withValues(alpha: 0.85 * math.min(1.0, drawProgress * 1.5))
      ..style = PaintingStyle.stroke
      ..strokeWidth = R * 0.045 // dynamic stroke width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // --- Path 1: Left-hand crescent embrace ---
    final Path pathLeft = Path();
    pathLeft.moveTo(centerX - R * 0.05, centerY - R * 0.75);
    pathLeft.cubicTo(
      centerX - R * 0.65, centerY - R * 0.55,
      centerX - R * 0.70, centerY + R * 0.40,
      centerX + R * 0.02, centerY + R * 0.75,
    );

    // --- Path 2: Right-hand crescent embrace (asymmetric offset) ---
    final Path pathRight = Path();
    pathRight.moveTo(centerX + R * 0.08, centerY - R * 0.70);
    pathRight.cubicTo(
      centerX + R * 0.62, centerY - R * 0.48,
      centerX + R * 0.68, centerY + R * 0.45,
      centerX - R * 0.08, centerY + R * 0.80,
    );

    // --- Draw Paths with Staggered Metric Extraction ---
    // Left draws first (0.0 to 0.7 progress), Right draws overlapping (0.3 to 1.0 progress)
    final double progressLeft = (drawProgress / 0.7).clamp(0.0, 1.0);
    final double progressRight = ((drawProgress - 0.3) / 0.7).clamp(0.0, 1.0);

    if (progressLeft > 0) {
      _drawAnimatedPath(canvas, pathLeft, linePaint, progressLeft);
    }

    if (progressRight > 0) {
      _drawAnimatedPath(canvas, pathRight, linePaint, progressRight);
    }

    // --- Draw Inner Breathing Ember (representing quiet presence) ---
    // Appears softly when drawing is half-complete
    final double emberOpacity = ((drawProgress - 0.5) / 0.5).clamp(0.0, 1.0);
    if (emberOpacity > 0) {
      final Offset emberCenter = Offset(centerX, centerY - R * 0.05);

      // 1. Soft diffused outer glow (iris-glow tint)
      final double glowRadius = R * (0.22 + 0.04 * pulseProgress);
      final Paint glowPaint = Paint()
        ..color = EdenColors.edenIrisGlow.withValues(alpha: 0.4 * emberOpacity * (0.5 + 0.5 * pulseProgress))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, R * 0.08);
      canvas.drawCircle(emberCenter, glowRadius, glowPaint);

      // 2. Core glowing point (human warmth)
      final double coreRadius = R * (0.075 + 0.015 * pulseProgress);
      final Paint corePaint = Paint()
        ..color = EdenColors.edenBlush.withValues(alpha: emberOpacity * (0.75 + 0.25 * pulseProgress));
      canvas.drawCircle(emberCenter, coreRadius, corePaint);
    }
  }

  void _drawAnimatedPath(Canvas canvas, Path path, Paint paint, double progress) {
    if (progress >= 1.0) {
      canvas.drawPath(path, paint);
      return;
    }
    
    final Path animatedPath = Path();
    for (final PathMetric metric in path.computeMetrics()) {
      final double extractLength = metric.length * progress;
      animatedPath.addPath(
        metric.extractPath(0.0, extractLength),
        Offset.zero,
      );
    }
    canvas.drawPath(animatedPath, paint);
  }

  @override
  bool shouldRepaint(covariant EdenLogoPainter oldDelegate) {
    return oldDelegate.drawProgress != drawProgress ||
        oldDelegate.pulseProgress != pulseProgress;
  }
}
