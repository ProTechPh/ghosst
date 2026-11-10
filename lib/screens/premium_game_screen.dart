import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../premium.dart';
import '../services/models.dart';
import '../theme.dart';
import 'premium_carousel.dart';
import 'premium_product_screen.dart';

/// Website game page in read-only form: image carousel, description, and
/// versions with prices/stock. A version opens its own detail page.
class PremiumGameScreen extends StatelessWidget {
  const PremiumGameScreen({super.key, required this.game});

  final ShopGame game;

  void _openProduct(BuildContext context, ShopProduct product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PremiumProductScreen(game: game.name, product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(game.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xxl),
        children: [
          const SizedBox(height: AppSpace.sm),
          PremiumCarousel(images: game.images),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.lg,
              AppSpace.xl,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(game.name, style: AppText.headline),
                if (game.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(game.description, style: AppText.caption),
                ],
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Text(
                      game.priceLabel,
                      style: AppText.figure.copyWith(
                        fontSize: 18,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Text(
                      '${game.stock} keys in stock',
                      style: AppText.caption.copyWith(
                        fontSize: 11,
                        color: AppColors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xl),
                SectionHeader(
                  title: 'Versions',
                  trailing: Text(
                    '${game.products.length}',
                    style: AppText.figure.copyWith(
                      fontSize: 12,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                for (final p in game.products) ...[
                  _versionCard(context, p),
                  const SizedBox(height: AppSpace.sm),
                ],
                const SizedBox(height: AppSpace.sm),
                Text(
                  'Checkout finishes on ghossthub.com - in-app payment is coming soon.',
                  style: AppText.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _versionCard(BuildContext context, ShopProduct p) {
    return Pressable(
      onTap: () => _openProduct(context, p),
      semanticLabel: '${p.name}, ${p.priceLabel}, view details',
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm + 2),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.input + 2),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: SizedBox(
                width: 56,
                height: 56,
                child: p.image.isEmpty
                    ? const PremiumImageFallback()
                    : CachedNetworkImage(
                        imageUrl: p.image,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        errorWidget: (context, url, e) =>
                            const PremiumImageFallback(),
                      ),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.subtitle.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.platformLabel} · ${p.stock} in stock',
                    style: AppText.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  p.priceLabel,
                  style: AppText.figure.copyWith(
                    fontSize: 13,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'View',
                  style: AppText.label.copyWith(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
