import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../models/models.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../theme/glass_theme.dart';

class MemoryCard extends StatefulWidget {
  final Memory memory;
  final VoidCallback? onLongPress;

  const MemoryCard({
    super.key,
    required this.memory,
    this.onLongPress,
  });

  @override
  State<MemoryCard> createState() => MemoryCardState();
}

class MemoryCardState extends State<MemoryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> shake() async {
    await _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        DateFormat('MMMM d, y').format(widget.memory.createdAt);
    final isPinned = widget.memory.isPinned;

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final val = _shakeAnimation.value;
        final offset = sin(val * pi * 6) * 8 * (1 - val);
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlass.withOwnLayer(
          shape: GlassTheme.shape,
          settings: GlassTheme.card,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.memory.memoryType.name.toUpperCase(),
                        style: EdenTypography.bodySm.copyWith(
                          color: EdenColors.textTertiary,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isPinned)
                      const Icon(
                        Icons.push_pin_rounded,
                        size: 15,
                        color: EdenColors.edenGold,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.memory.memoryText,
                  style: EdenTypography.bodyLg.copyWith(
                    color: EdenColors.textPrimary,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    formattedDate,
                    style: EdenTypography.bodySm.copyWith(
                      color: EdenColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
