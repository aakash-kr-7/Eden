// ═══════════════════════════════════════════════════════════════════
// FILE: screens/splash_screen.dart
// PURPOSE: Entry point — checks auth and onboarding state, routes accordingly.
// CONTEXT: First screen shown on every app open. Minimum 2500ms display.
// ═══════════════════════════════════════════════════════════════════

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../main.dart';
import '../widgets/eden_logo.dart';
import '../widgets/atmospheric_background.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  double _contentOpacity = 0.0;
  double _textOpacity = 0.0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _startTransitionSequence();
  }

  Future<void> _startTransitionSequence() async {
    // 1. Initial delay, then fade in the logo container
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    setState(() {
      _contentOpacity = 1.0;
      _hasError = false;
    });

    // 2. Fade in the text brand elements halfway through the logo drawing
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _textOpacity = 1.0;
    });

    final startTime = DateTime.now();

    // 3. Perform background state checks
    User? user;
    final authStateAsync = ref.read(authStateProvider);
    if (authStateAsync.isLoading) {
      try {
        user = await ref.read(authStateProvider.future);
      } catch (e) {
        user = null;
      }
    } else {
      user = authStateAsync.value;
    }

    String targetPath = '/auth';
    bool gotError = false;

    if (user != null) {
      try {
        final apiService = ref.read(apiServiceProvider);
        final onboardingStatus = await apiService.checkOnboardingStatus();
        if (onboardingStatus.isComplete) {
          targetPath = '/chat';
        } else {
          targetPath = '/onboarding';
        }
      } catch (e) {
        debugPrint('Error in splash screen onboarding check: $e');
        gotError = true;
      }
    } else {
      targetPath = '/auth';
    }

    if (gotError) {
      if (mounted) {
        setState(() => _hasError = true);
      }
      return; // Stop transition flow, wait for manual user tap to retry
    }

    // 4. Guarantee minimum display of 2500ms for a slow, premium breathing experience
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds +
        1050; // includes the two delays
    const minDurationMs = 2500;
    if (elapsedMs < minDurationMs) {
      await Future.delayed(Duration(milliseconds: minDurationMs - elapsedMs));
    }

    // 5. Fade out content prior to router change
    if (!mounted) return;
    setState(() {
      _contentOpacity = 0.0;
    });
    await Future.delayed(const Duration(milliseconds: 400));

    // 6. Router navigation
    if (mounted) {
      context.go(targetPath);
    }
  }

  void _retry() {
    setState(() {
      _contentOpacity = 0.0;
      _textOpacity = 0.0;
      _hasError = false;
    });
    _startTransitionSequence();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EdenColors.edenVoid,
      body: AtmosphericBackground(
        child: GestureDetector(
          onTap: _hasError ? _retry : null,
          behavior: HitTestBehavior.opaque,
          child: Center(
            child: AnimatedOpacity(
              opacity: _contentOpacity,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Ancient runic logo with custom path metrics draw animation
                  const EdenLogo(size: 96.0),
                  const SizedBox(height: 36.0),
                  // Wordmark and tagline
                  AnimatedOpacity(
                    opacity: _textOpacity,
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    child: Column(
                      children: [
                        // Wordmark — Cormorant Garamond, display-xl
                        Text(
                          'Eden',
                          style: EdenTypography.displayXl.copyWith(
                            color: EdenColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12.0),
                        // Tagline — design spec: body-md (14sp), text-tertiary, italic
                        // FIXED: was bodySm (12sp) — corrected to bodyMd (14sp) per Eden design system
                        Text(
                          'a relationship that remembers',
                          style: EdenTypography.bodyMd.copyWith(
                            color: EdenColors.textTertiary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_hasError) ...[
                    const SizedBox(height: 48.0),
                    Text(
                      'Connection error. Tap anywhere to retry.',
                      style: EdenTypography.bodySm.copyWith(
                        color: EdenColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
