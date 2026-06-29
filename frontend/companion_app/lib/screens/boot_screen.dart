// FILE: screens/boot_screen.dart
// PURPOSE: Plays the boot animation, then advances into the existing app flow.
// RESPONSIBILITIES: Play startup media and hand off to splash at the right time.
// NEVER: Contain auth policy, provider ownership, or backend logic.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../main.dart';
import '../theme/nocturne.dart';

class BootScreen extends ConsumerStatefulWidget {
  const BootScreen({super.key});

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen> {
  static bool _hasPlayedBoot = false;

  VideoPlayerController? _controller;
  bool _hasNavigated = false;
  bool _skippingVideo = false;

  @override
  void initState() {
    super.initState();

    if (_hasPlayedBoot) {
      _skippingVideo = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToNextScreen();
      });
    } else {
      _hasPlayedBoot = true;
      _controller = VideoPlayerController.asset('assets/bootup_animation.mp4');
      unawaited(_initializeVideo());
    }
  }

  Future<void> _initializeVideo() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.initialize();
      if (!mounted) return;

      setState(() {});
      await controller.play();
      controller.addListener(_handleVideoState);

      await Future.delayed(const Duration(seconds: 4));
      if (mounted && !_hasNavigated) {
        _navigateToNextScreen();
      }
    } catch (_) {
      if (mounted && !_hasNavigated) {
        _navigateToNextScreen();
      }
    }
  }

  void _handleVideoState() {
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.position >= controller.value.duration) {
      _navigateToNextScreen();
    }
  }

  Future<void> _navigateToNextScreen() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final authService = ref.read(authServiceProvider);
    final isAuthenticated = authService.currentUser != null;

    if (!isAuthenticated) {
      context.go(AppRoute.auth);
      return;
    }

    try {
      final status = await ref.read(apiServiceProvider).onboardingStatus();
      final isComplete = _statusFlag(status['complete']);
      if (!mounted) return;
      context.go(isComplete ? AppRoute.chat : AppRoute.onboarding);
    } catch (_) {
      if (!mounted) return;
      context.go(AppRoute.chat);
    }
  }

  bool _statusFlag(dynamic value) {
    if (value == true || value == 1) return true;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleVideoState);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_skippingVideo) {
      return const Scaffold(
        backgroundColor: Nocturne.black,
        body: SizedBox.shrink(),
      );
    }

    final controller = _controller;
    return Scaffold(
      backgroundColor: Nocturne.black,
      body: Center(
        child: controller != null && controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
