import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/eden_colors.dart';
import '../theme/eden_typography.dart';

// ─── Minimal shimmer that respects Eden's no-spinner rule ──────────
class EdenShimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  const EdenShimmer({
    super.key,
    this.width = 80,
    this.height = 16,
    this.borderRadius = 999,
  });

  @override
  State<EdenShimmer> createState() => _EdenShimmerState();
}

class _EdenShimmerState extends State<EdenShimmer>
    with SingleTickerProviderStateMixin {
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
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                EdenColors.glassLight,
                EdenColors.glassShimmer,
                EdenColors.glassLight,
              ],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Primary Button (accent solid, no shadow) ──────────────────────
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
      height: 56.0, // was 54 → 8pt grid
      width: widget.width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      decoration: BoxDecoration(
        color: EdenColors.edenIris,
        borderRadius: BorderRadius.circular(999.0), // radius-pill
        // No boxShadow – Eden uses only glass blur, never shadows
      ),
      child: widget.isLoading
          ? const EdenShimmer(
              width: 80,
              height: 20,
              borderRadius: 999,
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
      onTapUp: isEnabled
          ? (_) {
              setState(() => _isPressed = false);
              HapticFeedback.lightImpact();
              widget.onTap?.call();
            }
          : null,
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

// ─── Secondary Button (glass, no shadow) ───────────────────────────
class EdenSecondaryButton extends StatefulWidget {
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
  State<EdenSecondaryButton> createState() => _EdenSecondaryButtonState();
}

class _EdenSecondaryButtonState extends State<EdenSecondaryButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onTap != null && !widget.isLoading;

    Widget buttonChild = Container(
      height: 56.0, // 8pt grid
      width: widget.width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      decoration: BoxDecoration(
        color: EdenColors.glassMedium,
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(
          color: EdenColors.glassBorder,
          width: 1.0,
        ),
      ),
      child: widget.isLoading
          ? EdenShimmer(
              width: 80,
              height: 20,
              borderRadius: 999,
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
                  style: EdenTypography.button.copyWith(
                    color: widget.textColor,
                  ),
                ),
              ],
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
