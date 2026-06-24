// ═══════════════════════════════════════════════════════════════════
// FILE: widgets/eden_button.dart
// PURPOSE: Primary and secondary button components with Eden styling.
// CONTEXT: Used on auth screen, onboarding, settings for all actions.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';

class EdenPrimaryButton extends StatefulWidget {
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
  State<EdenPrimaryButton> createState() => _EdenPrimaryButtonState();
}

class _EdenPrimaryButtonState extends State<EdenPrimaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onTap != null && !widget.isLoading;

    Widget buttonChild = Container(
      height: 54.0,
      width: widget.width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      decoration: BoxDecoration(
        color: EdenColors.edenIris,
        borderRadius: BorderRadius.circular(999.0), // radius-pill
        boxShadow: const [
          BoxShadow(
            color: EdenColors.edenIrisGlow, // rgba iris 0.25
            blurRadius: 20.0,
            offset: Offset(0.0, 4.0),
          ),
        ],
      ),
      child: widget.isLoading
          ? const SizedBox(
              width: 20.0,
              height: 20.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  widget.icon!,
                  const SizedBox(width: 12.0),
                ],
                Text(
                  widget.text,
                  style: EdenTypography.button,
                ),
              ],
            ),
    );

    return GestureDetector(
      onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: isEnabled ? (_) {
        setState(() => _isPressed = false);
        HapticFeedback.lightImpact();
        widget.onTap?.call();
      } : null,
      onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: isEnabled ? (_isPressed ? 0.9 : 1.0) : 0.5,
          duration: const Duration(milliseconds: 100),
          child: buttonChild,
        ),
      ),
    );
  }
}

class EdenSecondaryButton extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final bool isLoading;
  final double? width;
  final Widget? icon;

  const EdenSecondaryButton({
    super.key,
    required this.text,
    this.onTap,
    this.isLoading = false,
    this.width,
    this.icon,
  });

  @override
  State<EdenSecondaryButton> createState() => _EdenSecondaryButtonState();
}

class _EdenSecondaryButtonState extends State<EdenSecondaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onTap != null && !widget.isLoading;

    Widget buttonChild = Container(
      height: 54.0,
      width: widget.width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      decoration: BoxDecoration(
        color: EdenColors.glassMedium,
        borderRadius: BorderRadius.circular(999.0), // radius-pill
        border: Border.all(
          color: EdenColors.glassBorder,
          width: 1.0,
        ),
      ),
      child: widget.isLoading
          ? const SizedBox(
              width: 20.0,
              height: 20.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(EdenColors.textPrimary),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  widget.icon!,
                  const SizedBox(width: 12.0),
                ],
                Text(
                  widget.text,
                  style: EdenTypography.button.copyWith(color: EdenColors.textPrimary),
                ),
              ],
            ),
    );

    return GestureDetector(
      onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: isEnabled ? (_) {
        setState(() => _isPressed = false);
        HapticFeedback.lightImpact();
        widget.onTap?.call();
      } : null,
      onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: isEnabled ? (_isPressed ? 0.9 : 1.0) : 0.5,
          duration: const Duration(milliseconds: 100),
          child: buttonChild,
        ),
      ),
    );
  }
}
