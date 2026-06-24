// ═══════════════════════════════════════════════════════════════════
// FILE: widgets/typing_indicator.dart
// PURPOSE: Animated three-dot typing indicator shown while partner responds.
// CONTEXT: Shown in chat screen while SSE response streams in.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../theme/eden_colors.dart';

class TypingIndicator extends StatefulWidget {
  final double dotSize;
  final double spacing;

  const TypingIndicator({
    super.key,
    this.dotSize = 8.0, // 8px circles
    this.spacing = 6.0,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

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
    _fadeController.forward();

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

    _startAnimations();
  }

  void _startAnimations() async {
    for (int i = 0; i < 3; i++) {
      if (!mounted) return;
      _controllers[i].repeat(reverse: true);
      // Staggered delay: 0ms, 150ms, 300ms
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
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
                color: EdenColors.edenIris, // eden-iris brand color
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }
}
