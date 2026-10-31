import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../arcade.dart';
import '../premium.dart';
import '../services/worker_backend.dart';
import '../theme.dart';
import 'claim_reveal.dart';
import 'download_screen.dart';

/// Full product page: image carousel, description, YouTube poster, claim CTA.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.coins,
    required this.stock,
    required this.onRefresh,
    this.owned = false,
  });

  final Product product;
  final int coins;

  /// Remaining stock (-1 = unknown, non-admin).
  final int stock;

  /// Refreshes the app's coin balance / store state after a claim.
  final Future<void> Function() onRefresh;

  /// True when the user already bought this product (app-store items are
  /// single-purchase — the CTA becomes "Download" instead of "Buy").
  final bool owned;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late int coins = widget.coins;
  final _page = PageController();
  int _pageIdx = 0;
  bool claiming = false;

  /// Ownership mirrored locally. [ProductDetailScreen.owned] is a snapshot
  /// taken when this route was pushed and never updates, so a completed
  /// purchase used to leave a live "Buy" button under the buyer's thumb —
  /// one more tap meant a second charge.
  late bool _owned = widget.owned;

  /// Duration option currently picked on the chip row (key products with
  /// admin-defined options only — empty means the flat-cost claim).
  String _durationLabel = '';

  /// Parsed video id — drives the poster frame and the tap-to-play link.
  late final String? _ytId = _youtubeId(widget.product.youtubeUrl);

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p.hasDurations) _durationLabel = p.durations.first.label;
  }

  /// Opens the video in the YouTube app (or browser).
  ///
  /// There used to be an in-app WebView player here. YouTube answers it with
  /// "Configuration error" on many devices and nothing the app can send
  /// satisfies it, so the poster frame plus the real app is the reliable path.
  Future<void> _openExternal() async {
    final id = _ytId;
    if (id == null) return;
    try {
      await launchUrl(
        Uri.parse('https://www.youtube.com/watch?v=$id'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // No handler available — the in-app player remains usable.
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProductDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only ever moves towards owned — a stale parent snapshot must not undo
    // a purchase this screen already recorded.
    if (widget.owned && !_owned) _owned = true;
  }

  /// Extracts the video id from a watch / shorts / embed / youtu.be URL.
  String? _youtubeId(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    // Already a bare 11-character id.
    if (RegExp(r'^[\w-]{11}$').hasMatch(value)) return value;
    final u = Uri.tryParse(value);
    if (u == null) return null;
    final host = u.host.toLowerCase();
    if (host.endsWith('youtu.be')) {
      final seg = u.pathSegments;
      if (seg.isNotEmpty && seg.first.isNotEmpty) return seg.first;
      return null;
    }
    if (host.contains('youtube.com')) {
      if (u.path == '/watch') {
        final v = u.queryParameters['v'];
        if (v != null && v.isNotEmpty) return v;
      }
      final seg = u.pathSegments;
      if (seg.length >= 2 &&
          const ['shorts', 'embed', 'live', 'v'].contains(seg[0]) &&
          seg[1].isNotEmpty) {
        return seg[1];
      }
    }
    return null;
  }

  /// URL from an earlier purchase (owned products never re-spend coins).
  Future<Claim?> _ownedClaim() async {
    try {
      final claims = await Backend.myClaims();
      for (final c in claims) {
        if (c.productId == widget.product.id && c.downloadUrl.isNotEmpty) {
          return c;
        }
      }
    } catch (_) {
      // Fall through — the admin can re-check the link if nothing is found.
    }
    return null;
  }

  Future<void> _openDownload() async {
    final p = widget.product;
    var url = _lastUrl;
    var sha = _lastSha;
    if (url.isEmpty) {
      final c = await _ownedClaim();
      url = c?.downloadUrl ?? '';
      sha = c?.sha256;
    }
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download link not available yet')),
        );
      }
      return;
    }
    _lastUrl = url;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DownloadScreen(
          url: url,
          title: p.name,
          kind: p.isApk ? 'apk' : 'file',
          version: p.version,
          fileSize: p.fileSize,
          preferredName: p.isApk ? '${p.name}.apk' : '',
          imageUrl: Backend.productThumbUrl(p.imageIds),
          youtubeUrl: p.youtubeUrl,
          sha256: sha,
        ),
      ),
    );
  }

  /// The duration option matching [_durationLabel] (first option when the
  /// label went stale), or null for flat-priced products.
  ProductDuration? _selectedDuration(Product p) {
    if (!p.hasDurations) return null;
    for (final d in p.durations) {
      if (d.label == _durationLabel) return d;
    }
    return p.durations.first;
  }

  /// URL of the most recent successful unlock (fresh link on every claim —
  /// `Backend.claimApp` returns the current MediaFire URL).
  String _lastUrl = '';

  /// Checksum that came with [_lastUrl], when the server published one.
  String? _lastSha;

  Future<void> _claim() async {
    if (claiming) return;
    final p = widget.product;
    final isApp = p.isDownloadable;
    final sel = _selectedDuration(p);
    final duration = sel?.label ?? '';

    setState(() => claiming = true);
    final ok = await showClaimFlow(
      context: context,
      product: p,
      balanceBefore: coins,
      cost: sel?.cost ?? p.cost,
      kind: isApp ? 'app' : 'key',
      claim: () async {
        if (!isApp) {
          return Backend.claim(p.id, duration: duration);
        }
        final res = await Backend.claimApp(p.id);
        _lastUrl = res.url;
        _lastSha = res.sha256;
        return res.url;
      },
    );
    if (!mounted) return;
    // New balance straight from the backend, then notify the shell.
    final c = await Backend.coins().catchError((_) => coins);
    if (!mounted) return;
    setState(() {
      coins = c;
      claiming = false;
      // Flip before the first await: the CTA can never be "Buy" again for
      // something the server just charged for.
      if (ok && isApp) _owned = true;
    });
    await widget.onRefresh();
    if (!mounted) return;
    if (ok) {
      if (isApp) {
        if (_lastUrl.isEmpty) {
          // Defensive only — the claim already succeeded, so read the link
          // back from the existing purchase instead of charging again.
          final c = await _ownedClaim();
          _lastUrl = c?.downloadUrl ?? '';
          _lastSha = c?.sha256;
        }
        if (!mounted) return;
        if (_lastUrl.isNotEmpty) await _openDownload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unlocked — download anytime from My Purchases'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Key claimed — saved to My Purchases')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final isApp = p.isDownloadable;
    final isOwned = isApp && _owned;
    final sel = _selectedDuration(p);
    final cost = sel?.cost ?? p.cost;
    final affordable = coins >= cost;
    final outOfStock = p.isKey && widget.stock == 0;
    final canClaim = isOwned
        ? !claiming
        : affordable && !outOfStock && !claiming;

    final label = isOwned
        ? 'Download'
        : outOfStock
        ? 'Out of stock'
        : affordable
        ? isApp
              ? 'Buy & download'
              : 'Claim key'
        : 'Not enough coins';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: AppSpace.lg),
            children: [
              CardFrame(
                radius: 0,
                tier: tierForCost(entryCost(widget.product)),
                child: _hero(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  AppSpace.xl,
                  AppSpace.xl,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: AppText.headline),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      isApp
                          ? (p.isApk
                                ? 'Android app · downloaded with your coins'
                                : 'Digital file · downloaded with your coins')
                          : 'License key · delivered instantly',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: AppSpace.lg),

                    // ---- price / stock / type --------------------------
                    _stats(cost: cost, outOfStock: outOfStock, isApp: isApp),
                    if (p.version.isNotEmpty || p.fileSize.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.md),
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.xs,
                        children: [
                          if (p.version.isNotEmpty)
                            NeonPill(
                              icon: Icons.tag_rounded,
                              label: p.version,
                              color: AppColors.textDim,
                            ),
                          if (p.fileSize.isNotEmpty)
                            NeonPill(
                              icon: Icons.data_usage_rounded,
                              label: p.fileSize,
                              color: AppColors.cyan,
                            ),
                        ],
                      ),
                    ],

                    // ---- description -----------------------------------
                    const SizedBox(height: AppSpace.xl),
                    const SectionHeader(title: 'About this product'),
                    Text(
                      p.description.trim().isEmpty
                          ? 'No description yet.'
                          : p.description.trim(),
                      style: AppText.body.copyWith(
                        height: 1.6,
                        color: p.description.trim().isEmpty
                            ? AppColors.textDim
                            : AppColors.text,
                      ),
                    ),

                    // ---- youtube --------------------------------------
                    if (_ytId != null) ...[
                      const SizedBox(height: AppSpace.xl),
                      SectionHeader(
                        title: p.isDownloadable ? 'Tutorial' : 'Video',
                      ),
                      GlowCard(
                        padding: const EdgeInsets.all(6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppRadius.input + 2,
                          ),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  'https://i.ytimg.com/vi/$_ytId/hqdefault.jpg',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stack) =>
                                      const ColoredBox(color: Colors.black),
                                ),
                                const ColoredBox(color: Color(0x2E000000)),
                                Center(
                                  child: Pressable(
                                    scale: 0.94,
                                    onTap: _openExternal,
                                    child: Container(
                                      width: 58,
                                      height: 58,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black.withValues(
                                          alpha: 0.62,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.24,
                                          ),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ] else if (p.youtubeUrl.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xl),
                      SectionHeader(
                        title: p.isDownloadable ? 'Tutorial' : 'Video',
                      ),
                      GlowCard(
                        padding: const EdgeInsets.all(AppSpace.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.link_off_rounded,
                              color: AppColors.gold,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpace.sm + 2),
                            Expanded(
                              child: Text(
                                'YouTube link not recognized. Use a video link like '
                                'https://youtu.be/… , https://www.youtube.com/watch?v=… '
                                'or https://www.youtube.com/shorts/…',
                                style: AppText.caption.copyWith(height: 1.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ---- duration options -----------------------------
                    if (p.hasDurations) ...[
                      const SizedBox(height: AppSpace.xl),
                      const SectionHeader(title: 'Duration'),
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.sm,
                        children: [
                          for (final d in p.durations)
                            _durationChip(
                              label: d.label,
                              cost: d.cost,
                              selected: d.label == (sel?.label ?? ''),
                              onTap: () =>
                                  setState(() => _durationLabel = d.label),
                            ),
                        ],
                      ),
                    ],

                    // ---- purchase note --------------------------------
                    if (isApp && !isOwned) ...[
                      const SizedBox(height: AppSpace.xl),
                      Text(
                        'One purchase — you can re-download it any time from '
                        'My Purchases.',
                        style: AppText.caption,
                      ),
                    ],
                    const SizedBox(height: AppSpace.xl),
                  ],
                ),
              ),
            ],
          ),

          // ---- floating glass back button ---------------------------
          Positioned(
            top: MediaQuery.paddingOf(context).top + AppSpace.xs,
            left: AppSpace.lg,
            child: _glassBack(context),
          ),
        ],
      ),
      bottomNavigationBar: _buyBar(
        cost: cost,
        isOwned: isOwned,
        affordable: affordable,
        outOfStock: outOfStock,
        canClaim: canClaim,
        label: label,
      ),
    );
  }

  Widget _glassBack(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.bg.withValues(alpha: 0.55),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(
          Icons.arrow_back_rounded,
          size: 20,
          color: AppColors.text,
        ),
      ),
    );
  }

  /// Price / stock / type — mono figures, never body text.
  Widget _stats({
    required int cost,
    required bool outOfStock,
    required bool isApp,
  }) {
    final type = widget.product.isApk
        ? 'APK'
        : widget.product.isFile
        ? 'FILE'
        : 'KEY';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StatCell(
            label: 'Price',
            value: groupDigits(cost),
            icon: Icons.monetization_on_rounded,
            color: AppColors.gold,
          ),
        ),
        if (widget.product.isKey && widget.stock >= 0) ...[
          _statDivider(),
          Expanded(
            child: StatCell(
              label: 'In stock',
              value: groupDigits(widget.stock),
              color: outOfStock ? AppColors.red : AppColors.green,
            ),
          ),
        ],
        _statDivider(),
        Expanded(
          child: StatCell(
            label: 'Type',
            value: type,
            color: isApp ? AppColors.cyan : AppColors.text,
          ),
        ),
      ],
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      color: AppColors.border,
    );
  }

  /// Sticky purchase bar: price on the left, CTA on the right.
  Widget _buyBar({
    required int cost,
    required bool isOwned,
    required bool affordable,
    required bool outOfStock,
    required bool canClaim,
    required String label,
  }) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: rarityEdge(tierForCost(entryCost(widget.product))),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg.withValues(alpha: 0.96),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.md,
                AppSpace.xl,
                AppSpace.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isOwned && !affordable && !outOfStock) ...[
                    Text(
                      'Watch ads on the Earn tab to get ${cost - coins} more coins.',
                      style: AppText.caption,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpace.sm),
                  ],
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isOwned ? 'OWNED' : 'PRICE',
                            style: AppText.caption.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          if (isOwned)
                            Text(
                              'Ready',
                              style: AppText.subtitle.copyWith(
                                color: AppColors.cyan,
                              ),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.monetization_on_rounded,
                                  size: 17,
                                  color: AppColors.gold,
                                ),
                                const SizedBox(width: AppSpace.xs),
                                Text(
                                  groupDigits(cost),
                                  style: AppText.figure.copyWith(
                                    fontSize: 19,
                                    color: AppColors.gold,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(width: AppSpace.lg),
                      Expanded(
                        child: NeonButton(
                          expand: true,
                          onPressed: canClaim || isOwned
                              ? () {
                                  if (isOwned) {
                                    _openDownload();
                                  } else {
                                    _claim();
                                  }
                                }
                              : null,
                          child: claiming
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (isOwned) ...[
                                      const Icon(
                                        Icons.download_rounded,
                                        size: 17,
                                      ),
                                      const SizedBox(width: AppSpace.sm - 1),
                                    ],
                                    Flexible(
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Selectable duration chip — mono cost, gold price tone.
  Widget _durationChip({
    required String label,
    required int cost,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Pressable(
      scale: 0.97,
      onTap: onTap,
      child: AnimatedContainer(
        duration: kMotionStandard,
        curve: kPremiumCurve,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md + 2,
          vertical: AppSpace.sm + 1,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.14)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppText.caption.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: selected ? AppColors.text : AppColors.textDim,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Icon(
              Icons.monetization_on_rounded,
              size: 12,
              color: AppColors.gold.withValues(alpha: selected ? 1 : 0.7),
            ),
            const SizedBox(width: AppSpace.xs - 1),
            Text(
              groupDigits(cost),
              style: AppText.figure.copyWith(
                fontSize: 13,
                color: AppColors.gold.withValues(alpha: selected ? 1 : 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Edge-to-edge poster with a scrim that melts into the page background.
  Widget _hero() {
    final product = widget.product;
    final ids = product.imageIds;

    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ids.isEmpty)
            Container(
              color: AppColors.surfaceHigh,
              child: Center(
                child: Icon(
                  product.isKey
                      ? Icons.key_rounded
                      : product.isApk
                      ? Icons.android_rounded
                      : Icons.insert_drive_file_rounded,
                  color: AppColors.cyan.withValues(alpha: 0.45),
                  size: 72,
                ),
              ),
            )
          else
            PageView.builder(
              controller: _page,
              itemCount: ids.length,
              onPageChanged: (i) => setState(() => _pageIdx = i),
              itemBuilder: (context, i) => Image.network(
                Backend.imageUrl(ids[i], width: 900),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.6),
                      ),
                errorBuilder: (context, e, s) => Container(
                  color: AppColors.surfaceHigh,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textDim,
                    size: 42,
                  ),
                ),
              ),
            ),

          // Darken under the floating back button.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.42],
                colors: [
                  AppColors.bg.withValues(alpha: 0.62),
                  AppColors.bg.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          // Melt the bottom edge into the page.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.55, 1],
                colors: [AppColors.bg.withValues(alpha: 0), AppColors.bg],
              ),
            ),
          ),

          if (ids.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpace.md,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < ids.length; i++)
                    AnimatedContainer(
                      duration: kMotionStandard,
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpace.xs - 1,
                      ),
                      width: i == _pageIdx ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _pageIdx
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                ],
              ),
            ),
          Positioned(
            // clears the 44 px glass back button above it
            top: MediaQuery.paddingOf(context).top + AppSpace.xs + 44 + AppSpace.sm,
            left: AppSpace.lg,
            right: AppSpace.lg,
            child: CardIndex(cost: entryCost(product), type: cardType(product)),
          ),
        ],
      ),
    );
  }
}
