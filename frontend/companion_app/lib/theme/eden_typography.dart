// FILE: theme/eden_typography.dart
// PURPOSE: Backward-compatible typography aliases while Nocturne is the source of truth.
// RESPONSIBILITIES: Forward legacy text style references to Nocturne.
// NEVER: Define standalone typography outside Nocturne.
import 'package:flutter/material.dart';

import 'nocturne.dart';

class EdenTypography {
  EdenTypography._();

  static const TextStyle displayXl = Nocturne.displayXl;
  static const TextStyle displayLg = Nocturne.displayLg;
  static const TextStyle displayMd = Nocturne.displayMd;

  static const TextStyle bodyXl = Nocturne.bodyXl;
  static const TextStyle bodyLg = Nocturne.bodyLg;
  static const TextStyle bodyMd = Nocturne.bodyMd;
  static const TextStyle bodySm = Nocturne.bodySm;

  static const TextStyle label = Nocturne.label;
  static const TextStyle button = Nocturne.button;
}
