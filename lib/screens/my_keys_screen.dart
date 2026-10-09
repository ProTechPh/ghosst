import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../appwrite_client.dart';
import '../services/backend.dart';
import '../services/distribution.dart';
import '../theme.dart';
import 'download_screen.dart';

class MyKeysScreen extends StatefulWidget {
  const MyKeysScreen({super.key});

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

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final allClaims = await Backend.myClaims();
      final c = Distribution.isPlay
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
      if (!mounted) return;
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
        ),
      ),
    );
    if (mounted) _load();
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
              style: const TextStyle(color: AppColors.textDim),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bgSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                c.keyText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColors.text,
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

  /// 44px cover — product art when we have it, gradient tile otherwise.
  Widget _thumb(Claim c) {
    const fallback = Icon(
      Icons.shopping_bag_outlined,
      color: Colors.white,
      size: 22,
    );
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: c.isDownload
            ? (c.keyText == 'apk' ? kNeonGradient : kGoldGradient)
            : kTealGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: () {
        final url = productArt[c.productId];
        if (url == null) {
          return c.isDownload
              ? fallback
              : const Icon(Icons.key_rounded, color: Colors.white, size: 22);
        }
        return Image.network(
          url,
          headers: const {'X-Appwrite-Project': appwriteProjectId},
          fit: BoxFit.cover,
          errorBuilder: (ctx, e, st) => c.isDownload
              ? fallback
              : const Icon(Icons.key_rounded, color: Colors.white, size: 22),
        );
      }(),
    );
  }

  /// APP / KEY category tag so the list reads like a purchase history.
  Widget _catBadge(Claim c) {
    final color = c.isDownload ? AppColors.gold : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Text(
        c.isDownload ? 'APP' : 'KEY',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          const SectionLabel('My purchases'),
          const Text(
            'My purchases',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${claims.length} purchase(s) in your collection',
            style: const TextStyle(color: AppColors.textDim, fontSize: 13.5),
          ),
          const SizedBox(height: 20),
          if (claims.isEmpty)
            const EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'No purchases yet',
              message:
                  'Watch ads to earn coins, then claim your first key or app in the Store.',
            ),
          for (final c in claims) ...[
            GlowCard(
              padding: const EdgeInsets.fromLTRB(16, 15, 13, 15),
              onTap: () => c.isDownload ? _openDownload(c) : _showKey(c),
              child: Row(
                children: [
                  _thumb(c),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.productName.isEmpty
                                    ? (c.isDownload
                                          ? 'Download'
                                          : 'License key')
                                    : c.productName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _catBadge(c),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${_date(c.createdAt)} · ${c.cost} coins'
                          '${c.duration.isEmpty ? '' : ' · ${c.duration}'}'
                          '${c.isDownload ? ' · ${c.keyText == 'apk' ? 'APK' : 'FILE'}' : ''}',
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(
                      c.isDownload
                          ? Icons.download_rounded
                          : Icons.copy_rounded,
                      size: 18,
                      color: AppColors.cyan,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  String _date(String iso) {
    if (iso.length < 10) return iso;
    return iso.substring(0, 10);
  }
}
