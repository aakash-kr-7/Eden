// FILE: screens/splash_screen.dart
// PURPOSE: Deliver a luxurious handoff from boot into the app's auth or chat flow.
// RESPONSIBILITIES: Play a brief cinematic splash and navigate using existing auth state.
// NEVER: Own backend logic, persistent state, or route decisions beyond the existing handoff.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../theme/nocturne.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glow;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _wordOpacity;
  late final Animation<double> _wordOffset;
  late final Animation<double> _fadeOut;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _glow = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.58, curve: Curves.easeOut),
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.12, 0.44, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.12, 0.52, curve: Curves.easeOut),
      ),
    );
    _wordOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 0.64, curve: Curves.easeOut),
    );
    _wordOffset = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.28, 0.64, curve: Curves.easeOut),
      ),
    );
    _fadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.84, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_hasNavigated) {
        _navigate();
      }
    });

    _controller.forward();
  }

  Future<void> _navigate() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final authService = ref.read(authServiceProvider);
    final isAuthenticated = authService.currentUser != null;

    await Future<void>.delayed(const Duration(milliseconds: 70));
    if (!mounted) return;

    context.go(isAuthenticated ? AppRoute.chat : AppRoute.auth);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final ambientPulse = _glow.value == 0
              ? 0.0
              : 0.72 + (math.sin(_glow.value * math.pi * 1.8) * 0.18);

          return Opacity(
            opacity: _fadeOut.value,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                Center(
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Nocturne.accentWarm
                              .withValues(alpha: 0.10 * ambientPulse),
                          Nocturne.accentCool
                              .withValues(alpha: 0.08 * ambientPulse),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Opacity(
                      opacity: _logoOpacity.value,
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        width: 122,
                        height: 122,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, 0.28),
                  child: Transform.translate(
                    offset: Offset(0, _wordOffset.value),
                    child: Opacity(
                      opacity: _wordOpacity.value,
                      child: Text(
                        'Eden',
                        style: Nocturne.displayLg.copyWith(
                          fontSize: 42,
                          letterSpacing: -0.7,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
