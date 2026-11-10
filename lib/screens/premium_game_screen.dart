import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../premium.dart';
import '../services/models.dart';
import '../theme.dart';

/// Website game page in read-only form: image carousel, versions with ₱
/// prices and stock. Every Buy opens that product on ghossthub.com.
class PremiumGameScreen extends StatefulWidget {
  const PremiumGameScreen({super.key, required this.game});

  final ShopGame game;

  @override
  State<PremiumGameScreen> createState() => _PremiumGameScreenState();
}

class _PremiumGameScreenState extends State<PremiumGameScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _open(ShopProduct item) async {
    final uri = Uri.tryParse(item.url);
    if (uri == null || uri.host.isEmpty) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Premium] could not open checkout: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(game.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xxl),
        children: [
          if (game.images.isNotEmpty) ...[
            SizedBox(
              height: 210,
              child: PageView.builder(
                controller: _pages,
                itemCount: game.images.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: CachedNetworkImage(
                      imageUrl: game.images[i],
                      fit: BoxFit.cover,
                      memCacheWidth: 900,
                      errorWidget: (context, url, e) => _fallback(),
                    ),
                  ),
                ),
              ),
            ),
            if (game.images.length > 1) ...[
              const SizedBox(height: AppSpace.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < game.images.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? AppColors.primary
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ],
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: SizedBox(height: 160, child: _fallback()),
              ),
            ),
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
                  _versionCard(p),
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

  Widget _versionCard(ShopProduct p) {
    return Pressable(
      onTap: () => _open(p),
      semanticLabel: '${p.name}, ${p.priceLabel}, buy on ghossthub.com',
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
                    ? _fallback()
                    : CachedNetworkImage(
                        imageUrl: p.image,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        errorWidget: (context, url, e) => _fallback(),
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
                  'Buy',
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

  Widget _fallback() => ColoredBox(
    color: AppColors.surfaceHigh,
    child: Center(
      child: Icon(
        Icons.sports_esports_outlined,
        color: AppColors.textDim.withValues(alpha: .7),
      ),
    ),
  );
}
