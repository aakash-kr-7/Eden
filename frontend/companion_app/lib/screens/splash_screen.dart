// ═══════════════════════════════════════════════════════════════════
// FILE: screens/splash_screen.dart
// PURPOSE: Cinematic Eden splash. Particles orbit inward → logo forms
//          → ambient glow pulses → logo blooms out → routes to auth/chat.
// DURATION: ~4s total. No skip. Single AnimationController driving
//           all phases via Interval curves.
// ═══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../theme/eden_colors.dart';

// ─── Timing constants (all in 0.0–1.0 of a 4000ms controller) ───────
// Phase 1 — vortex particles spiral in:       0.00 → 0.30  (0–1200ms)
// Phase 2 — logo materialises:                0.25 → 0.50  (1000–2000ms)  [overlaps for smoothness]
// Phase 3 — ambient glow breathes:            0.50 → 0.80  (2000–3200ms)
// Phase 4 — logo blooms + dissolves out:      0.80 → 1.00  (3200–4000ms)
// ─────────────────────────────────────────────────────────────────────

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // ── Phase 1: particle vortex ──────────────────────────────────────
  late final Animation<double>
      _particleProgress; // 0→1 drives orbit + convergence

  // ── Phase 2: logo materialise ────────────────────────────────────
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;

  // ── Phase 3: ambient glow ────────────────────────────────────────
  late final Animation<double>
      _glowPulse; // oscillates via sin, driven by controller

  // ── Phase 4: bloom exit ──────────────────────────────────────────
  late final Animation<double> _exitScale;
  late final Animation<double> _exitOpacity;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    // Phase 1
    _particleProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.00, 0.30, curve: Curves.easeIn),
    );

    // Phase 2
    _logoOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.25, 0.50, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.25, 0.50, curve: Curves.easeOutCubic),
      ),
    );

    // Phase 3 — raw controller value passed to painter for sin pulse
    _glowPulse = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.50, 0.80, curve: Curves.easeInOut),
    );

    // Phase 4
    _exitScale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.80, 1.00, curve: Curves.easeIn),
      ),
    );
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.82, 1.00, curve: Curves.easeIn),
      ),
    );

    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_hasNavigated) {
        _navigate();
      }
    });

    _ctrl.forward();
  }

  Future<void> _navigate() async {
    if (_hasNavigated) return;
    _hasNavigated = true;

    if (!mounted) return;

    final authService = ref.read(authServiceProvider);
    final isAuth = authService.currentUser != null;

    // Small buffer so the final frame renders cleanly
    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    context.go(isAuth ? '/chat' : '/auth');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EdenColors.edenVoid,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = _ctrl.value;

          // Glow intensity: during phase 3 (0.5→0.8), sin wave over the
          // normalised sub-progress. Gives 1.5 breath cycles.
          final glowSubT = _glowPulse.value; // 0→1 only during phase 3
          final glowIntensity = glowSubT > 0
              ? 0.4 + 0.6 * math.sin(glowSubT * math.pi * 3) * 0.5 + 0.5
              : 0.0;
          // Clamp so it doesn't go negative
          final glow = glowIntensity.clamp(0.0, 1.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Layer 1: Vortex particle painter ──────────────────
              CustomPaint(
                painter: _VortexParticlePainter(
                  progress: _particleProgress.value,
                  screenSize: MediaQuery.sizeOf(context),
                ),
              ),

              // ── Layer 2: Ambient glow bloom (behind logo) ─────────
              if (glow > 0)
                Center(
                  child: Opacity(
                    opacity: (glow * _logoOpacity.value).clamp(0.0, 1.0),
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF7B5EA7).withOpacity(0.45 * glow),
                            const Color(0xFFE8875A).withOpacity(0.20 * glow),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Layer 3: Logo ─────────────────────────────────────
              Center(
                child: Opacity(
                  opacity:
                      (_logoOpacity.value * _exitOpacity.value).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: _logoScale.value * _exitScale.value,
                    child: child, // the logo image — built once
                  ),
                ),
              ),
            ],
          );
        },
        child: Image.asset(
          'assets/images/eden_logo.png',
          width: 120,
          height: 120,
          fit: BoxFit.contain,
          // Eden logo already has correct background baked in;
          // use filterQuality high for smooth scale animation.
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — Vortex Particle Coalesce
//
// Spawns [_kParticleCount] particles, each on a unique orbit radius
// and angular offset. As [progress] goes 0→1:
//   - orbit radius shrinks from random spread → 0 (logo center)
//   - alpha fades from 1.0 → 0.0 as they arrive (absorbed into logo)
//   - rotation speed is faster at outer rings (realistic vortex feel)
// ═══════════════════════════════════════════════════════════════════

const int _kParticleCount = 72;

class _Particle {
  final double angleOffset; // radians — unique per particle
  final double radiusFactor; // 0.0–1.0 — how far from center at t=0
  final double size; // px
  final double
      orbitSpeed; // radians per unit of progress (fakes angular velocity)
  final Color color;

  const _Particle({
    required this.angleOffset,
    required this.radiusFactor,
    required this.size,
    required this.orbitSpeed,
    required this.color,
  });
}

List<_Particle> _buildParticles() {
  final rng = math.Random(42); // fixed seed → stable across rebuilds
  final colors = [
    const Color(0xFFE8875A), // warm orange (logo left horn)
    const Color(0xFF9B6FD4), // violet (logo right horn)
    const Color(0xFFF5C89A), // pale gold (star)
    const Color(0xFFCB7DBF), // rose-pink (transition zone)
    const Color(0xFFFFFFFF), // pure white sparkle
  ];

  return List.generate(_kParticleCount, (i) {
    final colorIndex = rng.nextInt(colors.length);
    return _Particle(
      angleOffset: rng.nextDouble() * math.pi * 2,
      radiusFactor: 0.35 + rng.nextDouble() * 0.65, // 35–100% of max radius
      size: 1.2 + rng.nextDouble() * 2.4,
      orbitSpeed: (1.8 + rng.nextDouble() * 2.4) * (rng.nextBool() ? 1 : -1),
      color: colors[colorIndex],
    );
  });
}

final _particles = _buildParticles(); // built once at module level

class _VortexParticlePainter extends CustomPainter {
  final double progress; // 0→1
  final Size screenSize;

  const _VortexParticlePainter({
    required this.progress,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final center = Offset(size.width / 2, size.height / 2);

    // Max orbit radius: ~42% of smaller dimension for nice spread
    final maxRadius = math.min(size.width, size.height) * 0.42;

    // As progress → 1.0, radius shrinks to 0 (arrives at center)
    // Use an ease-in curve so they accelerate inward
    final convergence = Curves.easeIn.transform(progress);

    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in _particles) {
      // Current radius: starts at p.radiusFactor * maxRadius, ends at 0
      final currentRadius = maxRadius * p.radiusFactor * (1.0 - convergence);

      // Angle rotates as they spiral (faster early, slows as radius shrinks)
      final angle = p.angleOffset + p.orbitSpeed * progress * math.pi;

      final x = center.dx + currentRadius * math.cos(angle);
      final y = center.dy + currentRadius * math.sin(angle);

      // Fade out as they reach center (absorbed by logo)
      // Alpha full during first 80% of progress, fades last 20%
      final alphaMult =
          progress < 0.80 ? 1.0 : 1.0 - ((progress - 0.80) / 0.20);

      paint.color = p.color.withOpacity(alphaMult.clamp(0.0, 1.0));

      // Tiny glow: draw a slightly larger, more transparent circle first
      paint.color = p.color.withOpacity((alphaMult * 0.25).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), p.size * 2.2, paint);

      // Core dot
      paint.color = p.color.withOpacity(alphaMult.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_VortexParticlePainter old) => old.progress != progress;
}
