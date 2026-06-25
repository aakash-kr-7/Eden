// ═══════════════════════════════════════════════════════════════════
// FILE: widgets/memory_card.dart
// PURPOSE: Individual memory card for the vault — content, type, date, pin state.
// CONTEXT: Used by memory_vault_screen.dart in the memory list.
// ═══════════════════════════════════════════════════════════════════

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import 'glass_card.dart';

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

class MemoryCardState extends State<MemoryCard> with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> shake() async {
    await _shakeController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('MMMM d, y').format(widget.memory.createdAt);
    final isPinned = widget.memory.isPinned;

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final val = _shakeAnimation.value;
        final double offset = sin(val * pi * 6.0) * 8.0 * (1.0 - val);
        return Transform.translate(
          offset: Offset(offset, 0.0),
          child: child,
        );
      },
      child: GestureDetector(
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (isPinned)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: EdenColors.edenIris,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(left: isPinned ? 16 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // memory_type label: bodySm (12sp), textTertiary, all caps, 4px tracking, appears above text
                    Text(
                      widget.memory.memoryType.name.toUpperCase(),
                      style: EdenTypography.bodySm.copyWith(
                        fontSize: 12.0,
                        color: EdenColors.textTertiary,
                        letterSpacing: 4.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // memoryText: bodyLg (16sp), textPrimary, line height 1.6
                    Text(
                      widget.memory.memoryText,
                      style: EdenTypography.bodyLg.copyWith(
                        fontSize: 16.0,
                        color: EdenColors.textPrimary,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Created date: bodySm, textTertiary, right-aligned bottom
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
            ],
          ),
        ),
      ),
    );
  }
}
