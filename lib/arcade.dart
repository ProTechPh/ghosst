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

