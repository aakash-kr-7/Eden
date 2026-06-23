import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/eden_theme.dart';
import '../main.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Run auth & onboarding checks after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkStatus());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    // Wait at least 1.5 seconds for visual impact of splash screen
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final authState = ref.read(authStateProvider).value;
    if (authState == null || authState.user == null) {
      if (mounted) context.go('/auth');
      return;
    }

    try {
      final apiService = ref.read(apiServiceProvider);
      final onboardingStatus = await apiService.checkOnboardingStatus();
      if (!mounted) return;

      if (onboardingStatus.isComplete) {
        context.go('/chat');
      } else {
        context.go('/onboarding');
      }
    } catch (e) {
      debugPrint('Error checking onboarding status: $e');
      // If server check fails (network issue, etc.), fallback to auth page
      if (mounted) context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EdenTheme.bgPrimary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Image.asset(
                'assets/images/eden_logo.png',
                width: 140,
                height: 140,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  width: 140,
                  height: 140,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: EdenTheme.bgSurface,
                  ),
                  child: const Center(
                    child: Text(
                      'Eden',
                      style: TextStyle(
                        fontFamily: EdenTheme.fontDisplay,
                        color: EdenTheme.accentPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'gathering presence…',
              style: EdenTheme.bodySmall.copyWith(
                color: EdenTheme.textSecondary.withValues(alpha: 0.6),
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
