import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../appwrite_client.dart';
import '../premium.dart';
import '../services/backend.dart';
import '../theme.dart';
import 'product_detail.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({
    super.key,
    required this.coins,
    required this.onRefresh,
    this.active = true,
    this.onOpenWallet,
    this.onGoToEarn,
  });

  final int coins;
  final Future<void> Function() onRefresh;

  /// Whether this tab is the currently visible one (see didUpdateWidget).
  final bool active;

  /// Opens the wallet (coin balance card).
  final VoidCallback? onOpenWallet;

  /// Jumps to the Earn tab.
  final VoidCallback? onGoToEarn;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen>
    with SingleTickerProviderStateMixin {
  List<Product> products = [];
  Map<String, int> stock = {};
  bool loading = true;
  String error = '';

  /// Soft pulse for the skeleton placeholders (opacity only).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StoreScreen old) {
    super.didUpdateWidget(old);
    // IndexedStack keeps this tab's data forever — refresh silently whenever
    // the tab becomes visible again (e.g. after editing products in Admin).
    if (widget.active && !old.active) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        error = '';
      });
    }
    try {
      final ps = await Backend.products();
      final counts = <String, int>{};
      // Stock counts are only readable by admins (team:admins can read `keys`).
      if (await Backend.isAdmin()) {
        for (final p in ps) {
          counts[p.id] = await Backend.availableCount(p.id);
        }
      }
      if (!mounted) return;
      setState(() {
        products = ps;
        stock = counts;
        if (!silent) loading = false;
      });
    } catch (e) {
      // Silent refresh failures keep showing the last good data.
      if (silent || !mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  Future<void> _openDetail(Product p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: p,
          coins: widget.coins,
          stock: stock[p.id] ?? -1,
          onRefresh: widget.onRefresh,
        ),
      ),
    );
    // Reload stock/availability after coming back (claim may have happened).
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return _skeleton();
    if (error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load store',
            message: error,
            action: IslandButton(
              expand: false,
              dense: true,
              outline: true,
              glow: false,
              label: 'Retry',
              icon: CupertinoIcons.arrow_clockwise,
              onPressed: _load,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
        children: [
          // ---- editorial header ----------------------------------------
          ScrollReveal(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow(text: 'License store'),
                const SizedBox(height: 16),
                const Text(
                  'Spend coins,\nclaim keys',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Every claim gives you a fresh, unused license key.',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // ---- balance hero --------------------------------------------
          ScrollReveal(
            delay: const Duration(milliseconds: 110),
            child: PressableScale(
              onTap: widget.onOpenWallet,
              child: DoubleBezel(
                padding: const EdgeInsets.all(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0E2229), Color(0xFF07161B)],
                ),
                glowColor: AppColors.gold,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'YOUR BALANCE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.2,
                              color: AppColors.textDim,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              AnimatedCounter(
                                value: widget.coins,
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.gold,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'coins',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: kGoldGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.35),
                            blurRadius: 24,
                            spreadRadius: -6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.monetization_on_outlined,
                        size: 24,
                        color: Color(0xFF422006),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.onGoToEarn != null) ...[
            const SizedBox(height: 12),
            ScrollReveal(
              delay: const Duration(milliseconds: 170),
              child: IslandButton(
                dense: true,
                outline: true,
                glow: false,
                label: 'Watch ads to top up',
                icon: CupertinoIcons.play_rectangle,
                onPressed: widget.onGoToEarn,
              ),
            ),
          ],
          const SizedBox(height: 30),

          // ---- products -------------------------------------------------
          const SectionLabel('AVAILABLE KEYS'),
          if (products.isEmpty)
            const ScrollReveal(
              child: EmptyState(
                icon: Icons.storefront_outlined,
                title: 'No products yet',
                message: 'Check back soon — new keys drop regularly.',
              ),
            ),
          for (var i = 0; i < products.length; i++) ...[
            ScrollReveal(
              delay: Duration(milliseconds: (60 * i).clamp(0, 400)),
              child: _productCard(products[i]),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 22),
          const Center(
            child: Text(
              'FRESH DROPS · DELIVERED INSTANTLY',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
                color: AppColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- loading skeleton ----------------------------------------------
  Widget _skeletonBox(double? width, double height, {double radius = 12}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _skeleton() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Opacity(
        opacity: 0.45 + 0.35 * _pulse.value,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
          children: [
            _skeletonBox(138, 26, radius: 99),
            const SizedBox(height: 16),
            _skeletonBox(224, 32, radius: 12),
            const SizedBox(height: 8),
            _skeletonBox(224, 32, radius: 12),
            const SizedBox(height: 10),
            _skeletonBox(258, 14, radius: 99),
            const SizedBox(height: 22),
            _skeletonBox(null, 94, radius: 26),
            const SizedBox(height: 30),
            _skeletonBox(124, 14, radius: 99),
            const SizedBox(height: 14),
            for (var i = 0; i < 3; i++) ...[
              _skeletonBox(null, 94, radius: 26),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  // ---- product card ----------------------------------------------------
  Widget _thumb(Product p) {
    const size = 60.0;
    if (p.imageIds.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          Backend.imageUrl(p.imageIds.first, width: 200),
          headers: const {'X-Appwrite-Project': appwriteProjectId},
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, e, s) => _thumbFallback(size),
        ),
      );
    }
    return _thumbFallback(size);
  }

  Widget _thumbFallback(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: kTealGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.key_rounded, color: Colors.white, size: 26),
      );

  Widget _productCard(Product p) {
    final count = stock[p.id] ?? -1;
    final desc = p.description.trim();

    return PressableScale(
      scale: 0.98,
      onTap: () => _openDetail(p),
      child: DoubleBezel(
        radius: 24,
        outerPadding: const EdgeInsets.all(5),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _thumb(p),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      desc,
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      NeonPill(
                        icon: Icons.monetization_on_rounded,
                        label: '${p.cost} coins',
                        color: AppColors.gold,
                      ),
                      if (count >= 0)
                        count == 0
                            ? const NeonPill(
                                icon: Icons.remove_shopping_cart_outlined,
                                label: 'Out of stock',
                                color: AppColors.red,
                              )
                            : NeonPill(
                                icon: Icons.inventory_2_outlined,
                                label: '$count in stock',
                                color: AppColors.green,
                              ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: const Icon(
                CupertinoIcons.chevron_right,
                size: 15,
                color: AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
