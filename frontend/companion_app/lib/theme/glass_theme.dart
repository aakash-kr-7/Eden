// FILE: theme/glass_theme.dart
// PURPOSE: Backward-compatible surface aliases while Nocturne owns the surface language.
// RESPONSIBILITIES: Forward legacy surface references to Nocturne.
// NEVER: Define independent surface presets outside Nocturne.
import '../components/glass.dart';
import 'nocturne.dart';

class GlassTheme {
  GlassTheme._();

  static const LiquidGlassSettings card = Nocturne.surfaceCard;
  static const LiquidGlassSettings prominent = Nocturne.surfaceProminent;
  static const LiquidGlassSettings button = Nocturne.surfaceInteractive;

  static const LiquidRoundedSuperellipse shape = Nocturne.panelShape;
}
