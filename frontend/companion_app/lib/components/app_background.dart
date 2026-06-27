// FILE: components/app_background.dart
// PURPOSE: Shared animated background behind the active application flow.
// RESPONSIBILITIES: Render the app-wide ambient backdrop without owning screen state.
// NEVER: Contain navigation logic, user interaction flow, or backend calls.
import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

class AppBackground extends StatefulWidget {
  const AppBackground({super.key});

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);
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
        final t = _controller.value;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.1 * (1 - t), -0.3 + 0.2 * t),
              colors: [
                Nocturne.accentCool.withValues(alpha: 0.2),
                Nocturne.bgSurface,
                Nocturne.black,
              ],
              stops: const [0.1, 0.6, 1.0],
            ),
          ),
          child: child,
        );
      },
      child: const SizedBox.expand(),
    );
  }
}
