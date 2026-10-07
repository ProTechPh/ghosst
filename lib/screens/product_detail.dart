import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../appwrite_client.dart';
import '../services/backend.dart';
import '../theme.dart';
import 'claim_reveal.dart';

/// Full product page: image carousel, description, YouTube embed, claim CTA.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.coins,
    required this.stock,
    required this.onRefresh,
  });

  final Product product;
  final int coins;

  /// Remaining stock (-1 = unknown, non-admin).
  final int stock;

  /// Refreshes the app's coin balance / store state after a claim.
  final Future<void> Function() onRefresh;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late int coins = widget.coins;
  final _page = PageController();
  int _pageIdx = 0;
  bool claiming = false;
  WebViewController? _yt;

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

  Future<void> _claim() async {
    if (claiming) return;
    setState(() => claiming = true);
    final ok = await showClaimFlow(
      context: context,
      product: widget.product,
      balanceBefore: coins,
      claim: () => Backend.claim(widget.product.id),
    );
    if (!mounted) return;
    // New balance straight from the backend, then notify the shell.
    final c = await Backend.coins().catchError((_) => coins);
    if (!mounted) return;
    setState(() {
      coins = c;
      claiming = false;
    });
    await widget.onRefresh();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Key claimed — saved to My Keys')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final affordable = coins >= p.cost;
    final outOfStock = widget.stock == 0;
    final canClaim = affordable && !outOfStock && !claiming;

    return Scaffold(
      appBar: AppBar(title: const Text('Product details')),
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
                label: '${p.cost} coins',
                color: AppColors.gold,
              ),
              if (widget.stock >= 0)
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
            const SectionLabel('Video'),
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
            const SectionLabel('Video'),
            GlowCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.link_off_rounded,
                      color: AppColors.gold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'YouTube link not recognized. Use a video link like '
                      'https://youtu.be/… , https://www.youtube.com/watch?v=… '
                      'or https://www.youtube.com/shorts/…',
                      style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ---- claim ----
          const SizedBox(height: 24),
          NeonButton(
            expand: true,
            onPressed: canClaim ? _claim : null,
            child: claiming
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(
                    outOfStock
                        ? 'Out of stock'
                        : affordable
                            ? 'Claim key · ${p.cost} coins'
                            : 'Not enough coins',
                  ),
          ),
          if (!affordable && !outOfStock) ...[
            const SizedBox(height: 10),
            Text(
              'Watch ads on the Earn tab to get ${p.cost - coins} more coins.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
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
          gradient: kTealGradient,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Icon(Icons.key_rounded, color: Colors.white, size: 64),
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
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.textDim, size: 42),
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
                    color: i == _pageIdx
                        ? AppColors.cyan
                        : AppColors.border,
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
