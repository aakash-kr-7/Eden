// ═══════════════════════════════════════════════════════════════════
// FILE: widgets/pill_option.dart
// PURPOSE: Selectable pill for onboarding multiple-choice questions.
// CONTEXT: Used by OnboardingScreen for option selection.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/eden_colors.dart';

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
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected 
              ? EdenColors.edenIrisDim 
              : EdenColors.glassLight,
          borderRadius: BorderRadius.circular(14.0), // radius-md is 14px
          border: Border.all(
            color: isSelected 
                ? EdenColors.edenIris 
                : EdenColors.glassBorder,
            width: 1.0,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          style: GoogleFonts.jost(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
            color: isSelected 
                ? EdenColors.textAccent 
                : EdenColors.textPrimary.withValues(alpha: 0.78),
          ),
          child: text.contains(' · ') 
              ? Text(text) 
              : Center(widthFactor: isFullWidth ? null : 1.0, child: Text(text)),
        ),
      ),
    );
  }
}
