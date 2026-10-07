import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../premium.dart';
import '../theme.dart';

/// Cinematic cold-start splash — motion-driven, never opacity-driven.
///
/// Beat structure (researched from logo-reveal motion practice):
///   1. A radar scan sweeps once behind the emblem.
///   2. The vault ring DRAWS itself on around it (pen-head glow leads).
///   3. Ring locks → emblem pops + glow blooms + haptic beat.
///   4. A light glint sweeps across the logo (confined to its circle).
///   5. GHOSST rises letter-by-letter behind clip masks, tagline follows.
///
/// The emblem photo stays at the exact spot/size of the native Android
/// launch bitmap, so the hand-off is seamless; all motion builds AROUND it.
/// Tap anywhere to skip.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Must match `tool/generate_brand_images.ps1` (130dp splash bitmap).
  static const double _logoSize = 130;
  static const double _ringSize = 186;
  static const String _word = 'GHOSST';
  static const List<String> _tags = ['WATCH', 'EARN', 'CLAIM'];

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..forward();
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  Timer? _finishTimer;
  Timer? _hapticTimer;
  bool _exited = false;

  @override
  void initState() {
    super.initState();
    _finishTimer = Timer(const Duration(milliseconds: 2150), _exit);
    // The "ring locks" beat — synced to the pop at ~0.36 of the intro.
    _hapticTimer = Timer(
      const Duration(milliseconds: 760),
      () => HapticFeedback.mediumImpact().ignore(),
    );
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _hapticTimer?.cancel();
    _intro.dispose();
    _spin.dispose();
    _out.dispose();
    super.dispose();
  }

  /// Eased 0→1 ramp over one slice of the master intro timeline.
  double _seg(double from, double to) {
    final t = _intro.value;
    if (t <= from) return 0;
    if (t >= to) return 1;
    return kPremiumCurve.transform((t - from) / (to - from));
  }

  void _skip() {
    if (_exited) return;
    _intro.value = 1; // reveal everything…
    _exit(); // …then fly out
  }

  void _exit() {
    if (_exited || !mounted) return;
    _exited = true;
    _finishTimer?.cancel();
    _hapticTimer?.cancel();
    _out.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final out = CurvedAnimation(parent: _out, curve: kPremiumCurve);

    // Dolly-in exit: the camera pushes INTO the app, never a plain blink.
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0).animate(out),
      child: Transform.scale(
        scale: 1 + 0.10 * out.value,
        child: Stack(
          children: [
            const MeshBackground(),
            Positioned.fill(child: _body()),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ body

  Widget _body() {
    final spin = _spin.value;
    final draw = _seg(0.02, 0.36); // ring draws itself on
    final settle = _seg(0.36, 0.60); // bright stroke → hairline morph
    final pop = _seg(0.36, 0.50); // lock beat
    final popScale = 1 + 0.05 * math.sin(pop * math.pi);
    final radar = _seg(0.05, 0.58); // single scan rotation
    final radarAlpha = math.sin(radar * math.pi); // fades in and out once
    final glowBase = _seg(0.04, 0.30); // one-shot bloom (never pulses)
    final glow = (glowBase * 0.8 + 0.35 * math.sin(pop * math.pi))
        .clamp(0.0, 1.0);
    final glint = _seg(0.44, 0.68); // light sweep across the emblem
    final progress = _seg(0.0, 0.94); // hairline load bar
    final skipIn = _seg(0.90, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: Column(
        children: [
          Expanded(
            child: Center(
              // Shift the group down so the emblem itself is dead-center —
              // exactly where the native splash bitmap sits.
              child: Transform.translate(
                offset: const Offset(0, 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _emblem(
                      draw: draw,
                      settle: settle,
                      rotation: spin,
                      radar: radar,
                      radarAlpha: radarAlpha,
                      glow: glow,
                      popScale: popScale,
                      glint: glint,
                    ),
                    const SizedBox(height: 30),
                    _wordmark(),
                    const SizedBox(height: 12),
                    _tagline(),
                  ],
                ),
              ),
            ),
          ),
          _loadBar(progress),
          const SizedBox(height: 14),
          Opacity(
            opacity: skipIn,
            child: Text(
              'TAP TO SKIP',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5,
                color: AppColors.textDim.withValues(alpha: 0.8),
              ),
            ),
          ),
          const SizedBox(height: 44),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- emblem

  Widget _emblem({
    required double draw,
    required double settle,
    required double rotation,
    required double radar,
    required double radarAlpha,
    required double glow,
    required double popScale,
    required double glint,
  }) {
    return SizedBox(
      width: _ringSize,
      height: _ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radial bloom — blooms once, never blinks.
          Positioned.fill(
            child: Center(
              child: Opacity(
                opacity: glow,
                child: Transform.scale(
                  scale: 0.94 + 0.06 * glow,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.34),
                          AppColors.primary.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Radar scan, draw-on ring, orbiting comet — one painter.
          CustomPaint(
            size: const Size(_ringSize, _ringSize),
            painter: _VaultRingPainter(
              draw: draw,
              settle: settle,
              rotation: rotation,
              radar: radar,
              radarAlpha: radarAlpha,
            ),
          ),
          // Emblem photo + pop scale + glint — confined to the circle.
          Transform.scale(
            scale: popScale,
            child: SizedBox(
              width: _logoSize,
              height: _logoSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: _logoSize,
                      height: _logoSize,
                      child: Image.asset(
                        'assets/images/logo.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: kNeonGradient,
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 56,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF04212A),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Hairline bezel — appears with the drawn ring.
                  Opacity(
                    opacity: draw,
                    child: Container(
                      width: _logoSize,
                      height: _logoSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                  // Light glint — a masked band sweeping across the logo
                  // only (ClipOval keeps it inside the emblem's alpha).
                  if (glint > 0 && glint < 1)
                    ClipOval(
                      child: SizedBox(
                        width: _logoSize,
                        height: _logoSize,
                        child: Center(
                          child: Transform.translate(
                            offset: Offset(-_logoSize * 0.75 + glint * _logoSize * 1.6, 0),
                            child: Transform.rotate(
                              angle: -0.4,
                              child: Container(
                                width: 20,
                                height: _logoSize * 1.7,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0),
                                      Colors.white.withValues(alpha: 0.55),
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- wordmark

  Widget _wordmark() {
    return ShaderMask(
      shaderCallback: (bounds) => kNeonGradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _word.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            _riseIn(
              _seg(0.48 + i * 0.05, 0.66 + i * 0.05),
              dy: 44,
              child: Text(
                _word[i],
                style: const TextStyle(
                  fontSize: 40,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tagline() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _tags.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: _riseIn(
                _seg(0.72 + i * 0.05, 0.88 + i * 0.05),
                dy: 16,
                child: const Text(
                  '·',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          _riseIn(
            _seg(0.72 + i * 0.05, 0.88 + i * 0.05),
            dy: 16,
            child: Text(
              _tags[i],
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: AppColors.textDim,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- loadbar

  /// Hairline progress that GROWS left-to-right (transform only) — a moving
  /// line reads as loading; a pulsing dot reads as blinking.
  Widget _loadBar(double progress) {
    return SizedBox(
      width: 120,
      child: Stack(
        children: [
          Container(
            height: 1.5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Transform.scale(
            scaleX: progress,
            scaleY: 1,
            alignment: Alignment.centerLeft,
            child: Container(
              height: 1.5,
              width: 120,
              decoration: BoxDecoration(
                gradient: kNeonGradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- helpers

  /// Clip-mask rise: the letter slides UP from behind the clip edge — a
  /// crisp reveal instead of a fade (fades read as blinking).
  Widget _riseIn(double v, {required double dy, required Widget child}) {
    return ClipRect(
      child: Transform.translate(
        offset: Offset(0, dy * (1 - v)),
        child: child,
      ),
    );
  }
}

/// Radar scan → draw-on ring → hairline + orbiting comet + tech dashes.
class _VaultRingPainter extends CustomPainter {
  _VaultRingPainter({
    required this.draw,
    required this.settle,
    required this.rotation,
    required this.radar,
    required this.radarAlpha,
  });

  final double draw; // 0..1 ring draw-on progress
  final double settle; // 0..1 morph bright stroke → hairline
  final double rotation; // 0..1 comet loop position
  final double radar; // 0..1 single scan rotation
  final double radarAlpha; // 0..1 scan visibility (fades once)

  static const double _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 1;
    final rect = Rect.fromCircle(center: center, radius: r);

    // --- Beat 1: radar scan wedge (one full sweep, trails the heading).
    if (radarAlpha > 0.01) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-math.pi / 2 + radar * _tau);
      const sweep = 1.2;
      final local = Rect.fromCircle(center: Offset.zero, radius: r * 0.97);
      final wedge = Path()
        ..moveTo(0, 0)
        ..arcTo(local, -sweep, sweep, false)
        ..close();
      canvas.drawPath(
        wedge,
        Paint()..color = AppColors.primary.withValues(alpha: 0.12 * radarAlpha),
      );
      canvas.drawLine(
        Offset.zero,
        Offset(math.cos(0) * r * 0.97, math.sin(0) * r * 0.97),
        Paint()
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = AppColors.cyan.withValues(alpha: 0.5 * radarAlpha),
      );
      canvas.restore();
    }

    // --- Beat 2: the ring draws itself on, pen-head glow leading.
    if (draw > 0.001) {
      final bright = Color.lerp(
        AppColors.cyan.withValues(alpha: 0.95),
        Colors.white.withValues(alpha: 0.12),
        settle,
      )!;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        _tau * draw,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 + (1.3 - 2.2) * settle
          ..strokeCap = StrokeCap.round
          ..color = bright,
      );
      if (draw < 0.999) {
        // The "pen" — where the stroke is being written right now.
        final theta = -math.pi / 2 + _tau * draw;
        final head = Offset(
          center.dx + r * math.cos(theta),
          center.dy + r * math.sin(theta),
        );
        canvas.drawCircle(
          head,
          8,
          Paint()..color = AppColors.primary.withValues(alpha: 0.28),
        );
        canvas.drawCircle(head, 3, Paint()..color = AppColors.cyan);
      }
    }

    // --- Beat 3: counter-rotating tech dashes (vault mechanism).
    final dashAlpha = ((draw - 0.9) / 0.1).clamp(0.0, 1.0);
    if (dashAlpha > 0.01) {
      final base = -rotation * _tau * 0.5;
      final dashRect = Rect.fromCircle(center: center, radius: r - 9);
      for (var i = 0; i < 3; i++) {
        canvas.drawArc(
          dashRect,
          base + i * _tau / 3,
          0.55,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: 0.16 * dashAlpha),
        );
      }
    }

    // --- Beat 4: orbiting light comet once the ring is closed.
    if (settle > 0.01) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation * _tau);
      canvas.translate(-center.dx, -center.dy);
      const start = -math.pi / 2;
      const sweep = 1.25;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: start,
            endAngle: start + sweep,
            colors: [
              AppColors.primary.withValues(alpha: 0),
              AppColors.primary.withValues(alpha: 0.85 * settle),
              AppColors.cyan.withValues(alpha: settle),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(rect),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _VaultRingPainter old) =>
      old.draw != draw ||
      old.settle != settle ||
      old.rotation != rotation ||
      old.radar != radar ||
      old.radarAlpha != radarAlpha;
}
