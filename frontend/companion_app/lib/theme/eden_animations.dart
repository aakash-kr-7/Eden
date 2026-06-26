// ═══════════════════════════════════════════════════════════════════
// FILE: theme/eden_animations.dart
// PURPOSE: Animation durations, curves, and reusable animated widget builders.
// CONTEXT: Used throughout the app for consistent motion design.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'eden_colors.dart';

class EdenAnimations {
  EdenAnimations._();

  // ─── Durations ─────────────────────────────────────────────────────
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration standard = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration breath = Duration(milliseconds: 800);

  // ─── Curves ────────────────────────────────────────────────────────
  static const Curve snap = Curves.easeOut;
  static const Curve smooth = Curves.easeInOut;
  static const Curve spring = Curves.elasticOut;
  static const Curve gentle = Curves.decelerate;
}

// ─── Reusable FadeSlideIn Widget ────────────────────────────────────
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double offsetY;
  final Curve curve;
  final Duration delay;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = EdenAnimations.standard,
    this.offsetY = 8.0,
    this.curve = EdenAnimations.gentle,
    this.delay = Duration.zero,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _translationAnimation;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _translationAnimation =
        Tween<double>(begin: widget.offsetY, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.translate(
            offset: Offset(0.0, _translationAnimation.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ─── Reusable PulseAnimation Widget ──────────────────────────────────
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double scaleFactor;
  final bool active;

  const PulseAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    this.scaleFactor = 0.04,
    this.active = true,
  });

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0 + widget.scaleFactor)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0 + widget.scaleFactor, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50.0,
      ),
    ]).animate(_controller);

    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant PulseAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0.0;
      }
    }
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
        return Transform.scale(
          scale: widget.active ? _scaleAnimation.value : 1.0,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─── Reusable BreathingBackground Widget ─────────────────────────────
class BreathingBackground extends StatefulWidget {
  final Widget? child;
  final Color baseColor;

  const BreathingBackground({
    super.key,
    this.child,
    this.baseColor = EdenColors.edenDepth,
  });

  @override
  State<BreathingBackground> createState() => _BreathingBackgroundState();
}

class _BreathingBackgroundState extends State<BreathingBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
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
          painter: _AtmosphericPainter(
            progress: _controller.value,
            baseColor: widget.baseColor,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _AtmosphericPainter extends CustomPainter {
  final double progress;
  final Color baseColor;

  _AtmosphericPainter({
    required this.progress,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw base deep background
    final paintBase = Paint()..color = baseColor;
    canvas.drawRect(Offset.zero & size, paintBase);

    // Coordinate shift (2-3px movement drift)
    final double offsetVal = progress * 3.0;

    // 2. Presence Blue Orb (Top Left)
    final double blueOpacity = 0.04 + (progress * 0.02);
    final paintBlue = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.8, -0.8),
        colors: [
          EdenColors.presenceBlue.withValues(alpha: blueOpacity),
          Colors.transparent,
        ],
        radius: 1.2,
      ).createShader(Offset.zero & size);

    canvas.save();
    canvas.translate(-offsetVal, offsetVal);
    canvas.drawRect(Offset.zero & size, paintBlue);
    canvas.restore();

    // 3. Warm Violet Orb (Bottom Right)
    final double violetOpacity = 0.04 + ((1.0 - progress) * 0.02);
    final paintViolet = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.8, 0.8),
        colors: [
          EdenColors.warmViolet.withValues(alpha: violetOpacity),
          Colors.transparent,
        ],
        radius: 1.2,
      ).createShader(Offset.zero & size);

    canvas.save();
    canvas.translate(offsetVal, -offsetVal);
    canvas.drawRect(Offset.zero & size, paintViolet);
    canvas.restore();

    // 4. Human Warmth Orb (Bottom Center)
    final double warmthOpacity = 0.02 + (progress * 0.015);
    final paintWarmth = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, 1.0),
        colors: [
          EdenColors.humanWarmth.withValues(alpha: warmthOpacity),
          Colors.transparent,
        ],
        radius: 1.0,
      ).createShader(Offset.zero & size);

    canvas.save();
    canvas.translate(0, -offsetVal * 0.5);
    canvas.drawRect(Offset.zero & size, paintWarmth);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AtmosphericPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.baseColor != baseColor;
  }
}
