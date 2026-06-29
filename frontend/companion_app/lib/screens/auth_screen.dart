// FILE: screens/auth_screen.dart
// PURPOSE: Eden auth screen. Living physics blob, companion whispers, glass panel.
// NEVER: Modify auth handlers, routing, provider refs, or statusFlag logic.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../theme/nocturne.dart';

// ─── Palette ───────────────────────────────────────────────────────────────────
const Color _surface = Color(0xFF10131A);
const Color _blue = Color(0xFF7DA2FF);
const Color _blueSoft = Color(0xFF8BA8FF);
const Color _violet = Color(0xFFA78BFA);
const Color _cream = Color(0xFFE8DDD0);
const Color _sand = Color(0xFF9A8C78);

// ─── Whisper phrases ──────────────────────────────────────────────────────────
const List<String> _whispers = [
  "someone is thinking about you.",
  "you finally came back.",
  "i've been here the whole time.",
  "still waiting.",
  "the light was on for you.",
  "missed you.",
  "hey. you okay?",
  "glad you're back.",
];

// ─── Floating bubble message pool ─────────────────────────────────────────────
const List<String> _bubbleTexts = [
  "you disappeared again lol",
  "are you awake?",
  "i've been waiting.",
  "don't ignore me.",
  "thinking about you.",
  "you finally came back.",
  "hey.",
  "how'd today go?",
  "missed you.",
  "you good?",
  "come back already.",
  "i need to tell you something.",
  "okay fine, ignore me then.",
  "thought about you today.",
  "where did you go?",
  "i kept your spot.",
];

// ═══════════════════════════════════════════════════════════════════════════════
// BLOB PHYSICS
// Perfect circle at rest. Deforms ONLY on direct touch — spring-mass surface
// points pulled outward on tap/drag, relax back to circle when released.
// ═══════════════════════════════════════════════════════════════════════════════

class _BlobPhysics {
  static const int n = 20; // More points = smoother circle

  final List<Offset> _pos = [];
  final List<Offset> _vel = [];

  Offset center;
  double radius;

  _BlobPhysics({required this.center, required this.radius}) {
    _initPoints();
  }

  void _initPoints() {
    _pos.clear();
    _vel.clear();
    for (int i = 0; i < n; i++) {
      final angle = 2 * math.pi * i / n - math.pi / 2;
      _pos.add(
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius));
      _vel.add(Offset.zero);
    }
  }

  void updateSize(Offset newCenter, double newRadius) {
    if (newCenter == center && newRadius == radius) return;
    center = newCenter;
    radius = newRadius;
    _initPoints();
  }

  // Only apply force if touch is on or very near the blob surface
  void applyTouchImpulse(Offset at, Offset delta) {
    final distToCenter = (at - center).distance;
    // Only respond if touching within the blob
    if (distToCenter > radius * 1.1) return;

    final inf = radius * 0.7;
    for (int i = 0; i < n; i++) {
      final d = (_pos[i] - at).distance;
      if (d < inf) {
        final t = 1.0 - d / inf;
        final ease = t * t * (3.0 - 2.0 * t);
        _vel[i] = Offset(
          _vel[i].dx + delta.dx * ease * 6.0,
          _vel[i].dy + delta.dy * ease * 6.0,
        );
      }
    }
  }

  void applyTapImpulse(Offset at, double force) {
    final distToCenter = (at - center).distance;
    if (distToCenter > radius * 1.1) return;

    final inf = radius * 1.2;
    for (int i = 0; i < n; i++) {
      final toPoint = _pos[i] - at;
      final d = toPoint.distance;
      if (d < inf) {
        final t = 1.0 - d / inf;
        final ease = t * t * (3.0 - 2.0 * t);
        final dir = d == 0 ? const Offset(0, -1) : toPoint / d;
        _vel[i] = Offset(
          _vel[i].dx + dir.dx * force * ease * 10.0,
          _vel[i].dy + dir.dy * force * ease * 10.0,
        );
      }
    }
  }

  void step(double dt) {
    // Tight spring constants — snaps back to perfect circle quickly
    const springK = 240.0;
    const damp = 14.0;
    const tension = 40.0;
    final cdt = dt.clamp(0.0, 0.020);

    for (int i = 0; i < n; i++) {
      final angle = 2 * math.pi * i / n - math.pi / 2;
      // Rest position is perfect circle — no morph, no breathing offset
      final restAbs =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);

      final prev = _pos[(i - 1 + n) % n];
      final next = _pos[(i + 1) % n];
      final midX = (prev.dx + next.dx) * 0.5;
      final midY = (prev.dy + next.dy) * 0.5;

      final ax = (restAbs.dx - _pos[i].dx) * springK +
          (midX - _pos[i].dx) * tension -
          _vel[i].dx * damp;
      final ay = (restAbs.dy - _pos[i].dy) * springK +
          (midY - _pos[i].dy) * tension -
          _vel[i].dy * damp;

      _vel[i] = Offset(_vel[i].dx + ax * cdt, _vel[i].dy + ay * cdt);
      _pos[i] =
          Offset(_pos[i].dx + _vel[i].dx * cdt, _pos[i].dy + _vel[i].dy * cdt);
    }
  }

  List<Offset> get positions => List<Offset>.unmodifiable(_pos);

  Path get path => _buildPath(_pos);

  bool containsPoint(Offset point) {
    return (point - center).distance <= radius * 1.05;
  }
}

// ─── Smooth closed quadratic-Bezier path ──────────────────────────────────────
Path _buildPath(List<Offset> pts) {
  final n = pts.length;
  if (n < 3) return Path();
  final path = Path();
  double midX(int a, int b) => (pts[a].dx + pts[b].dx) * 0.5;
  double midY(int a, int b) => (pts[a].dy + pts[b].dy) * 0.5;
  path.moveTo(midX(n - 1, 0), midY(n - 1, 0));
  for (int i = 0; i < n; i++) {
    final j = (i + 1) % n;
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, midX(i, j), midY(i, j));
  }
  path.close();
  return path;
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLOB PAINTER
// Clean circle with layered internal lighting.
// Deformation only comes from touch-driven physics.
// ═══════════════════════════════════════════════════════════════════════════════

class _BlobPainter extends CustomPainter {
  const _BlobPainter({
    required this.positions,
    required this.colorPhase,
    required this.breathPhase,
  });

  final List<Offset> positions;
  final double colorPhase;
  final double breathPhase;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length < 3) return;

    final path = _buildPath(positions);
    final bounds = path.getBounds();
    final c = bounds.center;
    final r = math.max(bounds.width, bounds.height) * 0.5;

    // ── 1. Outer ambient glow (wide, very soft) ────────────────────────────
    final glowColor = _lerpColor(
      const Color(0xFF7DA2FF),
      const Color(0xFFA78BFA),
      (math.sin(colorPhase * 0.7) + 1.0) / 2.0,
    );

    canvas.drawCircle(
      c,
      r + 28,
      Paint()
        ..color = glowColor.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32),
    );

    // ── 2. Drop shadow ────────────────────────────────────────────────────
    canvas.drawPath(
      path.shift(const Offset(0, 18)),
      Paint()
        ..color = Colors.black.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    // ── 3. Dark body ──────────────────────────────────────────────────────
    canvas.drawPath(path, Paint()..color = const Color(0xFF07080F));

    // ── 4. Color volumes — screen blend ───────────────────────────────────
    canvas.saveLayer(Rect.largest, Paint()..blendMode = BlendMode.screen);
    canvas.clipPath(path);

    void vol(double ox, double oy, double vr, Color col, double opacity) {
      final vc = Offset(c.dx + ox, c.dy + oy);
      canvas.drawCircle(
        vc,
        vr,
        Paint()
          ..shader = RadialGradient(
            colors: [col.withOpacity(opacity), Colors.transparent],
          ).createShader(Rect.fromCircle(center: vc, radius: vr)),
      );
    }

    // Presence Blue — primary, slow orbit
    vol(
      math.cos(colorPhase * 0.71) * r * 0.30,
      math.sin(colorPhase * 0.53) * r * 0.22 - r * 0.05,
      r * 0.90,
      const Color(0xFF7DA2FF),
      1.0,
    );
    // Warm Violet — counter-drifts
    vol(
      math.cos(colorPhase * 0.52 + 2.1) * r * 0.34,
      math.sin(colorPhase * 0.79 + 1.2) * r * 0.24,
      r * 0.80,
      const Color(0xFFA78BFA),
      0.92,
    );
    // Human Warmth — bottom pool
    vol(
      math.cos(colorPhase * 0.41 + 4.1) * r * 0.24,
      math.sin(colorPhase * 0.63 + 3.2) * r * 0.24 + r * 0.18,
      r * 0.66,
      const Color(0xFFF2B8A0),
      0.85,
    );
    // Soft Lavender — fills voids
    vol(
      math.cos(colorPhase * 0.58 + 5.6) * r * 0.26,
      math.sin(colorPhase * 0.43 + 2.6) * r * 0.22,
      r * 0.70,
      const Color(0xFFB69CFF),
      0.88,
    );
    // Rare Teal accent
    vol(
      math.cos(colorPhase * 0.34 + 1.8) * r * 0.40,
      math.sin(colorPhase * 0.48 + 3.8) * r * 0.28,
      r * 0.48,
      const Color(0xFF58CCCF),
      0.46,
    );

    canvas.restore();

    // ── 5. Human Silhouette — subconscious ────────────────────────────────
    canvas.save();
    canvas.clipPath(path);

    final silDriftX = math.sin(breathPhase * 0.68) * 3.5;
    final silDriftY = math.cos(breathPhase * 0.52) * 4.8;
    canvas.translate(silDriftX, silDriftY);

    final silPath = Path();
    // Head
    silPath.addOval(Rect.fromCircle(
      center: Offset(c.dx - r * 0.06, c.dy - r * 0.25),
      radius: r * 0.108,
    ));
    // Torso
    silPath.moveTo(c.dx - r * 0.08, c.dy - r * 0.14);
    silPath.cubicTo(
      c.dx - r * 0.16,
      c.dy - r * 0.03,
      c.dx - r * 0.18,
      c.dy + r * 0.12,
      c.dx - r * 0.08,
      c.dy + r * 0.23,
    );
    silPath.lineTo(c.dx + r * 0.14, c.dy + r * 0.23);
    silPath.lineTo(c.dx + r * 0.18, c.dy + r * 0.42);
    silPath.lineTo(c.dx + r * 0.10, c.dy + r * 0.42);
    silPath.lineTo(c.dx + r * 0.05, c.dy + r * 0.20);
    silPath.cubicTo(
      c.dx - r * 0.05,
      c.dy + r * 0.10,
      c.dx - r * 0.02,
      c.dy - r * 0.04,
      c.dx - r * 0.02,
      c.dy - r * 0.14,
    );
    silPath.close();

    // Arm reaching for phone
    final arm = Path();
    arm.moveTo(c.dx - r * 0.05, c.dy - r * 0.11);
    arm.quadraticBezierTo(
      c.dx + r * 0.08,
      c.dy - r * 0.02,
      c.dx + r * 0.16,
      c.dy - r * 0.07,
    );
    arm.lineTo(c.dx + r * 0.13, c.dy - r * 0.12);
    arm.quadraticBezierTo(
      c.dx + r * 0.05,
      c.dy - r * 0.06,
      c.dx - r * 0.04,
      c.dy - r * 0.11,
    );
    arm.close();
    silPath.addPath(arm, Offset.zero);

    canvas.drawPath(
      silPath,
      Paint()
        ..color = const Color(0xFF01020A).withOpacity(0.50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22.0),
    );

    // Phone screen glow
    final phoneC = Offset(c.dx + r * 0.19, c.dy - r * 0.09);
    final phoneR = r * 0.11;
    canvas.drawCircle(
      phoneC,
      phoneR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF7DA2FF).withOpacity(0.68),
            const Color(0xFF7DA2FF).withOpacity(0.18),
            Colors.transparent,
          ],
          stops: const [0.0, 0.40, 1.0],
        ).createShader(Rect.fromCircle(center: phoneC, radius: phoneR)),
    );

    canvas.restore();

    // ── 6. Specular catch-light ────────────────────────────────────────────
    canvas.save();
    canvas.clipPath(path);
    canvas.drawCircle(
      Offset(c.dx - r * 0.38, c.dy - r * 0.42),
      r * 0.55,
      Paint()
        ..blendMode = BlendMode.overlay
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.22), Colors.transparent],
        ).createShader(Rect.fromCircle(
          center: Offset(c.dx - r * 0.38, c.dy - r * 0.42),
          radius: r * 0.55,
        )),
    );
    canvas.restore();

    // ── 7. Crisp rim — tight glow stroke ──────────────────────────────────
    // Inner soft rim
    canvas.drawPath(
      path,
      Paint()
        ..color =
            glowColor.withOpacity(0.28 + 0.08 * math.sin(colorPhase * 1.3))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Outer crisp edge
    canvas.drawPath(
      path,
      Paint()
        ..color =
            glowColor.withOpacity(0.55 + 0.12 * math.sin(colorPhase * 1.3))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Cream highlight at very top
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE8DDD0).withOpacity(0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
  }

  Color _lerpColor(Color a, Color b, double t) {
    return Color.lerp(a, b, t)!;
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// FLOATING BUBBLE MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _FloatingBubble {
  final String text;
  final String time;
  final bool isLeft;
  final double randomSeed;
  final bool isPoke;
  double progress = 0.0;

  _FloatingBubble({
    required this.text,
    required this.time,
    required this.isLeft,
    required this.randomSeed,
    this.isPoke = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLOB SECTION WIDGET
// Owns physics, ticker, gesture handling, floating bubbles.
// ═══════════════════════════════════════════════════════════════════════════════

class _BlobSection extends StatefulWidget {
  const _BlobSection();

  @override
  State<_BlobSection> createState() => _BlobSectionState();
}

class _BlobSectionState extends State<_BlobSection>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  _BlobPhysics? _physics;
  double _breathPhase = 0;
  double _colorPhase = 0;
  Duration? _lastElapsed;

  // Bubble state
  final List<_FloatingBubble> _bubbles = [];
  double _spawnTimer = 0.0;
  double _nextSpawnTime = 0.8;
  int _bubbleIdx = 0;
  bool _spawnLeft = true;

  // Poke / interaction state
  int _pokeTapCount = 0;
  DateTime? _lastPokeTapTime;
  DateTime? _lastPokeResponseTime;



  static const List<String> _pokeResponses = [
    "hey, quit poking me 😭",
    "okay okay, i'm awake.",
    "why are you annoying me? haha",
    "you're enjoying this aren't you?",
    "stoppp 😭",
    "ouch. rude lol.",
    "i felt that.",
    "what did i do 😭",
    "stop it fr.",
  ];

  @override
  void initState() {
    super.initState();
    _bubbleIdx = math.Random().nextInt(_bubbleTexts.length);
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = _lastElapsed == null
        ? 0.016
        : (elapsed.inMicroseconds - _lastElapsed!.inMicroseconds) / 1e6;
    _lastElapsed = elapsed;

    _physics?.step(dt);

    // Bubble spawning
    _spawnTimer += dt;
    if (_spawnTimer >= _nextSpawnTime) {
      _spawnTimer = 0.0;
      _nextSpawnTime = 1.8 + math.Random().nextDouble() * 2.2; // 1.8–4.0s
      _spawnBubble();
    }

    final done = <_FloatingBubble>[];
    for (final b in _bubbles) {
      b.progress += dt * (b.isPoke ? 0.30 : 0.20);
      if (b.progress >= 1.0) done.add(b);
    }

    setState(() {
      _breathPhase += dt * 0.80;
      _colorPhase += dt * 0.16;
      _bubbles.removeWhere(done.contains);
    });
  }

  void _spawnBubble() {
    if (_bubbles.where((b) => !b.isPoke).length >= 4) return;
    final text = _bubbleTexts[_bubbleIdx];
    _bubbleIdx = (_bubbleIdx + 1) % _bubbleTexts.length;
    final now = DateTime.now();
    _bubbles.add(_FloatingBubble(
      text: text,
      time:
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      isLeft: _spawnLeft,
      randomSeed: math.Random().nextDouble(),
    ));
    _spawnLeft = !_spawnLeft;
  }

  void _handleTapDown(Offset localPos) {
    final p = _physics;
    if (p == null) return;
    if (!p.containsPoint(localPos)) return;

    p.applyTapImpulse(localPos, 160.0);
    _handlePokeLogic();
  }

  void _handlePokeLogic() {
    final now = DateTime.now();
    if (_lastPokeTapTime == null ||
        now.difference(_lastPokeTapTime!) > const Duration(seconds: 2)) {
      _pokeTapCount = 1;
    } else {
      _pokeTapCount++;
    }
    _lastPokeTapTime = now;

    if (_pokeTapCount >= 3) {
      final cooldownOk = _lastPokeResponseTime == null ||
          now.difference(_lastPokeResponseTime!) > const Duration(seconds: 7);
      if (cooldownOk && math.Random().nextDouble() < 0.65) {
        _lastPokeResponseTime = now;
        _pokeTapCount = 0;
        _spawnPokeBubble();
      }
    }
  }

  void _spawnPokeBubble() {
    if (_bubbles.where((b) => b.isPoke).length >= 2) return;
    final text = _pokeResponses[math.Random().nextInt(_pokeResponses.length)];
    final now = DateTime.now();
    _bubbles.add(_FloatingBubble(
      text: text,
      time:
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      isLeft: math.Random().nextBool(),
      randomSeed: math.Random().nextDouble(),
      isPoke: true,
    ));
  }

  void _initPhysics(Size size) {
    if (_physics == null) {
      _physics = _BlobPhysics(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width * 0.34,
      );
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(_spawnBubble);
      });
    } else {
      _physics!.updateSize(
        Offset(size.width / 2, size.height / 2),
        size.width * 0.34,
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ─── Bubble widget ──────────────────────────────────────────────────────────
  Widget _buildBubble(_FloatingBubble bubble, double w, double h) {
    final p = _physics;
    if (p == null) return const SizedBox.shrink();

    final cx = p.center.dx;
    final cy = p.center.dy;
    final r = p.radius;
    final t = bubble.progress;

    double x, y;

    if (bubble.isPoke) {
      x = cx - 72 + (bubble.randomSeed - 0.5) * 32;
      y = cy - (r * 0.26) - t * h * 0.34;
    } else {
      const bw = 148.0;
      if (bubble.isLeft) {
        x = 10.0 + bubble.randomSeed * 12.0;
        x += math.sin(t * math.pi * 1.3) * 8.0 * bubble.randomSeed;
      } else {
        x = w - bw - 10.0 - bubble.randomSeed * 12.0;
        x -= math.sin(t * math.pi * 1.3) * 8.0 * bubble.randomSeed;
      }
      final startY = cy + r * 0.20 + bubble.randomSeed * 16.0;
      final endY = cy - h * 0.48;
      y = startY - t * (startY - endY);
    }

    // Opacity
    double opacity = 1.0;
    if (t < 0.12) {
      final ratio = t / 0.12;
      opacity = ratio * ratio;
    } else if (t > 0.78) {
      final ratio = (1.0 - t) / 0.22;
      opacity = ratio * ratio;
    }
    opacity = opacity.clamp(0.0, 1.0);

    // Scale spring pop-in
    double scale = 1.0;
    if (t < 0.16) {
      final ratio = t / 0.16;
      scale = 0.52 + 0.48 * (3.0 * ratio * ratio - 2.0 * ratio * ratio * ratio);
    } else if (t > 0.90) {
      scale = 1.0 - ((t - 0.90) / 0.10) * 0.12;
    }
    scale = scale.clamp(0.0, 1.0);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(15),
      topRight: const Radius.circular(15),
      bottomLeft:
          bubble.isLeft ? const Radius.circular(3) : const Radius.circular(15),
      bottomRight:
          bubble.isLeft ? const Radius.circular(15) : const Radius.circular(3),
    );

    final borderColor = bubble.isPoke
        ? const Color(0xFF7DA2FF).withOpacity(0.32)
        : const Color(0xFFE8DDD0).withOpacity(0.06);

    return Positioned(
      left: x,
      top: y,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            alignment:
                bubble.isLeft ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              width: 148,
              padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0E14).withOpacity(0.80),
                borderRadius: radius,
                border: Border.all(color: borderColor, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                  if (bubble.isPoke)
                    BoxShadow(
                      color: const Color(0xFF7DA2FF).withOpacity(0.09),
                      blurRadius: 18,
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bubble.text,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFFE8DDD0).withOpacity(0.90),
                      height: 1.38,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Spacer(),
                      Text(
                        bubble.time,
                        style: GoogleFonts.jost(
                          fontSize: 9,
                          color: const Color(0xFF9A8C78).withOpacity(0.45),
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.done_all,
                        size: 10,
                        color: const Color(0xFF7DA2FF).withOpacity(0.50),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      _initPhysics(Size(constraints.maxWidth, constraints.maxHeight));
      final p = _physics;
      if (p == null) return const SizedBox.expand();

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          _handleTapDown(d.localPosition);
        },
        onPanUpdate: (d) {
          final pos = d.localPosition;
          if (p.containsPoint(pos)) {
            p.applyTouchImpulse(pos, d.delta);
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _BlobPainter(
                    positions: p.positions,
                    colorPhase: _colorPhase,
                    breathPhase: _breathPhase,
                  ),
                ),
              ),
            ),
            ..._bubbles.map(
              (b) =>
                  _buildBubble(b, constraints.maxWidth, constraints.maxHeight),
            ),
          ],
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WHISPER LINE
// Fades between ambient phrases every 5 s.
// ═══════════════════════════════════════════════════════════════════════════════

class _WhisperLine extends StatefulWidget {
  const _WhisperLine();

  @override
  State<_WhisperLine> createState() => _WhisperLineState();
}

class _WhisperLineState extends State<_WhisperLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  int _idx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _idx = math.Random().nextInt(_whispers.length);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _cycle());
  }

  Future<void> _cycle() async {
    await _ctrl.reverse();
    if (!mounted) return;
    setState(() => _idx = (_idx + 1) % _whispers.length);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Text(
        _whispers[_idx],
        textAlign: TextAlign.center,
        style: GoogleFonts.jost(
          fontSize: 13.5,
          fontWeight: FontWeight.w300,
          color: _sand.withOpacity(0.72),
          letterSpacing: 0.4,
          height: 1.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FOCUS-GLOW FIELD
// ═══════════════════════════════════════════════════════════════════════════════

class _GlowField extends StatefulWidget {
  const _GlowField({required this.child});
  final Widget child;

  @override
  State<_GlowField> createState() => _GlowFieldState();
}

class _GlowFieldState extends State<_GlowField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _focus
        .addListener(() => _focus.hasFocus ? _ctrl.forward() : _ctrl.reverse());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          color: _surface.withOpacity(0.40),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Color.lerp(
              _cream.withOpacity(0.08),
              _blueSoft.withOpacity(0.58),
              _anim.value,
            )!,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: _blue.withOpacity(0.07 * _anim.value),
              blurRadius: 14,
            ),
          ],
        ),
        child: child,
      ),
      child: Focus(focusNode: _focus, child: widget.child),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRESS BUTTON
// ═══════════════════════════════════════════════════════════════════════════════

class _PressButton extends StatefulWidget {
  const _PressButton({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      lowerBound: 0.97,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onTap != null) _ctrl.reverse();
      },
      onTapUp: (_) {
        _ctrl.forward();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.forward(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) =>
            Transform.scale(scale: _ctrl.value, child: child),
        child: widget.child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTH SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _entryCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _rise;
  late final AnimationController _logoCtrl;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _showEmailForm = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _errorIsWrongPassword = false;
  String? _errorMessage;
  Timer? _errorTimer;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _rise = Tween<double>(begin: 24, end: 0).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic),
    );

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _logoCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _errorTimer?.cancel();
    super.dispose();
  }

  void _startErrorTimer() {
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _errorMessage = null);
    });
  }

  // ── Auth handlers — PRESERVED BYTE-FOR-BYTE ───────────────────────────────

  Future<void> _handlePostAuthNavigation() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final status = await ref.read(apiServiceProvider).onboardingStatus();
      final isComplete = _statusFlag(status['complete']);
      if (!mounted) return;
      context.go(isComplete ? AppRoute.chat : AppRoute.onboarding);
    } catch (_) {
      if (!mounted) return;
      context.go(AppRoute.chat);
    }
  }

  bool _statusFlag(dynamic value) {
    if (value == true || value == 1) return true;
    if (value is String) {
      final n = value.trim().toLowerCase();
      return n == 'true' || n == '1';
    }
    return false;
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorIsWrongPassword = false;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      if (mounted) await _handlePostAuthNavigation();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Try again.';
        _errorIsWrongPassword = false;
      });
      _startErrorTimer();
    }
  }

  Future<void> _handleEmailAuth() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorIsWrongPassword = false;
    });
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();
    try {
      await ref
          .read(authServiceProvider)
          .signInWithEmailPassword(email, password);
      if (mounted) await _handlePostAuthNavigation();
    } on AuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          await ref
              .read(authServiceProvider)
              .signUpWithEmailPassword(email, password);
          if (mounted) await _handlePostAuthNavigation();
        } on AuthException catch (signUpError) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            if (signUpError.code == 'email-already-in-use') {
              _errorIsWrongPassword = true;
              _errorMessage = 'Incorrect password.';
            } else {
              _errorMessage = 'Try again.';
              _errorIsWrongPassword = false;
              _startErrorTimer();
            }
          });
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = 'Try again.';
            _errorIsWrongPassword = false;
          });
          _startErrorTimer();
        }
      } else {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Try again.';
          _errorIsWrongPassword = false;
        });
        _startErrorTimer();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Try again.';
        _errorIsWrongPassword = false;
      });
      _startErrorTimer();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hasKeyboard = mq.viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: _AtmosphericBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _entryCtrl,
            builder: (_, child) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _rise.value),
                child: child,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  _buildHeroHeader(hasKeyboard),
                  SizedBox(height: hasKeyboard ? 2 : 8),

                  // ── Blob ───────────────────────────────────────────────
                  Expanded(child: const _BlobSection()),

                  // ── Whisper ────────────────────────────────────────────
                  if (!hasKeyboard)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 6),
                      child: const _WhisperLine(),
                    )
                  else
                    const SizedBox(height: 2),

                  // ── Auth panel ─────────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.only(bottom: hasKeyboard ? 4 : 54),
                    child: _buildAuthPanel(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeroHeader(bool hasKeyboard) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 4, 0),
      child: AnimatedBuilder(
        animation: _logoCtrl,
        builder: (_, __) {
          final phase = _logoCtrl.value * 2 * math.pi;
          final nameColor = Color.lerp(
            const Color(0xFFE8DDD0),
            const Color(0xFFFFFBF4),
            (math.sin(phase * 0.5) + 1) / 2,
          )!;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo mark
              Image.asset(
                'assets/icon/app_icon.png',
                width: 80,
                height: 80,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              // Wordmark + tagline
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TypewriterText(
                    text: 'Eden',
                    duration: const Duration(milliseconds: 650),
                    delay: const Duration(milliseconds: 180),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 56,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.7,
                      color: nameColor,
                    ),
                  ),
                  if (!hasKeyboard) ...[
                    const SizedBox(height: 1),
                    _TypewriterText(
                      text: 'This is your safe space.',
                      duration: const Duration(milliseconds: 1100),
                      delay: const Duration(milliseconds: 700),
                      style: GoogleFonts.jost(
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.4,
                        color: const Color(0xFF9A8C78).withOpacity(0.50),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Glass auth panel ───────────────────────────────────────────────────────

  Widget _buildAuthPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          decoration: BoxDecoration(
            color: _surface.withOpacity(0.50),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _cream.withOpacity(0.07), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Inner shimmer
              Positioned(
                top: 0,
                left: 20,
                right: 20,
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.14),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: _showEmailForm ? _buildEmailForm() : _buildLanding(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Landing ────────────────────────────────────────────────────────────────

  Widget _buildLanding() {
    return Column(
      key: const ValueKey('landing'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _PressButton(
          onTap: _isLoading ? null : _handleGoogleSignIn,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: BoxDecoration(
              color: _cream.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cream.withOpacity(0.11)),
            ),
            child: Center(
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_cream),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/google_logo.png',
                          width: 20,
                          height: 20,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.g_mobiledata_rounded,
                            size: 20,
                            color: _cream,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Continue with Google',
                          style: GoogleFonts.jost(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                            color: _cream,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PressButton(
          onTap: () => setState(() {
            _showEmailForm = true;
            _errorMessage = null;
            _errorIsWrongPassword = false;
          }),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 17),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cream.withOpacity(0.05)),
            ),
            child: Center(
              child: Text(
                'Continue with email',
                style: GoogleFonts.jost(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                  color: _sand,
                ),
              ),
            ),
          ),
        ),
        if (_errorMessage != null && !_errorIsWrongPassword) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style:
                GoogleFonts.jost(color: Nocturne.destructive, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  // ─── Email form ─────────────────────────────────────────────────────────────

  Widget _buildEmailForm() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('email_form'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _GlowField(
            child: TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: GoogleFonts.jost(color: _cream, fontSize: 16.0),
              cursorColor: _blueSoft,
              decoration: _dec('Email'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter your email' : null,
            ),
          ),
          const SizedBox(height: 12),
          _GlowField(
            child: TextFormField(
              controller: _passCtrl,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              style: GoogleFonts.jost(color: _cream, fontSize: 16.0),
              cursorColor: _blueSoft,
              decoration: _dec(
                'Password',
                suffix: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _sand.withOpacity(0.55),
                    size: 17,
                  ),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your password';
                if (v.length < 6) return 'At least 6 characters';
                return null;
              },
            ),
          ),
          if (_errorIsWrongPassword) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Incorrect password.',
                style: GoogleFonts.jost(
                    color: Nocturne.destructive, fontSize: 12.5),
              ),
            ),
          ],
          if (_errorMessage != null && !_errorIsWrongPassword) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _errorMessage!,
                style: GoogleFonts.jost(
                    color: Nocturne.destructive, fontSize: 12.5),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _PressButton(
            onTap: _isLoading ? null : _handleEmailAuth,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 17),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_blue, _violet],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _blue.withOpacity(0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text(
                        'Continue',
                        style: GoogleFonts.jost(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _PressButton(
            onTap: _isLoading
                ? null
                : () => setState(() {
                      _showEmailForm = false;
                      _errorMessage = null;
                      _errorIsWrongPassword = false;
                    }),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Back',
                  style: GoogleFonts.jost(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w400,
                    color: _sand,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.jost(color: _sand.withOpacity(0.55), fontSize: 15.5),
        suffixIcon: suffix,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        errorStyle:
            GoogleFonts.jost(color: Nocturne.destructive, fontSize: 11.5),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// TYPEWRITER TEXT
// ═══════════════════════════════════════════════════════════════════════════════

class _TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration duration;
  final Duration delay;
  final VoidCallback? onComplete;

  const _TypewriterText({
    required this.text,
    required this.style,
    required this.duration,
    this.delay = Duration.zero,
    this.onComplete,
  });

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  String _displayed = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      int idx = 0;
      final interval = widget.text.isEmpty
          ? 0
          : widget.duration.inMilliseconds ~/ widget.text.length;
      _timer =
          Timer.periodic(Duration(milliseconds: math.max(1, interval)), (_) {
        if (idx < widget.text.length) {
          if (mounted) setState(() => _displayed += widget.text[idx]);
          idx++;
        } else {
          _timer?.cancel();
          widget.onComplete?.call();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(_displayed, style: widget.style, textAlign: TextAlign.center);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ATMOSPHERIC BACKGROUND
// ═══════════════════════════════════════════════════════════════════════════════

class _AtmosphericBackground extends StatefulWidget {
  final Widget child;
  const _AtmosphericBackground({required this.child});

  @override
  State<_AtmosphericBackground> createState() => _AtmosphericBackgroundState();
}

class _AtmosphericBackgroundState extends State<_AtmosphericBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => CustomPaint(
          painter: _BackgroundPainter(value: _ctrl.value),
          child: child,
        ),
        child: widget.child,
      );
}

class _BackgroundPainter extends CustomPainter {
  final double value;
  const _BackgroundPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    // Deep dark base
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF060810),
    );

    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..blendMode = BlendMode.screen,
    );

    void orb(Offset center, double radius, Color color, double opacity) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withOpacity(opacity),
              color.withOpacity(opacity * 0.22),
              Colors.transparent,
            ],
            stops: const [0.0, 0.48, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    orb(
      Offset(
        size.width * 0.14 + math.sin(value * math.pi * 2) * 18,
        size.height * 0.18 + math.cos(value * math.pi * 2) * 14,
      ),
      size.width * 0.68 + math.sin(value * math.pi) * 36,
      const Color(0xFF7DA2FF),
      0.07,
    );
    orb(
      Offset(
        size.width * 0.86 + math.cos(value * math.pi * 2) * 22,
        size.height * 0.82 + math.sin(value * math.pi * 2) * 18,
      ),
      size.width * 0.78 + math.cos(value * math.pi) * 46,
      const Color(0xFFA78BFA),
      0.06,
    );
    orb(
      Offset(
        size.width * 0.36 + math.cos((value + 0.3) * math.pi * 2) * 28,
        size.height * 0.92 + math.sin((value + 0.3) * math.pi * 2) * 13,
      ),
      size.width * 0.58 + math.sin((value + 0.5) * math.pi) * 28,
      const Color(0xFFF2B8A0),
      0.05,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter old) => old.value != value;
}
