// ═══════════════════════════════════════════════════════════════════
// FILE: widgets/glass_card.dart  
// PURPOSE: Frosted glass card — the primary surface component in Eden.
// CONTEXT: Used by memory cards, modals, and elevated surfaces everywhere.
// ═══════════════════════════════════════════════════════════════════

import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/eden_colors.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.borderRadius = 20.0, // radius-lg is 20px
  });

  @override
  Widget build(BuildContext context) {
    Widget cardContent = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0), // blur-md is 20px
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: EdenColors.glassLight,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: EdenColors.glassBorder,
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      cardContent = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: cardContent,
      );
    }

    if (margin != null) {
      cardContent = Padding(
        padding: margin!,
        child: cardContent,
      );
    }

    return cardContent;
  }
}
