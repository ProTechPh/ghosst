import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../appwrite_client.dart';
import '../premium.dart';
import '../services/ad_service.dart';
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

  /// Which shelf is showing: `'key'` (licenses) or `'app'` (APK/file).
  String _tab = 'key';

  /// True after the first Keys↔Apps switch — product cards then render
  /// instantly (no ScrollReveal mount delay), which is what made the shelf
  /// swap feel laggy.
  bool _switchedShelf = false;

  /// Product ids the signed-in user already bought (repeat buys are disabled
  /// for app-store items — they'd spend coins on a link they already own).
  Set<String> owned = {};

  /// Soft pulse for the skeleton placeholders (opacity only).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..repeat(reverse: true);

  /// Sponsored native card at the end of the shelf (passive revenue).
  NativeAd? _nativeAd;
  bool _nativeLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadNative();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _nativeAd?.dispose();
    _nativeAd = null;
    super.dispose();
  }

  /// Medium native template, styled dark to match the store chrome.
  /// Rendered only after [onAdLoaded] — a failed ad simply never shows.
  void _loadNative() {
    NativeAd(
      adUnitId: AdUnits.native,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (a) {
          if (!mounted) return;
          setState(() {
            _nativeAd = a as NativeAd;
            _nativeLoaded = true;
          });
        },
        onAdFailedToLoad: (a, _) => a.dispose(),
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: AppColors.surface,
        primaryTextStyle: NativeTemplateTextStyle(textColor: AppColors.text),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.textDim,
        ),
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF04212A),
          backgroundColor: AppColors.cyan,
        ),
      ),
    ).load();
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
          if (p.isKey) counts[p.id] = await Backend.availableCount(p.id);
        }
      }
      // Owned set is best-effort — an empty set only loses the "Owned" badge.
      final mine = await Backend.ownedProductIds().catchError(
        (_) => <String>{},
      );
      if (!mounted) return;
      setState(() {
        products = ps;
        stock = counts;
        owned = mine;
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

  /// Products on the current shelf.
  List<Product> get _shelf => products
      .where((p) => _tab == 'key' ? p.isKey : p.isDownloadable)
      .toList();

  Future<void> _openDetail(Product p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: p,
          coins: widget.coins,
          stock: p.isKey ? (stock[p.id] ?? -1) : -1,
          onRefresh: widget.onRefresh,
          owned: owned.contains(p.id),
        ),
      ),
    );
    // Reload stock/availability after coming back (claim may have happened).
    if (mounted) _load(silent: true);
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

    final shelf = _shelf;

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
                Eyebrow(text: _tab == 'key' ? 'License store' : 'App store'),
                const SizedBox(height: 16),
                Text(
                  _tab == 'key'
                      ? 'Spend coins,\nclaim keys'
                      : 'Spend coins,\ndownload apps',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _tab == 'key'
                      ? 'Every claim gives you a fresh, unused license key.'
                      : 'Buy APKs and files with your ad coins, then download them here.',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ---- shelf switch (Keys | Apps) -------------------------------
          ScrollReveal(
            delay: const Duration(milliseconds: 60),
            child: _segment(),
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
          SectionLabel(_tab == 'key' ? 'AVAILABLE KEYS' : 'APPS & FILES'),
          if (shelf.isEmpty)
            ScrollReveal(
              child: EmptyState(
                icon: _tab == 'key'
                    ? Icons.storefront_outlined
                    : Icons.apps_outlined,
                title: _tab == 'key' ? 'No products yet' : 'No apps yet',
                message: _tab == 'key'
                    ? 'Check back soon — new keys drop regularly.'
                    : 'Apps and files you buy with coins show up here.',
              ),
            ),
          for (var i = 0; i < shelf.length; i++) ...[
            // Cinematic stagger only on the first entry — after a shelf
            // switch, cards must appear instantly instead of remounting
            // their reveal delay + 800ms fade.
            if (_switchedShelf)
              _productCard(shelf[i])
            else
              ScrollReveal(
                delay: Duration(milliseconds: (60 * i).clamp(0, 400)),
                child: _productCard(shelf[i]),
              ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 22),

          // ---- sponsored native ad ------------------------------------
          if (shelf.isNotEmpty && _nativeLoaded && _nativeAd != null) ...[
            const SectionLabel('Sponsored'),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 350, maxHeight: 400),
              child: AdWidget(ad: _nativeAd!),
            ),
            const SizedBox(height: 22),
          ],

          Center(
            child: Text(
              _tab == 'key'
                  ? 'FRESH DROPS · DELIVERED INSTANTLY'
                  : 'MEDIAFIRE BACKED · DOWNLOADS ANY TIME',
              style: const TextStyle(
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

  // ---- Keys | Apps switch ---------------------------------------------
  Widget _segment() {
    const keys = 'key';
    const apps = 'app';

    Widget item(String id, String label, IconData icon) {
      final on = _tab == id;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_tab == id) return;
            setState(() {
              _tab = id;
              _switchedShelf = true;
            });
          },
          child: AnimatedContainer(
            // Snappier than kMotionBase (420ms) — the pill morph was part
            // of the perceived lag when swapping shelves.
            duration: const Duration(milliseconds: 240),
            curve: kPremiumCurve,
            height: 46,
            decoration: BoxDecoration(
              gradient: on ? kNeonGradient : null,
              color: on ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: on
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.10),
              ),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.28),
                        blurRadius: 22,
                        spreadRadius: -8,
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: on ? Colors.white : AppColors.textDim,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                    color: on ? Colors.white : AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          item(keys, 'Keys', Icons.key_rounded),
          item(apps, 'Apps', Icons.android_rounded),
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
          errorBuilder: (context, e, s) => _thumbFallback(size, p),
        ),
      );
    }
    return _thumbFallback(size, p);
  }

  Widget _thumbFallback(double size, Product p) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: p.isApk
          ? kNeonGradient
          : p.isFile
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
            )
          : kTealGradient,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(
      p.isKey
          ? Icons.key_rounded
          : p.isApk
          ? Icons.android_rounded
          : Icons.insert_drive_file_rounded,
      color: Colors.white,
      size: 26,
    ),
  );

  Widget _productCard(Product p) {
    final count = p.isKey ? (stock[p.id] ?? -1) : -1;
    final desc = p.description.trim();
    final isOwned = owned.contains(p.id);

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
                        color: AppColors.textDim,
                        fontSize: 12.5,
                      ),
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
                        label: p.hasDurations
                            ? 'from ${p.durations.map((d) => d.cost).reduce((a, b) => a < b ? a : b)} coins'
                            : '${p.cost} coins',
                        color: AppColors.gold,
                      ),
                      if (p.isDownloadable)
                        NeonPill(
                          icon: p.isApk
                              ? Icons.android_rounded
                              : Icons.insert_drive_file_outlined,
                          label: p.isApk
                              ? (p.version.isEmpty ? 'APK' : 'APK ${p.version}')
                              : (p.fileSize.isEmpty
                                    ? 'FILE'
                                    : 'FILE · ${p.fileSize}'),
                          color: AppColors.cyan,
                        ),
                      if (isOwned)
                        const NeonPill(
                          icon: Icons.check_circle_rounded,
                          label: 'Owned',
                          color: AppColors.green,
                        ),
                      if (p.isKey && count >= 0)
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
              child: Icon(
                isOwned && p.isDownloadable
                    ? Icons.download_rounded
                    : CupertinoIcons.chevron_right,
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
