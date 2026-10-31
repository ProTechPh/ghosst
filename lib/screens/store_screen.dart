import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../premium.dart';
import '../arcade.dart';
import '../services/ad_service.dart';
import '../services/worker_backend.dart';
import '../services/distribution.dart';
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

class _StoreScreenState extends State<StoreScreen> {
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

  /// Sponsored native card at the end of the shelf (passive revenue).
  NativeAd? _nativeAd;
  bool _nativeLoaded = false;
  int _nativeRetryAttempts = 0;
  Timer? _nativeRetryTimer;

  void _onAdsEnabledForNative() {
    if (AdService.adsEnabled &&
        mounted &&
        _nativeAd == null &&
        !_nativeLoaded) {
      _loadNative();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    AdService.instance.adsEnabledNotifier.addListener(_onAdsEnabledForNative);
    if (AdService.adsEnabled) {
      _loadNative();
    }
  }

  @override
  void dispose() {
    _nativeRetryTimer?.cancel();
    AdService.instance.adsEnabledNotifier.removeListener(
      _onAdsEnabledForNative,
    );
    _nativeAd?.dispose();
    _nativeAd = null;
    _nativeLoaded = false;
    super.dispose();
  }

  /// Medium native template, styled dark to match the store chrome.
  /// Rendered only after [onAdLoaded] — a failed ad simply never shows.
  void _loadNative() {
    if (!AdService.adsEnabled || !mounted) return;
    _nativeRetryTimer?.cancel();
    NativeAd(
      adUnitId: AdUnits.native,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (a) {
          if (!mounted) {
            a.dispose();
            return;
          }
          _nativeRetryAttempts = 0;
          setState(() {
            _nativeAd = a as NativeAd;
            _nativeLoaded = true;
          });
        },
        onAdFailedToLoad: (a, error) {
          a.dispose();
          debugPrint(
            '[StoreScreen] NativeAd failed to load: code ${error.code}, message: ${error.message}, domain: ${error.domain}',
          );
          if (!mounted) return;
          setState(() {
            _nativeAd = null;
            _nativeLoaded = false;
          });
          // Code 3 means the auction has no inventory. Repeating the same
          // request every few seconds cannot create inventory and only adds
          // unnecessary ad traffic. A later Store visit may try again.
          if (error.code == 3) {
            debugPrint('[StoreScreen] NativeAd no fill.');
          } else if (_nativeRetryAttempts < 3) {
            final delaySeconds = 4 * (1 << _nativeRetryAttempts);
            _nativeRetryAttempts++;
            debugPrint(
              '[StoreScreen] Retrying native ad in ${delaySeconds}s (attempt $_nativeRetryAttempts/3)',
            );
            _nativeRetryTimer = Timer(Duration(seconds: delaySeconds), () {
              if (mounted) _loadNative();
            });
          } else {
            debugPrint('[StoreScreen] NativeAd retries exhausted.');
          }
        },
        onAdImpression: (_) => debugPrint('[StoreScreen] NativeAd impression'),
        onAdClicked: (_) => debugPrint('[StoreScreen] NativeAd clicked'),
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: AppColors.surface,
        primaryTextStyle: NativeTemplateTextStyle(textColor: AppColors.text),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: AppColors.textDim,
        ),
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF141210),
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
        products = !Distribution.showsDownloadStore
            ? ps.where((product) => product.isKey).toList()
            : ps;
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

  int _stockOf(Product p) => p.isKey ? (stock[p.id] ?? -1) : -1;

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
          padding: const EdgeInsets.all(AppSpace.xl),
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
    final rest = shelf.length > 1 ? shelf.sublist(1) : const <Product>[];

    return Stack(
      children: [
        const Positioned.fill(child: IgnorePointer(child: TableSurface())),
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.md,
          AppSpace.xl,
          // Clears the floating nav pill so the last row is never covered.
          AppSpace.huge + AppSpace.xxl,
        ),
        children: [
          // ---- editorial header ----------------------------------------
          ScrollReveal(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(text: _tab == 'key' ? 'License store' : 'App store'),
                const SizedBox(height: AppSpace.lg),
                Text(
                  _tab == 'key'
                      ? 'Spend coins,\nclaim keys'
                      : 'Spend coins,\ndownload apps',
                  style: AppText.display,
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  _tab == 'key'
                      ? 'Every claim gives you a fresh, unused license key.'
                      : 'Buy APKs and files with your ad coins, then download them here.',
                  style: AppText.caption.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),

          // ---- shelf switch (Keys | Apps) -------------------------------
          if (Distribution.showsDownloadStore) ...[
            ScrollReveal(
              delay: const Duration(milliseconds: 60),
              child: _segment(),
            ),
            const SizedBox(height: AppSpace.xl),
          ],

          // ---- balance hero --------------------------------------------
          ScrollReveal(
            delay: const Duration(milliseconds: 110),
            child: Pressable(
              onTap: widget.onOpenWallet,
              child: DoubleBezel(
                padding: const EdgeInsets.all(AppSpace.lg),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1F2026), Color(0xFF131417)],
                ),
                glowColor: AppColors.gold,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOUR BALANCE',
                            style: AppText.caption.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.2,
                            ),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              AnimatedCounter(
                                value: widget.coins,
                                style: monoStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.gold,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(width: AppSpace.sm),
                              Text('coins', style: AppText.caption),
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
            const SizedBox(height: AppSpace.md),
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
          const SizedBox(height: AppSpace.xxl),

          // ---- products -------------------------------------------------
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
                action: widget.onGoToEarn == null
                    ? null
                    : IslandButton(
                        expand: false,
                        dense: true,
                        label: 'Earn coins',
                        icon: CupertinoIcons.play_rectangle,
                        onPressed: widget.onGoToEarn,
                      ),
              ),
            )
          else ...[
            ScrollReveal(
              child: SectionHeader(
                title: 'Featured',
                trailing: Text(
                  _tab == 'key' ? 'LICENSE' : 'DOWNLOAD',
                  style: AppText.label.copyWith(
                    fontSize: 10,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            ScrollReveal(
              delay: const Duration(milliseconds: 60),
              child: _featuredCard(shelf.first),
            ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xl),
              SectionHeader(
                title: _tab == 'key' ? 'All keys' : 'Apps & files',
                trailing: Text(
                  '${rest.length}',
                  style: AppText.figure.copyWith(
                    fontSize: 12,
                    color: AppColors.textDim,
                  ),
                ),
              ),
              _switchedShelf
                  ? _cardShelf(rest)
                  : ScrollReveal(
                      delay: const Duration(milliseconds: 120),
                      child: _cardShelf(rest),
                    ),
            ],
          ],
          const SizedBox(height: AppSpace.xl),

          // ---- sponsored native ad ------------------------------------
          if (shelf.isNotEmpty && _nativeLoaded && _nativeAd != null) ...[
            const SectionHeader(title: 'Sponsored'),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 350, maxHeight: 400),
              child: AdWidget(ad: _nativeAd!),
            ),
            const SizedBox(height: AppSpace.xl),
          ],

          Center(
            child: Text(
              _tab == 'key'
                  ? 'FRESH DROPS · DELIVERED INSTANTLY'
                  : 'MEDIAFIRE BACKED · DOWNLOADS ANY TIME',
              style: AppText.label.copyWith(
                fontSize: 10,
                letterSpacing: 2.4,
                color: AppColors.textDim,
              ),
            ),
          ),
        ],
          ),
        ),
      ],
    );
  }

  // ---- Keys | Apps switch ---------------------------------------------
  Widget _segment() {
    const keys = 'key';
    const apps = 'app';

    Widget item(String id, String label, IconData icon) {
      final on = _tab == id;
      return Expanded(
        child: Pressable(
          scale: 0.97,
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
            height: 44,
            decoration: BoxDecoration(
              gradient: on ? kNeonGradient : null,
              color: on ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.28),
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
                  size: 15,
                  color: on ? const Color(0xFF141210) : AppColors.textDim,
                ),
                const SizedBox(width: AppSpace.sm - 1),
                Text(
                  label,
                  style: AppText.subtitle.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: on ? const Color(0xFF141210) : AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.pill),
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
  Widget _skeleton() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        AppSpace.huge,
      ),
      children: [
        const Skeleton(width: 116, height: 26, radius: AppRadius.pill),
        const SizedBox(height: AppSpace.lg),
        const Skeleton(width: 232, height: 30, radius: AppRadius.chip),
        const SizedBox(height: AppSpace.sm),
        const Skeleton(width: 180, height: 30, radius: AppRadius.chip),
        const SizedBox(height: AppSpace.md),
        const Skeleton(width: 250, height: 12, radius: AppRadius.pill),
        const SizedBox(height: AppSpace.xl),
        const Skeleton(height: 44, radius: AppRadius.pill),
        const SizedBox(height: AppSpace.xl),
        const Skeleton(height: 96, radius: AppRadius.hero),
        const SizedBox(height: AppSpace.xxl),
        const Skeleton(width: 90, height: 12, radius: AppRadius.pill),
        const SizedBox(height: AppSpace.md),
        const Skeleton(height: 288, radius: AppRadius.hero),
        const SizedBox(height: AppSpace.xl),
        const Skeleton(width: 74, height: 12, radius: AppRadius.pill),
        const SizedBox(height: AppSpace.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                children: [
                  Skeleton(height: 268, radius: AppRadius.card),
                  SizedBox(height: AppSpace.md),
                  Skeleton(height: 214, radius: AppRadius.card),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpace.lg),
                child: const Column(
                  children: [
                    Skeleton(height: 214, radius: AppRadius.card),
                    SizedBox(height: AppSpace.md),
                    Skeleton(height: 268, radius: AppRadius.card),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---- product imagery -------------------------------------------------
  Widget _cover(Product p, {int width = 800}) {
    if (p.imageIds.isNotEmpty) {
      return Image.network(
        Backend.imageUrl(p.imageIds.first, width: width),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, e, s) => _coverFallback(p),
      );
    }
    return _coverFallback(p);
  }

  Widget _coverFallback(Product p) {
    return Container(
      color: AppColors.surfaceHigh,
      child: Center(
        child: Icon(
          p.isKey
              ? Icons.key_rounded
              : p.isApk
              ? Icons.android_rounded
              : Icons.insert_drive_file_rounded,
          color: AppColors.cyan.withValues(alpha: 0.55),
          size: 34,
        ),
      ),
    );
  }

  /// Mono price with the coin mark — never plain body text.
  Widget _priceTag(int cost, {double size = 14}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.monetization_on_rounded,
          size: size + 1,
          color: AppColors.gold,
        ),
        const SizedBox(width: AppSpace.xs),
        Text(
          groupDigits(cost),
          style: AppText.figure.copyWith(
            fontSize: size,
            color: AppColors.gold,
          ),
        ),
      ],
    );
  }

  // ---- featured hero panel --------------------------------------------
  Widget _featuredCard(Product p) {
    final count = _stockOf(p);
    final isOwned = owned.contains(p.id);
    final soldOut = p.isKey && count == 0;
    final desc = p.description.trim();

    return Pressable(
      scale: 1.01,
      onTap: soldOut ? null : () => _openDetail(p),
      child: CardFrame(
        radius: AppRadius.hero,
        tier: tierForCost(entryCost(p)),
        child: SizedBox(
          height: 286,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _cover(p),
              // Cyan-tinted scrim: the poster fades into the page, never a
              // black rectangle behind the title.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.45, 1],
                    colors: [
                      AppColors.bg.withValues(alpha: 0.05),
                      AppColors.bg.withValues(alpha: 0.35),
                      AppColors.bg.withValues(alpha: 0.96),
                    ],
                  ),
                ),
              ),
              if (soldOut)
                ColoredBox(color: AppColors.bg.withValues(alpha: 0.45)),
              Positioned(
                top: AppSpace.md,
                left: AppSpace.md,
                right: AppSpace.md,
                child: CardIndex(cost: entryCost(p), type: cardType(p)),
              ),
              Positioned(
                left: AppSpace.lg,
                right: AppSpace.lg,
                bottom: AppSpace.lg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: AppText.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xs + 2),
                      Text(
                        desc,
                        style: AppText.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpace.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (isOwned)
                          const NeonPill(
                            icon: Icons.check_circle_rounded,
                            label: 'Owned',
                            color: AppColors.cyan,
                          )
                        else if (soldOut)
                          NeonPill(
                            icon: Icons.remove_shopping_cart_outlined,
                            label: 'Sold out',
                            color: AppColors.textDim,
                          )
                        else ...[
                          if (p.hasDurations) ...[
                            Text('from', style: AppText.caption),
                            const SizedBox(width: AppSpace.xs + 2),
                          ],
                          _priceTag(entryCost(p), size: 17),
                          const SizedBox(width: AppSpace.xs + 2),
                          Text('coins', style: AppText.caption),
                        ],
                        const Spacer(),
                        if (!isOwned && !soldOut) ...[
                          Text(
                            count >= 0 ? '$count left' : 'Fresh drop',
                            style: AppText.label.copyWith(
                              fontSize: 10,
                              letterSpacing: 1.6,
                              color: AppColors.textDim,
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                        ],
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Icon(
                            soldOut
                                ? Icons.lock_outline_rounded
                                : CupertinoIcons.chevron_right,
                            size: 16,
                            color: soldOut ? AppColors.textDim : AppColors.text,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- 5:7 card shelf --------------------------------------------------
  Widget _cardShelf(List<Product> items) {
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: _shelfCard(items[i]),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left)),
        const SizedBox(width: AppSpace.md),
        // Dropping the right column gives the shelf its editorial stagger.
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: items.length > 1 ? AppSpace.lg : 0),
            child: Column(children: right),
          ),
        ),
      ],
    );
  }

  Widget _shelfCard(Product p) {
    final count = _stockOf(p);
    final isOwned = owned.contains(p.id);
    final soldOut = isSoldOutCard(isKey: p.isKey, stock: count);
    final tier = tierForCost(entryCost(p));

    return Pressable(
      onTap: soldOut ? null : () => _openDetail(p),
      child: CardFrame(
        tier: tier,
        holo: tier == RarityTier.vault,
        child: AspectRatio(
          aspectRatio: 5 / 7,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card - 11),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _cover(p, width: 400),
                      if (soldOut)
                        ColoredBox(color: AppColors.bg.withValues(alpha: .55)),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: .55,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.bg.withValues(alpha: 0),
                                  AppColors.bg.withValues(alpha: .94),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.subtitle.copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              cardMeta(p),
                              style: AppText.caption.copyWith(fontSize: 11),
                            ),
                            if (!isOwned && !soldOut && count >= 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                '$count left',
                                style: AppText.caption.copyWith(
                                  fontSize: 11,
                                  color: AppColors.green,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: CardIndex(cost: entryCost(p), type: cardType(p)),
              ),
              if (isOwned)
                const Positioned(top: 44, right: 12, child: _OwnedSeal()),
              if (soldOut) const Center(child: _SoldOutStamp()),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnedSeal extends StatelessWidget {
  const _OwnedSeal();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.cyan.withValues(alpha: .18),
      ),
      child: const Icon(Icons.check_rounded, size: 13, color: AppColors.cyan),
    );
  }
}

class _SoldOutStamp extends StatelessWidget {
  const _SoldOutStamp();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.06,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.textDim.withValues(alpha: .6)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'SOLD OUT',
          style: AppText.label.copyWith(
            fontSize: 10,
            letterSpacing: 3,
            color: AppColors.textDim,
          ),
        ),
      ),
    );
  }
}
