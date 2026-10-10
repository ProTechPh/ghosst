import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../appwrite_client.dart';
import '../services/backend.dart';
import '../theme.dart';
import 'claim_reveal.dart';
import 'download_screen.dart';

/// Full product page: image carousel, description, YouTube embed, claim CTA.
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

  WebViewController? _yt;

  /// Duration option currently picked on the chip row (key products with
  /// admin-defined options only — empty means the flat-cost claim).
  String _durationLabel = '';

  /// Parsed video id (kept for the "Watch on YouTube" fallback).
  late final String? _ytId = _youtubeId(widget.product.youtubeUrl);

  /// Appwrite function domain — serves the embed wrapper at `?yt=<id>`.
  /// Loading the wrapper from this REAL third-party origin (instead of a
  /// `loadHtmlString` data document or a faked youtube.com baseUrl) is what
  /// YouTube's embedded player accepts; the other shapes are rejected with
  /// Error 153 / 152-4.
  static const _videoBase = 'https://claim.sgp.appwrite.run';

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p.hasDurations) _durationLabel = p.durations.first.label;
    final id = _ytId;
    if (id != null) {
      _yt = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        // Reduced Chrome UA without WebView markers ("; wv", "Version/4.0").
        ..setUserAgent(_chromeMobileUa)
        ..loadRequest(Uri.parse('$_videoBase/?yt=$id'));
    }
  }

  /// Standard reduced Chrome-on-Android UA (matches real Chrome devices).
  static const _chromeMobileUa =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Mobile Safari/537.36';

  /// Guaranteed fallback: open the video in the YouTube app (or browser).
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
  Future<String> _ownedUrl() async {
    try {
      final claims = await Backend.myClaims();
      for (final c in claims) {
        if (c.productId == widget.product.id && c.downloadUrl.isNotEmpty) {
          return c.downloadUrl;
        }
      }
    } catch (_) {
      // Fall through — the admin can re-check the link if nothing is found.
    }
    return '';
  }

  Future<void> _openDownload() async {
    final p = widget.product;
    var url = _lastUrl;
    if (url.isEmpty) url = await _ownedUrl();
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
        final url = await Backend.claimApp(p.id);
        _lastUrl = url;
        return url;
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
          _lastUrl = await _ownedUrl();
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
              ? 'Buy & download · $cost coins'
              : 'Claim key · $cost coins'
        : 'Not enough coins';

    return Scaffold(
      appBar: AppBar(title: Text(isApp ? 'App details' : 'Product details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _carousel(),
          const SizedBox(height: 18),
          Text(
            p.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              NeonPill(
                icon: Icons.monetization_on_rounded,
                label: '$cost coins',
                color: AppColors.gold,
              ),
              if (isApp)
                NeonPill(
                  icon: p.isApk
                      ? Icons.android_rounded
                      : Icons.insert_drive_file_outlined,
                  label: p.isApk ? 'APK' : 'FILE',
                  color: AppColors.cyan,
                ),
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
              if (isOwned)
                const NeonPill(
                  icon: Icons.check_circle_rounded,
                  label: 'Owned',
                  color: AppColors.green,
                ),
              if (p.isKey && widget.stock >= 0)
                widget.stock == 0
                    ? const NeonPill(
                        icon: Icons.remove_shopping_cart_outlined,
                        label: 'Out of stock',
                        color: AppColors.red,
                      )
                    : NeonPill(
                        icon: Icons.inventory_2_outlined,
                        label: '${widget.stock} in stock',
                        color: AppColors.green,
                      ),
              NeonPill(
                icon: Icons.account_balance_wallet_outlined,
                label: '$coins coins',
                color: AppColors.cyan,
              ),
            ],
          ),

          // ---- description ----
          const SizedBox(height: 20),
          const SectionLabel('About this product'),
          Text(
            p.description.trim().isEmpty
                ? 'No description yet.'
                : p.description.trim(),
            style: TextStyle(
              color: p.description.trim().isEmpty
                  ? AppColors.textDim
                  : AppColors.text,
              fontSize: 14.5,
              height: 1.55,
            ),
          ),

          // ---- youtube ----
          if (_yt != null) ...[
            const SizedBox(height: 20),
            SectionLabel(p.isDownloadable ? 'Tutorial' : 'Video'),
            GlowCard(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: WebViewWidget(controller: _yt!),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Fallback: some devices' WebView still reject embedded
                  // playback — opening the YouTube app always works.
                  NeonButton(
                    expand: true,
                    dense: true,
                    outline: true,
                    glow: false,
                    onPressed: _openExternal,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.ondemand_video_outlined, size: 17),
                        SizedBox(width: 7),
                        Text('Watch on YouTube'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (p.youtubeUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionLabel(p.isDownloadable ? 'Tutorial' : 'Video'),
            GlowCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.link_off_rounded,
                    color: AppColors.gold,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'YouTube link not recognized. Use a video link like '
                      'https://youtu.be/… , https://www.youtube.com/watch?v=… '
                      'or https://www.youtube.com/shorts/…',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ---- duration options ----
          if (p.hasDurations) ...[
            const SizedBox(height: 22),
            const SectionLabel('Duration'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in p.durations)
                  _durationChip(
                    label: d.label,
                    cost: d.cost,
                    selected: d.label == (sel?.label ?? ''),
                    onTap: () => setState(() => _durationLabel = d.label),
                  ),
              ],
            ),
          ],

          // ---- claim ----
          const SizedBox(height: 24),
          NeonButton(
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
                        const Icon(Icons.download_rounded, size: 17),
                        const SizedBox(width: 7),
                      ],
                      Text(label),
                    ],
                  ),
          ),
          if (!isOwned && !affordable && !outOfStock) ...[
            const SizedBox(height: 10),
            Text(
              'Watch ads on the Earn tab to get ${cost - coins} more coins.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          if (isApp && !isOwned) ...[
            const SizedBox(height: 10),
            Text(
              'One purchase — you can re-download it any time from '
              'My Purchases.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// Selectable duration chip (durations block) — hardcoded styling because
  /// this screen deliberately doesn't import premium.dart.
  Widget _durationChip({
    required String label,
    required int cost,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.cyan.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.cyan : AppColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.text : AppColors.textDim,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '$cost',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carousel() {
    final ids = widget.product.imageIds;
    if (ids.isEmpty) {
      // No images yet — styled placeholder.
      return Container(
        height: 210,
        decoration: BoxDecoration(
          gradient: widget.product.isApk ? kNeonGradient : kTealGradient,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Icon(
            widget.product.isKey
                ? Icons.key_rounded
                : widget.product.isApk
                ? Icons.android_rounded
                : Icons.insert_drive_file_rounded,
            color: Colors.white,
            size: 64,
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          height: 250,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
            color: AppColors.surface,
          ),
          child: PageView.builder(
            controller: _page,
            itemCount: ids.length,
            onPageChanged: (i) => setState(() => _pageIdx = i),
            itemBuilder: (context, i) => Image.network(
              Backend.imageUrl(ids[i], width: 900),
              headers: const {'X-Appwrite-Project': appwriteProjectId},
              fit: BoxFit.cover,
              width: double.infinity,
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
        ),
        if (ids.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < ids.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _pageIdx ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _pageIdx ? AppColors.cyan : AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
