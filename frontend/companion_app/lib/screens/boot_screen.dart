import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../theme/eden_colors.dart';

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  late final VideoPlayerController _controller;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset('assets/bootup_animation.mp4');

    unawaited(_initializeVideo());
  }

  Future<void> _initializeVideo() async {
    try {
      await _controller.initialize();
      if (!mounted) return;

      setState(() {});
      await _controller.play();
      _controller.addListener(_handleVideoState);

      await Future.delayed(const Duration(seconds: 4));
      if (mounted && !_hasNavigated) {
        _navigateToSplash();
      }
    } catch (_) {
      if (mounted && !_hasNavigated) {
        _navigateToSplash();
      }
    }
  }

  void _handleVideoState() {
    if (_controller.value.isInitialized &&
        _controller.value.position >= _controller.value.duration) {
      _navigateToSplash();
    }
  }

  void _navigateToSplash() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    context.go('/splash');
  }

  @override
  void dispose() {
    _controller.removeListener(_handleVideoState);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EdenColors.edenVoid,
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
