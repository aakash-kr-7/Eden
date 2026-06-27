// ═══════════════════════════════════════════════════════════════════
// FILE: screens/splash_screen.dart
// PURPOSE: A tasteful, minimal Eden splash.
//          Soft radial glow → logo materialises → gentle breath →
//          bloom exit. Total ~4s. No skip.
// ═══════════════════════════════════════════════════════════════════

// RESPONSIBILITIES: Play the splash sequence and hand off into auth or chat.
// NEVER: Contain backend logic or persistent app state ownership.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../theme/eden_colors.dart';

// ─── Timing (4000ms controller) ─────────────────────────────────────
// Phase 1 — background glow breathes in:   0.00 → 0.40
// Phase 2 — logo materialises:             0.20 → 0.60
// Phase 3 — hold with subtle shimmer:      0.60 → 0.85
// Phase 4 — bloom out + fade:              0.85 → 1.00
// ─────────────────────────────────────────────────────────────────────

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // ── Phase 1: ambient glow ────────────────────────────────────────
  late final Animation<double> _glowIntensity;

  // ── Phase 2: logo entrance ───────────────────────────────────────
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;

  // ── Phase 3: subtle shimmer on the celestial body ────────────────
  late final Animation<double> _shimmer;

  // ── Phase 4: bloom exit ──────────────────────────────────────────
  late final Animation<double> _exitBloom;
  late final Animation<double> _exitOpacity;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    // Phase 1: soft radial glow breathes in
    _glowIntensity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.00, 0.40, curve: Curves.easeOut),
    );

    // Phase 2: logo fades in and gently scales up
    _logoOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.20, 0.60, curve: Curves.easeOutCubic),
    );
    _logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.20, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    // Phase 3: celestial body shimmer – subtle opacity pulse
    _shimmer = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.60, 0.85, curve: Curves.easeInOut),
    );

    // Phase 4: bloom (scale + fade out together)
    _exitBloom = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.85, 1.00, curve: Curves.easeIn),
      ),
    );
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.85, 1.00, curve: Curves.easeIn),
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

    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;

    context.go(isAuth ? AppRoute.chat : AppRoute.auth);
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
          // Glow intensity during phase 1 (sinusoidal breathing feel)
          final glow = _glowIntensity.value > 0
              ? 0.3 + 0.2 * math.sin(_glowIntensity.value * math.pi * 1.5)
              : 0.0;

          // Shimmer during phase 3: subtle light pulse on the logo
          final shimmerVal = _shimmer.value > 0
              ? 0.5 + 0.5 * math.sin(_shimmer.value * math.pi * 2)
              : 0.0;

          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Layer 1: Soft ambient radial glow ──────────────────
              if (glow > 0)
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          EdenColors.edenBlush.withValues(alpha: 0.15 * glow),
                          EdenColors.edenIris.withValues(alpha: 0.08 * glow),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),

              // ── Layer 2: Logo (with gentle shimmer overlay) ────────
              Center(
                child: Opacity(
                  opacity:
                      (_logoOpacity.value * _exitOpacity.value).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: _logoScale.value * _exitBloom.value,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // The logo image (hand cradling a glowing celestial body)
                        Image.asset(
                          'assets/icon/app_icon.png',
                          width: 120,
                          height: 120,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                        // A subtle, breathing light overlay on the logo
                        if (shimmerVal > 0)
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  EdenColors.edenGold
                                      .withValues(alpha: 0.12 * shimmerVal),
                                  Colors.transparent,
                                ],
                                stops: const [0.4, 1.0],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
