import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../premium.dart';
import '../services/models.dart';
import '../services/worker_backend.dart';
import '../social_shell.dart';
import '../theme.dart';

class ShopHubScreen extends StatefulWidget {
  const ShopHubScreen({
    super.key,
    required this.coins,
    required this.onRefresh,
    required this.onOpenEarn,
    required this.onOpenStore,
    required this.onOpenKeys,
    required this.onOpenTutorials,
    required this.onOpenWallet,
    this.loadProducts,
    this.loadClaims,
  });

  final int coins;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenEarn;
  final VoidCallback onOpenStore;
  final VoidCallback onOpenKeys;
  final VoidCallback onOpenTutorials;
  final VoidCallback onOpenWallet;
  final Future<List<Product>> Function()? loadProducts;
  final Future<List<Claim>> Function()? loadClaims;

  @override
  State<ShopHubScreen> createState() => _ShopHubScreenState();
}

class _ShopHubScreenState extends State<ShopHubScreen> {
  List<Product> _products = const [];
  List<Claim> _claims = const [];
  bool _loading = true;
  bool _productsFailed = false;
  bool _claimsFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _productsFailed = false;
      _claimsFailed = false;
    });
    final results = await Future.wait<Object?>([
      (widget.loadProducts ?? Backend.products)()
          .then<List<Product>>((value) => value)
          .catchError((Object _) {
            _productsFailed = true;
            return <Product>[];
          }),
      (widget.loadClaims ?? Backend.myClaims)()
          .then<List<Claim>>((value) => value)
          .catchError((Object _) {
            _claimsFailed = true;
            return <Claim>[];
          }),
    ]);
    if (!mounted) return;
    setState(() {
      _products = results[0] as List<Product>;
      _claims = results[1] as List<Claim>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: SocialAppBar(
        title: 'Shop',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: CoinPill(coins: widget.coins, onTap: widget.onOpenWallet),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: () async {
          await widget.onRefresh();
          await _load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.xxl,
          ),
          children: [
            GlowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR COINS', style: AppText.label),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    '${groupDigits(widget.coins)} coins',
                    style: AppText.display.copyWith(color: AppColors.gold),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  TextButton(
                    onPressed: widget.onOpenEarn,
                    child: const Text('Earn more'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.onOpenEarn,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Earn coins'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.onOpenStore,
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Browse store'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            SectionHeader(
              title: 'Your keys',
              trailing: TextButton(
                key: const ValueKey('shop-open-keys'),
                onPressed: widget.onOpenKeys,
                child: const Text('View all'),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            if (_loading)
              const LinearProgressIndicator()
            else if (_claimsFailed)
              const Text('Could not load keys', style: AppText.caption)
            else if (_claims.isEmpty)
              const EmptyState(
                icon: Icons.key_outlined,
                title: 'No keys yet',
                message: 'Claim a product to see it here.',
              )
            else
              Row(
                children: [
                  for (final claim in _claims.take(2))
                    Expanded(
                      child: Card(
                        margin: const EdgeInsets.only(right: AppSpace.sm),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                claim.productName.isEmpty
                                    ? 'License key'
                                    : claim.productName,
                                style: AppText.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Text(
                                claim.keyText,
                                style: AppText.figure.copyWith(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: AppSpace.xl),
            SectionHeader(
              title: 'Featured',
              trailing: TextButton(
                onPressed: widget.onOpenStore,
                child: const Text('See all'),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            if (_loading)
              const LinearProgressIndicator()
            else if (_productsFailed)
              const Text(
                'Could not load featured products',
                style: AppText.caption,
              )
            else if (_products.isEmpty)
              const EmptyState(
                icon: Icons.storefront_outlined,
                title: 'No products yet',
                message: 'New items will appear here.',
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpace.sm,
                  crossAxisSpacing: AppSpace.sm,
                  childAspectRatio: 0.95,
                ),
                itemCount: _products.take(4).length,
                itemBuilder: (context, index) {
                  final product = _products[index];
                  final imageUrl = Backend.productThumbUrl(product.imageIds);
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: widget.onOpenStore,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: imageUrl.isEmpty
                                ? Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          AppColors.primaryDeep,
                                          AppColors.primary,
                                        ],
                                      ),
                                    ),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                        const ColoredBox(
                                          color: AppColors.surfaceHigh,
                                        ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(AppSpace.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: AppText.subtitle.copyWith(
                                    fontSize: 12,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '● ${groupDigits(product.cost)}',
                                  style: AppText.caption.copyWith(
                                    color: AppColors.gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: AppSpace.xl),
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: const Text('Tutorials'),
                      onTap: widget.onOpenTutorials,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: const Text('Wallet'),
                      onTap: widget.onOpenWallet,
                    ),
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
