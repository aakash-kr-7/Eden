// ═══════════════════════════════════════════════════════════════════
// FILE: widgets/shimmer_loader.dart
// PURPOSE: Skeleton shimmer loading placeholder for lists and cards.
// CONTEXT: Used while memories, messages, and session data load.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../theme/eden_colors.dart';

class ShimmerLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0, // default radius-sm is 8px
  });

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Translate the gradient alignments from left to right based on the animation value
        final double value = _controller.value;
        final Alignment beginAlignment = Alignment(-2.0 + (value * 4.0), -1.0);
        final Alignment endAlignment = Alignment((value * 4.0), 1.0);

        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: beginAlignment,
              end: endAlignment,
              colors: const [
                EdenColors.edenElevated,
                EdenColors.edenRim,
                EdenColors.edenElevated,
              ],
            ),
          ),
        );
      },
    );
  }
}
