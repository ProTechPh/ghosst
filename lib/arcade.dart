import 'dart:math';

import 'package:flutter/material.dart';

import 'premium.dart';
import 'services/models.dart';
import 'theme.dart';

/// Price tier. Derived at render time; never stored on the product.
enum RarityTier { standard, plus, prime, vault }

RarityTier tierForCost(int cost) {
  if (cost < 500) return RarityTier.standard;
  if (cost < 1500) return RarityTier.plus;
  if (cost < 3000) return RarityTier.prime;
  return RarityTier.vault;
}

/// Lowest selectable price — shelf and detail page must agree on the tier.
int entryCost(Product p) => p.hasDurations
    ? p.durations.map((d) => d.cost).reduce((a, b) => a < b ? a : b)
    : p.cost;

/// `-1` means stock is unknown (non-key product or not fetched yet).
bool isSoldOutCard({required bool isKey, required int stock}) =>
    isKey && stock == 0;

String cardMeta(Product p) {
  if (p.isKey) return 'License key';
  if (p.isApk) return p.version.isEmpty ? 'APK' : 'APK ${p.version}';
  return p.fileSize.isEmpty ? 'FILE' : 'FILE · ${p.fileSize}';
}

String cardType(Product p) => p.isKey ? 'KEY' : (p.isApk ? 'APK' : 'FILE');

Color edgeColor(RarityTier tier) => switch (tier) {
  RarityTier.standard => AppColors.border,
  RarityTier.plus => AppColors.cyan,
  RarityTier.prime => AppColors.primary,
  RarityTier.vault => AppColors.gold,
};

Gradient rarityEdge(RarityTier tier) => switch (tier) {
  RarityTier.standard => const LinearGradient(
    colors: [AppColors.border, AppColors.border],
  ),
  RarityTier.plus => LinearGradient(
    colors: [AppColors.cyan.withValues(alpha: .85), AppColors.border],
  ),
  RarityTier.prime => kTealGradient,
  RarityTier.vault => kGoldGradient,
};

/// A card body: 1 px rarity edge, dark core, optional static holo sheen.
class CardFrame extends StatelessWidget {
  const CardFrame({
    super.key,
    required this.child,
    this.tier = RarityTier.standard,
    this.radius = AppRadius.card,
    this.holo = false,
    this.glow = false,
  });

  final Widget child;
  final RarityTier tier;
  final double radius;
  final bool holo;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final inner = (radius - 1).clamp(0.0, double.infinity);
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        gradient: rarityEdge(tier),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: edgeColor(tier).withValues(alpha: .32),
                  blurRadius: 26,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(inner),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C1C22), Color(0xFF071317)],
            ),
          ),
          child: Stack(
            children: [
              child,
              if (holo)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0, .45, 1],
                          colors: [
                            AppColors.gold.withValues(alpha: .08),
                            Colors.transparent,
                            AppColors.cyan.withValues(alpha: .06),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _CornerTicks(edgeColor(tier))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Price + type strip pinned to a card corner.
class CardIndex extends StatelessWidget {
  const CardIndex({super.key, required this.cost, required this.type});

  final int cost;
  final String type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.monetization_on_rounded,
            size: 12,
            color: AppColors.gold,
          ),
          const SizedBox(width: 4),
          Text(
            groupDigits(cost),
            style: AppText.figure.copyWith(
              fontSize: 11.5,
              color: AppColors.gold,
            ),
          ),
          const Spacer(),
          Text(
            type,
            style: AppText.label.copyWith(
              fontSize: 10,
              letterSpacing: 1.6,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// Static felt/dot-grid backdrop; no animation, no repaint.
class TableSurface extends StatelessWidget {
  const TableSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: CustomPaint(painter: _TablePainter()));
  }
}

/// Three to five overlapping chips, back-to-front.
class ChipStack extends StatelessWidget {
  const ChipStack({super.key, this.count = 3, this.size = 46});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = count.clamp(3, 5);
    final step = size * .55;
    final chipHeight = size * .78;
    return SizedBox(
      width: size + step * (n - 1),
      height: chipHeight,
      child: Stack(
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: step * i,
              top: i.isOdd ? 2 : 0,
              child: Container(
                width: size,
                height: chipHeight,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.all(
                    Radius.elliptical(size / 2, chipHeight / 2),
                  ),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: .45),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CornerTicks extends CustomPainter {
  const _CornerTicks(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .35)
      ..strokeWidth = 1;
    const len = 8.0;
    const inset = 6.0;
    final w = size.width;
    final h = size.height;
    final points = <(Offset, Offset)>[
      (Offset(inset, inset + len), Offset(inset, inset)),
      (Offset(inset, inset), Offset(inset + len, inset)),
      (Offset(w - inset - len, inset), Offset(w - inset, inset)),
      (Offset(w - inset, inset), Offset(w - inset, inset + len)),
      (Offset(inset, h - inset - len), Offset(inset, h - inset)),
      (Offset(inset, h - inset), Offset(inset + len, h - inset)),
      (Offset(w - inset - len, h - inset), Offset(w - inset, h - inset)),
      (Offset(w - inset, h - inset), Offset(w - inset, h - inset - len)),
    ];
    for (final (a, b) in points) {
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornerTicks old) => old.color != color;
}

class _TablePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = AppColors.cyan.withValues(alpha: .035);
    for (double x = 14; x < size.width; x += 28) {
      for (double y = 14; y < size.height; y += 28) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }
    final vignette = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.bg.withValues(alpha: .4), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 180));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 180), vignette);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Enters by flipping on the Y axis; lands once, then a short glow pulse.
class CardFlip extends StatefulWidget {
  const CardFlip({
    super.key,
    required this.child,
    this.tier = RarityTier.standard,
    this.duration = const Duration(milliseconds: 720),
    this.onLanded,
  });

  final Widget child;
  final RarityTier tier;
  final Duration duration;
  final VoidCallback? onLanded;

  @override
  State<CardFlip> createState() => _CardFlipState();
}

class _CardFlipState extends State<CardFlip> with TickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  bool _started = false;
  bool _reduced = false;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _flip.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_reduced) _land();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reduced = true;
      _flip.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _land());
    } else {
      _flip.forward();
    }
  }

  void _land() {
    if (_fired || !mounted) return;
    _fired = true;
    widget.onLanded?.call();
    if (!_reduced) _pulse.repeat(reverse: true, count: 2);
  }

  @override
  void dispose() {
    _flip.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_flip, _pulse]),
      builder: (context, _) {
        final v = _reduced ? 1.0 : kPremiumCurve.transform(_flip.value);
        final glow = _pulse.value;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0012)
            ..rotateY(pi * v),
          child: v < .5
              ? _CardBack(tier: widget.tier)
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(pi),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      boxShadow: glow > 0
                          ? [
                              BoxShadow(
                                color: edgeColor(
                                  widget.tier,
                                ).withValues(alpha: .55 * glow),
                                blurRadius: 28,
                              ),
                            ]
                          : null,
                    ),
                    child: widget.child,
                  ),
                ),
        );
      },
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({required this.tier});

  final RarityTier tier;

  @override
  Widget build(BuildContext context) {
    return CardFrame(
      tier: tier,
      holo: tier == RarityTier.vault,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LogoBadge(size: 64),
            const SizedBox(height: AppSpace.md),
            Text(
              'GHOSST',
              style: AppText.label.copyWith(
                letterSpacing: 5,
                color: AppColors.textDim,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Container(
              height: 1,
              width: 96,
              decoration: BoxDecoration(gradient: rarityEdge(tier)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short damped shake. Used once, on the claim landing.
class ShakeBox extends StatefulWidget {
  const ShakeBox({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<ShakeBox> createState() => _ShakeBoxState();
}

class _ShakeBoxState extends State<ShakeBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _c.forward();
  }

  @override
  void didUpdateWidget(ShakeBox old) {
    super.didUpdateWidget(old);
    if (!old.enabled && widget.enabled) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = _c.value;
        return Transform.translate(
          offset: Offset(6 * sin(v * pi * 3) * (1 - v), 0),
          child: child,
        );
      },
    );
  }
}

/// A gold token that arcs from a point to another and reports once.
/// The big glowing coin disc at the centre of a coin-arcade screen: a soft
/// bloom, a ring, then a darker core holding the emblem.
class CoinMedallion extends StatelessWidget {
  const CoinMedallion({super.key, this.size = 140, this.child});

  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.6,
      height: size * 1.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 1.6,
            height: size * 1.6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.30),
                  AppColors.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: -6,
                ),
              ],
            ),
          ),
          Container(
            width: size * 0.82,
            height: size * 0.82,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.surfaceHigh, AppColors.bgSoft],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child:
                child ??
                Icon(
                  Icons.monetization_on_rounded,
                  size: size * 0.42,
                  color: AppColors.gold,
                ),
          ),
        ],
      ),
    );
  }
}

/// Signed-out backdrop: mesh, table dots, one cyan bloom up top and a
/// near-black fade at the bottom so the pinned CTA always sits on ink.
/// The product drawn as itself: a gold key on a gradient core, bowed and
/// toothed, for the signed-out hero and as an auth watermark.
class KeyMark extends StatelessWidget {
  const KeyMark({
    super.key,
    this.size = 220,
    this.angle = -0.5,
    this.opacity = 1,
    this.glow = true,
  });

  final double size;
  final double angle;
  final double opacity;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Opacity(
        opacity: opacity,
        child: SizedBox(
          width: size,
          height: size * 0.62,
          child: CustomPaint(painter: _KeyPainter(glow: glow)),
        ),
      ),
    );
  }
}

class _KeyPainter extends CustomPainter {
  const _KeyPainter({required this.glow});

  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bow = Offset(w * 0.22, h * 0.5);
    final radius = w * 0.16;
    final shaftTop = h * 0.455;
    final shaftHeight = h * 0.09;

    var body = Path()..addOval(Rect.fromCircle(center: bow, radius: radius));
    body = Path.combine(
      PathOperation.union,
      body,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(bow.dx, shaftTop, w * 0.9, shaftTop + shaftHeight),
          Radius.circular(shaftHeight / 2),
        ),
      ),
    );
    for (final x in const [0.62, 0.73, 0.84]) {
      body = Path.combine(
        PathOperation.union,
        body,
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              w * x,
              shaftTop + shaftHeight - 1,
              w * x + w * 0.035,
              shaftTop + shaftHeight + h * 0.12,
            ),
            Radius.circular(w * 0.014),
          ),
        ),
      );
    }

    canvas.saveLayer(Offset.zero & size, Paint());
    if (glow) {
      canvas.drawPath(
        body,
        Paint()
          ..color = AppColors.gold.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }
    canvas.drawPath(
      body,
      Paint()
        ..shader = kGoldGradient.createShader(
          Rect.fromLTWH(0, shaftTop, w, shaftTop + shaftHeight),
        ),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.45),
    );
    // Punch the bow's hole through so the backdrop shows inside the key.
    canvas.drawCircle(bow, radius * 0.5, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KeyPainter old) => old.glow != glow;
}

class ArcadeBackdrop extends StatelessWidget {
  const ArcadeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const MeshBackground(),
        const Positioned.fill(child: IgnorePointer(child: TableSurface())),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.05),
                  radius: 1.15,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.20),
                    AppColors.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(0, -0.2),
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bg.withValues(alpha: 0),
                    AppColors.bg.withValues(alpha: 0.92),
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

class FloatingCoin extends StatefulWidget {
  const FloatingCoin({
    super.key,
    required this.from,
    required this.to,
    required this.label,
    this.onLanded,
  });

  final Offset from;
  final Offset to;
  final String label;
  final VoidCallback? onLanded;

  @override
  State<FloatingCoin> createState() => _FloatingCoinState();
}

class _FloatingCoinState extends State<FloatingCoin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _started = false;
  bool _reduced = false;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_reduced) _land();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reduced = true;
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _land());
    } else {
      _c.forward();
    }
  }

  void _land() {
    if (_fired || !mounted) return;
    _fired = true;
    widget.onLanded?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Offset _position(double t) {
    final control = Offset(
      (widget.from.dx + widget.to.dx) / 2,
      (widget.from.dy + widget.to.dy) / 2 - 90,
    );
    final a = Offset.lerp(widget.from, control, t)!;
    final b = Offset.lerp(control, widget.to, t)!;
    return Offset.lerp(a, b, t)!;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final p = _position(t);
            final opacity = t < .15 ? t / .15 : (t > .8 ? (1 - t) / .2 : 1.0);
            return Stack(
              children: [
                Positioned(
                  left: p.dx - 14,
                  top: p.dy - 14,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: kGoldGradient,
                          ),
                          child: const Icon(
                            Icons.monetization_on_rounded,
                            size: 18,
                            color: AppColors.bg,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.label,
                          style: AppText.figure.copyWith(
                            fontSize: 13,
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
