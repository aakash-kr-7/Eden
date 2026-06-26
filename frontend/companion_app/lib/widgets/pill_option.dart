import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../theme/glass_theme.dart';

class PillOption extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isFullWidth;

  const PillOption({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onTap,
    this.isFullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = FakeGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 18),
      settings: isSelected
          ? GlassTheme.button
          : const LiquidGlassSettings(
              blur: 8,
              glassColor: Color(0x18FFFFFF),
            ),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: isFullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: EdenTypography.bodyLg.copyWith(
              color:
                  isSelected ? EdenColors.textAccent : EdenColors.textPrimary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
            child: Center(
              widthFactor: isFullWidth ? null : 1.0,
              child: Text(text),
            ),
          ),
        ),
      ),
    );

    return isFullWidth ? content : IntrinsicWidth(child: content);
  }
}
