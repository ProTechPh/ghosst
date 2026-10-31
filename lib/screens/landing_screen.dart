import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../arcade.dart';
import '../premium.dart';
import '../theme.dart';

/// Signed-out landing: one oversized promise, the key itself as the product
/// shot, a single ticker, and the action pinned to the bottom.
class LandingScreen extends StatelessWidget {
  const LandingScreen({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
  });

  final VoidCallback onSignIn;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ArcadeBackdrop(),
        Positioned.fill(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpace.xl,
                        AppSpace.lg,
                        AppSpace.xl,
                        0,
                      ),
                      child: _BrandRow(),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.xl,
                          AppSpace.xl,
                          AppSpace.xl,
                          AppSpace.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ScrollReveal(
                              child: Text(
                                'REWARDED ADS  ·  LICENSE KEYS',
                                style: monoStyle(
                                  fontSize: 10,
                                  letterSpacing: 2.4,
                                  color: AppColors.primary.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpace.md),
                            const ScrollReveal(
                              delay: Duration(milliseconds: 60),
                              child: _HeroTitle(),
                            ),
                            const SizedBox(height: AppSpace.md),
                            const ScrollReveal(
                              delay: Duration(milliseconds: 130),
                              child: Text(
                                'One rewarded ad pays 10 coins. Trade them for a license key or a verified app download.',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  height: 1.5,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpace.lg),
                            const _Settle(child: _HeroArtifact()),
                            const SizedBox(height: AppSpace.lg),
                            const _Ticker(),
                            const SizedBox(height: AppSpace.xl),
                            const ScrollReveal(
                              delay: Duration(milliseconds: 120),
                              child: _Steps(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.xl,
                        AppSpace.sm,
                        AppSpace.xl,
                        AppSpace.xl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NeonButton(
                            expand: true,
                            glow: true,
                            onPressed: onSignUp,
                            child: const Text('Create account'),
                          ),
                          Center(
                            child: TextButton(
                              onPressed: onSignIn,
                              child: const Text('I already have an account'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two lines of display type that scale to the width instead of wrapping.
class _HeroTitle extends StatelessWidget {
  const _HeroTitle();

  @override
  Widget build(BuildContext context) {
    final style = AppText.display.copyWith(
      fontSize: 56,
      height: 0.96,
      letterSpacing: -1.6,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Watch ads.', style: style),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: GradientText('Unlock keys.', style: style),
        ),
      ],
    );
  }
}

/// Quiet brand row at the top — the headline below carries the screen.
class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const LogoBadge(size: 32),
        const SizedBox(width: AppSpace.sm + 2),
        Text(
          'GHOSST',
          style: AppText.label.copyWith(
            color: AppColors.textDim,
            letterSpacing: 3.2,
          ),
        ),
        const Spacer(),
        Text(
          'COIN ARCADE',
          style: monoStyle(
            fontSize: 10,
            letterSpacing: 1.6,
            color: AppColors.primary.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// The key, a coin, and the rings it sits on — drawn, not screenshotted.
class _HeroArtifact extends StatelessWidget {
  const _HeroArtifact();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 272,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(child: CustomPaint(painter: _RingPainter())),
          const Positioned(
            left: -6,
            child: KeyMark(size: 246, angle: -0.44, glow: false),
          ),
          const Positioned(right: 0, bottom: 6, child: CoinMedallion(size: 92)),
          Positioned(
            left: 0,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.xs + 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.bg.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '1 AD  →  10 COINS',
                style: monoStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: AppColors.textDim,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.52, size.height * 0.48);
    for (var i = 0; i < 3; i++) {
      final radius = size.width * (0.30 + i * 0.11);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -2.5,
        3.4,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.primary.withValues(alpha: 0.16 - i * 0.04),
      );
    }
    // Four chips of light where the innermost ring breaks.
    final dot = Paint()..color = AppColors.cyan.withValues(alpha: 0.5);
    for (var i = 0; i < 4; i++) {
      final angle = -2.4 + i * 0.55;
      canvas.drawCircle(
        center +
            Offset(
              (size.width * 0.30) * math.cos(angle),
              (size.width * 0.30) * math.sin(angle),
            ),
        1.6,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => false;
}

/// One slow ticker across the table. Pauses entirely under reduced motion.
class _Ticker extends StatefulWidget {
  const _Ticker();

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> with SingleTickerProviderStateMixin {
  static const _unit =
      '10 COINS PER AD  ·  LICENSE KEYS  ·  VERIFIED DOWNLOADS  ·  ';

  late final AnimationController _scroll = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 34),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.stop();
      _scroll.value = 0;
    } else if (!_scroll.isAnimating) {
      _scroll.repeat();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = monoStyle(
      fontSize: 10.5,
      letterSpacing: 2.2,
      color: AppColors.textDim.withValues(alpha: 0.75),
    );
    return SizedBox(
      height: 18,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: _unit, style: style),
              textDirection: TextDirection.ltr,
            )..layout();
            final unit = painter.width;
            painter.dispose();
            final copies = (constraints.maxWidth / unit).ceil() + 2;
            return OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: AnimatedBuilder(
                animation: _scroll,
                builder: (context, child) => Transform.translate(
                  offset: Offset(-unit * _scroll.value, 0),
                  child: child,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < copies; i++)
                      Text(_unit, style: style, maxLines: 1),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps();

  static const _steps = <(String, String)>[
    ('Watch', 'One rewarded ad pays 10 coins.'),
    ('Spend', 'Trade them for a license key or an app download.'),
    ('Keep', 'Every purchase stays saved in your account.'),
  ];

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.white.withValues(alpha: 0.08);
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: hairline)),
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _steps[i].$1,
                        style: AppText.subtitle.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        _steps[i].$2,
                        style: AppText.caption.copyWith(
                          height: 1.45,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Text(
                  '0${i + 1}',
                  style: monoStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: AppColors.primary.withValues(alpha: 0.16),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Settles the hero in from a slight tilt once, and stays still after that.
class _Settle extends StatefulWidget {
  const _Settle({required this.child});

  final Widget child;

  @override
  State<_Settle> createState() => _SettleState();
}

class _SettleState extends State<_Settle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (_c.status == AnimationStatus.dismissed) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = kOvershootCurve.transform(_c.value);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: (1 - t) * 0.05,
            child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}
