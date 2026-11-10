import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../premium.dart';
import '../services/worker_backend.dart';
import '../theme.dart';
import 'premium_carousel.dart';

/// Read-only version page, like the website's checkout.php: gallery, name,
/// description and details. "Buy" hands the product to ghossthub.com.
class PremiumProductScreen extends StatefulWidget {
  const PremiumProductScreen({
    super.key,
    required this.game,
    required this.product,
  });

  final String game;
  final ShopProduct product;

  @override
  State<PremiumProductScreen> createState() => _PremiumProductScreenState();
}

class _PremiumProductScreenState extends State<PremiumProductScreen> {
  late ShopProduct _product = widget.product;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final product = await Backend.premiumProduct(widget.product.id);
      if (mounted) {
        setState(() {
          _product = product;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Premium] details unavailable: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buy() async {
    final uri = Uri.tryParse(_product.url);
    if (uri == null || uri.host.isEmpty) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Premium] could not open checkout: $e');
    }
  }

  Widget _durationRow(ShopDuration d) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm + 2,
      ),
      decoration: BoxDecoration(
        color: d.soldOut
            ? AppColors.surface.withValues(alpha: .5)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input + 2),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              d.label,
              style: AppText.subtitle.copyWith(
                fontSize: 13,
                color: d.soldOut ? AppColors.textDim : AppColors.text,
              ),
            ),
          ),
          Text(
            d.soldOut ? 'Sold out' : '${d.stock} left',
            style: AppText.caption.copyWith(
              fontSize: 11,
              color: d.soldOut ? AppColors.red : AppColors.green,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Text(
            d.priceLabel,
            style: AppText.figure.copyWith(
              fontSize: 14,
              color: d.soldOut ? AppColors.textDim : AppColors.gold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final images = product.gallery.isNotEmpty
        ? product.gallery
        : (product.image.isEmpty ? const <String>[] : [product.image]);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 128),
            children: [
              const SizedBox(height: AppSpace.sm),
              PremiumCarousel(images: images),
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
                    Eyebrow(text: widget.game),
                    const SizedBox(height: AppSpace.sm),
                    Text(product.name, style: AppText.headline),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        Eyebrow(text: product.platformLabel),
                        Eyebrow(
                          text: '${product.stock} in stock',
                          color: AppColors.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      product.priceLabel,
                      style: AppText.figure.copyWith(
                        fontSize: 22,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xl),
                    if (_loading)
                      const Skeleton(height: 120, radius: AppRadius.card)
                    else ...[
                      if (product.durations.isNotEmpty) ...[
                        Text(
                          'Available durations',
                          style: AppText.subtitle.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: AppSpace.sm),
                        for (final d in product.durations) _durationRow(d),
                        const SizedBox(height: AppSpace.lg),
                      ],
                      if (product.description.isNotEmpty) ...[
                        Text(
                          'About',
                          style: AppText.subtitle.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(product.description, style: AppText.caption),
                        const SizedBox(height: AppSpace.lg),
                      ],
                      if (product.details.isNotEmpty) ...[
                        Text(
                          'Details',
                          style: AppText.subtitle.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          product.details,
                          style: AppText.caption.copyWith(height: 1.45),
                        ),
                      ],
                      if (product.description.isEmpty &&
                          product.details.isEmpty)
                        Text(
                          'No description yet - see the full listing on ghossthub.com.',
                          style: AppText.caption,
                        ),
                    ],
                    const SizedBox(height: AppSpace.xl),
                    Text(
                      'Checkout finishes on ghossthub.com - in-app payment is coming soon.',
                      style: AppText.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.sm,
                AppSpace.xl,
                AppSpace.lg,
              ),
              child: IslandButton(
                label: 'Buy on ghossthub.com',
                icon: CupertinoIcons.arrow_up_right,
                onPressed: _buy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
