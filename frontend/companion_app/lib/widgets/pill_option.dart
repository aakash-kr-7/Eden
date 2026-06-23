import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/eden_theme.dart';

class PillOption extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const PillOption({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected 
              ? EdenTheme.accentPrimary 
              : EdenTheme.bgSurface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected 
                ? EdenTheme.accentPrimary 
                : EdenTheme.textSecondary.withValues(alpha: 0.15),
            width: 1.0,
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          style: GoogleFonts.jost(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
            color: isSelected 
                ? EdenTheme.bgPrimary 
                : EdenTheme.textPrimary.withValues(alpha: 0.78),
          ),
          child: Text(text),
        ),
      ),
    );
  }
}
