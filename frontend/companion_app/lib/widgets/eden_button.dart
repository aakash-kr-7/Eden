import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';
import '../theme/glass_theme.dart';
import 'shimmer_loader.dart';

class EdenPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool isLoading;
  final double? width;
  final Widget? icon;

  const EdenPrimaryButton({
    super.key,
    required this.text,
    this.onTap,
    this.isLoading = false,
    this.width,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return _EdenGlassButton(
      text: text,
      onTap: onTap,
      isLoading: isLoading,
      width: width,
      icon: icon,
      glowColor: EdenColors.amberGlow,
      textColor: EdenColors.textPrimary,
    );
  }
}

class EdenSecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool isLoading;
  final double? width;
  final Widget? icon;
  final Color textColor;

  const EdenSecondaryButton({
    super.key,
    required this.text,
    this.onTap,
    this.isLoading = false,
    this.width,
    this.icon,
    this.textColor = EdenColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return _EdenGlassButton(
      text: text,
      onTap: onTap,
      isLoading: isLoading,
      width: width,
      icon: icon,
      glowColor: EdenColors.electricBlue,
      textColor: textColor,
      subtle: true,
    );
  }
}

class _EdenGlassButton extends StatefulWidget {
  const _EdenGlassButton({
    required this.text,
    required this.textColor,
    required this.glowColor,
    this.onTap,
    this.isLoading = false,
    this.width,
    this.icon,
    this.subtle = false,
  });

  final String text;
  final VoidCallback? onTap;
  final bool isLoading;
  final double? width;
  final Widget? icon;
  final Color textColor;
  final Color glowColor;
  final bool subtle;

  @override
  State<_EdenGlassButton> createState() => _EdenGlassButtonState();
}

class _EdenGlassButtonState extends State<_EdenGlassButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null && !widget.isLoading;

    Widget content = GlassGlow(
      glowColor: widget.glowColor,
      glowRadius: widget.subtle ? 0.45 : 0.8,
      child: FakeGlass(
        shape: const LiquidRoundedSuperellipse(borderRadius: 22),
        settings: GlassTheme.button,
        child: SizedBox(
          height: 56,
          width: widget.width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Center(
              child: widget.isLoading
                  ? const ShimmerLoader(
                      width: 80, height: 18, borderRadius: 999)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          widget.icon!,
                          const SizedBox(width: 12),
                        ],
                        Text(
                          widget.text,
                          style: EdenTypography.button.copyWith(
                            color: widget.textColor,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    content = AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: AnimatedOpacity(
        opacity: isEnabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 100),
        child: content,
      ),
    );

    return GestureDetector(
      onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: isEnabled
          ? (_) {
              setState(() => _isPressed = false);
              HapticFeedback.lightImpact();
              widget.onTap?.call();
            }
          : null,
      onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
      child: content,
    );
  }
}
