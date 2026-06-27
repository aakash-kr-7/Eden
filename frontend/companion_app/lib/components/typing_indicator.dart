// ═══════════════════════════════════════════════════════════════════
// FILE: components/typing_indicator.dart
// PURPOSE: Animated typing indicator used by the chat experience.
// RESPONSIBILITIES: Render typing dots and timing behavior for active message composition states.
// NEVER: Contain chat transport logic, message state ownership, or API calls.
// CONTEXT: Shows while partner is "typing" before each burst.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/nocturne.dart';

class TypingIndicatorV2 extends StatefulWidget {
  final Duration?
      overrideDuration; // If set, show typing for this long then auto-hide
  final bool isActive;
  final double dotSize;
  final double spacing;
  final bool isFollowUp;

  const TypingIndicatorV2({
    super.key,
    this.overrideDuration,
    required this.isActive,
    this.dotSize = 8.0,
    this.spacing = 6.0,
    this.isFollowUp = false,
  });

  @override
  State<TypingIndicatorV2> createState() => _TypingIndicatorV2State();
}

class _TypingIndicatorV2State extends State<TypingIndicatorV2>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  Timer? _autoHideTimer;
  bool _isAutoHidden = false;

  @override
  void initState() {
    super.initState();

    // Overall entrance fade in (200ms)
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Staggered dot scaling
    // 300ms forward + 300ms reverse = 600ms total cycle
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(
          parent: controller,
          curve: Curves.easeInOut,
        ),
      );
    }).toList();

    if (widget.isActive) {
      _fadeController.forward();
      _startAnimations();
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant TypingIndicatorV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        setState(() {
          _isAutoHidden = false;
        });
        _fadeController.forward();
        _startAnimations();
        _startTimer();
      } else {
        _fadeController.reverse();
        _stopTimer();
      }
    }
  }

  void _startTimer() {
    _stopTimer();
    final duration =
        widget.overrideDuration ?? const Duration(milliseconds: 2000);
    _autoHideTimer = Timer(duration, () {
      if (mounted) {
        setState(() {
          _isAutoHidden = true;
        });
        _fadeController.reverse();
      }
    });
  }

  void _stopTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  void _startAnimations() async {
    for (int i = 0; i < 3; i++) {
      if (!mounted) return;
      _controllers[i].repeat(reverse: true);
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _fadeController.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAutoHidden || !widget.isActive) {
      return const SizedBox.shrink();
    }

    final double baseOpacity = widget.isFollowUp ? 0.40 : 1.0;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Opacity(
        opacity: baseOpacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return ScaleTransition(
              scale: _animations[index],
              child: Container(
                width: widget.dotSize,
                height: widget.dotSize,
                margin: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
                decoration: const BoxDecoration(
                  color: Nocturne.accentCool,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
