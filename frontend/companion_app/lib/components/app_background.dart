// FILE: components/app_background.dart
// PURPOSE: Shared animated background behind the active application flow.
// RESPONSIBILITIES: Render the app-wide ambient backdrop without owning screen state.
// NEVER: Contain navigation logic, user interaction flow, or backend calls.
import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.06, -0.18),
          colors: [
            Color(0x3398A7FF),
            Nocturne.bgSurface,
            Nocturne.black,
          ],
          stops: [0.08, 0.56, 1.0],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}
