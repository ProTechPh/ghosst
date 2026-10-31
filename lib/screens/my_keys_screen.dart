import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../arcade.dart';
import '../premium.dart';
import '../services/worker_backend.dart';
import '../services/distribution.dart';
import '../theme.dart';
import 'download_screen.dart';

class MyKeysScreen extends StatefulWidget {
  const MyKeysScreen({super.key, this.active = true, this.onGoToStore});

  /// Whether this tab is the currently visible one (see didUpdateWidget).
  final bool active;

  /// Optional jump to the Store tab, used by the empty state.
  final VoidCallback? onGoToStore;

  @override
  State<MyKeysScreen> createState() => _MyKeysScreenState();
}

class _MyKeysScreenState extends State<MyKeysScreen> {
  List<Claim> claims = [];
  bool loading = true;
  String error = '';

  /// productId -> cover image URL. Best-effort: rows keep their gradient
  /// tile whenever art is missing (deleted product, no image, offline).
  Map<String, String> productArt = {};

  /// productId -> YouTube tutorial URL (optional), same best-effort rules.
  Map<String, String> productYt = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MyKeysScreen old) {
    super.didUpdateWidget(old);
    // IndexedStack keeps this tab's data forever — re-read whenever the tab
    // becomes visible again, so a key claimed after sign-in shows up.
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
      final allClaims = await Backend.myClaims();
      final c = !Distribution.showsDownloadStore
          ? allClaims.where((claim) => !claim.isDownload).toList()
          : allClaims;

      // Cover art per product — cosmetic, never blocks the list.
      final art = <String, String>{};
      final ytMap = <String, String>{};
      try {
        final ids = c.map((x) => x.productId).toSet().toList();
        final prods = await Future.wait(
          ids.map((id) => Backend.product(id).catchError((_) => null)),
        );
        for (var i = 0; i < ids.length; i++) {
          final p = prods[i];
          if (p == null) continue;
          final url = Backend.productThumbUrl(p.imageIds);
          if (url.isNotEmpty) art[ids[i]] = url;
          final yt = p.youtubeUrl.trim();
          if (yt.isNotEmpty) ytMap[ids[i]] = yt;
        }
      } catch (_) {
        // Art is cosmetic — keep the list without it.
      }

      if (!mounted) return;
      setState(() {
        claims = c;
        productArt = art;
        productYt = ytMap;
        loading = false;
      });
    } catch (e) {
      // A silent refresh failure keeps showing the last good list.
      if (silent || !mounted) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  /// Downloads kept for a purchase — the MediaFire link was stored on the
  /// `claims` doc (readable by its owner only).
  Future<void> _openDownload(Claim c) async {
    if (c.downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download link unavailable — contact support'),
        ),
      );
      return;
    }
    final isApk = c.keyText == 'apk';
    // Recover the cover art so the download screen matches the details page.
    var thumb = productArt[c.productId] ?? '';
    var yt = productYt[c.productId] ?? '';
    if (thumb.isEmpty || yt.isEmpty) {
      try {
        final prod = await Backend.product(c.productId);
        if (thumb.isEmpty) {
          thumb = Backend.productThumbUrl(prod?.imageIds ?? const []);
        }
        if (yt.isEmpty) yt = prod?.youtubeUrl.trim() ?? '';
      } catch (_) {
        // Art is cosmetic — never block a download on it.
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DownloadScreen(
          url: c.downloadUrl,
          title: c.productName,
          kind: isApk ? 'apk' : 'file',
          preferredName: isApk ? '${c.productName}.apk' : '',
          imageUrl: thumb,
          youtubeUrl: yt,
          sha256: c.sha256,
        ),
      ),
    );
    if (mounted) _load();
  }

  void _copyKey(Claim c) {
    if (c.keyText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: c.keyText));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Key copied')));
  }

  void _showKey(Claim c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.key_rounded,
            color: AppColors.primary,
            size: 32,
          ),
        ),
        title: Text(c.productName.isEmpty ? 'Your key' : c.productName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_date(c.createdAt)} · ${c.cost} coins'
              '${c.duration.isEmpty ? '' : ' · ${c.duration}'}',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpace.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.md + 2),
              decoration: BoxDecoration(
                color: AppColors.bgSoft,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                c.keyText,
                style: monoStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: c.keyText));
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          NeonButton(
            dense: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// 48px cover — product art when we have it, gradient tile otherwise.
  Widget _thumb(Claim c) {
    const fallback = Icon(
      Icons.shopping_bag_outlined,
      color: Colors.white,
      size: 20,
    );
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: c.isDownload
            ? (c.keyText == 'apk' ? kNeonGradient : kGoldGradient)
            : kTealGradient,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: () {
        final url = productArt[c.productId];
        if (url == null) {
          return c.isDownload
              ? fallback
              : const Icon(Icons.key_rounded, color: Colors.white, size: 20);
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (ctx, e, st) => c.isDownload
              ? fallback
              : const Icon(Icons.key_rounded, color: Colors.white, size: 20),
        );
      }(),
    );
  }

  /// APP / KEY category tag so the list reads like a purchase history.
  Widget _catBadge(Claim c) {
    final color = c.isDownload ? AppColors.primary : AppColors.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        c.isDownload ? 'APP' : 'KEY',
        style: AppText.label.copyWith(
          fontSize: 9.5,
          letterSpacing: 1.4,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return _skeleton();
    if (error.isNotEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load purchases',
        message: error,
        action: NeonButton(
          dense: true,
          onPressed: _load,
          child: const Text('Retry'),
        ),
      );
    }

    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: TableSurface()),
        ),
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.huge,
            ),
            children: [
              const Eyebrow(text: 'Collection'),
              const SizedBox(height: AppSpace.sm),
              const Text('My purchases', style: AppText.headline),
              const SizedBox(height: AppSpace.xs + 2),
              Text(
                '${claims.length} purchase(s) in your collection',
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpace.xl),
              if (claims.isEmpty)
                EmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'No purchases yet',
                  message:
                      'Watch ads to earn coins, then claim your first key or app in the Store.',
                  action: widget.onGoToStore == null
                      ? null
                      : NeonButton(
                          dense: true,
                          onPressed: widget.onGoToStore,
                          child: const Text('Browse the Store'),
                        ),
                )
              else
                for (final c in claims) _row(c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _skeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.huge,
      ),
      children: [
        const Skeleton(width: 190, height: 28),
        const SizedBox(height: AppSpace.xl),
        for (var i = 0; i < 5; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpace.md),
            child: Row(
              children: [
                Skeleton(width: 44, height: 44, radius: AppRadius.input),
                SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 170, height: 15),
                      SizedBox(height: AppSpace.sm),
                      Skeleton(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(Claim c) {
    final name = c.productName.isEmpty
        ? (c.isDownload ? 'Download' : 'License key')
        : c.productName;
    final meta =
        '${_date(c.createdAt)} · ${c.cost} coins'
        '${c.duration.isEmpty ? '' : ' · ${c.duration}'}'
        '${c.isDownload ? ' · ${c.keyText == 'apk' ? 'APK' : 'FILE'}' : ''}';
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
      ),
      child: Pressable(
        onTap: () => c.isDownload ? _openDownload(c) : _showKey(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(c),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.title.copyWith(fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        _catBadge(c),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs + 2),
                    if (c.isDownload)
                      Text(
                        'Ready to download',
                        style: AppText.caption.copyWith(color: AppColors.cyan),
                      )
                    else
                      Text(
                        c.keyText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: AppColors.textDim,
                        ),
                      ),
                    const SizedBox(height: AppSpace.xs),
                    Text(meta, style: AppText.caption),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Pressable(
                onTap: () => c.isDownload ? _openDownload(c) : _copyKey(c),
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Icon(
                    c.isDownload ? Icons.download_rounded : Icons.copy_rounded,
                    size: 17,
                    color: AppColors.cyan,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _date(String iso) {
    if (iso.length < 10) return iso;
    return iso.substring(0, 10);
  }
}
