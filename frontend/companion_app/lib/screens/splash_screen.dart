import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/eden_theme.dart';
import '../main.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  double _opacity = 0.0;
  
  @override
  void initState() {
    super.initState();
    _startTransitionSequence();
  }

  Future<void> _startTransitionSequence() async {
    // 1. Brief delay then fade in wordmark
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    setState(() => _opacity = 1.0);

    // 2. Start running status check concurrently
    final startTime = DateTime.now();
    String targetPath = '/auth';
    
    try {
      final authState = ref.read(authStateProvider).value;
      if (authState != null) {
        final apiService = ref.read(apiServiceProvider);
        final onboardingStatus = await apiService.checkOnboardingStatus();
        if (onboardingStatus.isComplete) {
          targetPath = '/chat';
        } else {
          targetPath = '/onboarding';
        }
      }
    } catch (e) {
      debugPrint('Error in splash screen checks: $e');
      targetPath = '/auth';
    }

    // 3. Enforce minimum display time of 800ms total
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    const minDurationMs = 1200; // slightly longer to feel very intentional and premium
    if (elapsedMs < minDurationMs) {
      await Future.delayed(Duration(milliseconds: minDurationMs - elapsedMs));
    }

    // 4. Fade out content before transition
    if (!mounted) return;
    setState(() => _opacity = 0.0);
    await Future.delayed(const Duration(milliseconds: 400));

    // 5. Navigate to the resolved path
    if (mounted) {
      context.go(targetPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Center(
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          child: Text(
            'Eden',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 42,
              fontWeight: FontWeight.w300,
              color: EdenTheme.textPrimary,
              letterSpacing: 2.0,
            ),
          ),
        ),
      ),
    );
  }
}
