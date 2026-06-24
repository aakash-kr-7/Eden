// ═══════════════════════════════════════════════════════════════════
// FILE: screens/splash_screen.dart
// PURPOSE: Entry point — checks auth and onboarding state, routes accordingly.
// CONTEXT: First screen shown on every app open. Minimum 800ms display.
// ═══════════════════════════════════════════════════════════════════

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../main.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  double _opacity = 0.0;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _startTransitionSequence();
  }

  Future<void> _startTransitionSequence() async {
    // 1. Brief delay then fade in wordmark and tagline
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    setState(() {
      _opacity = 1.0;
      _hasError = false;
    });

    final startTime = DateTime.now();

    // 2. Wait for Firebase auth state to initialize
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
      return; // Do not navigate, wait for user tap retry
    }

    // 3. Enforce minimum display time of 800ms total
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    const minDurationMs = 800;
    if (elapsedMs < minDurationMs) {
      await Future.delayed(Duration(milliseconds: minDurationMs - elapsedMs));
    }

    // 4. Fade out content before transition
    if (!mounted) return;
    setState(() => _opacity = 0.0);
    await Future.delayed(const Duration(milliseconds: 300));

    // 5. Navigate to the resolved path
    if (mounted) {
      context.go(targetPath);
    }
  }

  void _retry() {
    _startTransitionSequence();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EdenColors.edenVoid,
      body: GestureDetector(
        onTap: _hasError ? _retry : null,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedOpacity(
            opacity: _opacity,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Eden',
                  style: EdenTypography.displayXl.copyWith(
                    color: EdenColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24.0),
                Text(
                  'a relationship that remembers',
                  style: EdenTypography.bodySm.copyWith(
                    color: EdenColors.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (_hasError) ...[
                  const SizedBox(height: 32.0),
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
    );
  }
}
