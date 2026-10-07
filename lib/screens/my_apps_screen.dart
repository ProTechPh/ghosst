import 'package:flutter/material.dart';

import '../appwrite_client.dart';
import '../premium.dart';
import '../services/backend.dart';
import '../theme.dart';
import 'download_screen.dart';

/// One owned app, grouped from the purchase claims (newest claim wins).
class _OwnedApp {
  const _OwnedApp({required this.claim, required this.product});

  final Claim claim;

  /// Product metadata — `null` when the doc was deleted or is unreadable.
  final Product? product;
}

/// "App Owned" — every app/file the user bought, ready to re-download.
class MyAppsScreen extends StatefulWidget {
  const MyAppsScreen({super.key});

  @override
  State<MyAppsScreen> createState() => _MyAppsScreenState();
}

class _MyAppsScreenState extends State<MyAppsScreen> {
  List<_OwnedApp> apps = [];
  bool loading = true;
  String error = '';

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
      final claims = await Backend.myClaims();
      // One entry per product — claims arrive newest-first, so the first
      // claim we see for an id carries the freshest download link.
      final byProduct = <String, Claim>{};
      for (final c in claims) {
        if (!c.isDownload) continue;
        byProduct.putIfAbsent(c.productId, () => c);
      }
      // Enrich with cover art / version / size — best-effort, cosmetic only.
      final products = await Future.wait(
        byProduct.keys.map((id) => Backend.product(id).catchError((_) => null)),
      );
      if (!mounted) return;
      setState(() {
        apps = [
          for (var i = 0; i < byProduct.length; i++)
            _OwnedApp(
              claim: byProduct.values.elementAt(i),
              product: products[i],
            ),
        ];
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

  bool _isApk(_OwnedApp app) =>
      app.claim.keyText == 'apk' || (app.product?.isApk ?? false);

  String _title(_OwnedApp app) {
    final name = app.product?.name ?? '';
    if (name.isNotEmpty) return name;
    return app.claim.productName.isEmpty ? 'Download' : app.claim.productName;
  }

  void _open(_OwnedApp app) {
    final url = app.claim.downloadUrl;
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download link unavailable — contact support'),
        ),
      );
      return;
    }
    final isApk = _isApk(app);
    final name = _title(app);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DownloadScreen(
          url: url,
          title: name,
          kind: isApk ? 'apk' : 'file',
          version: app.product?.version ?? '',
          fileSize: app.product?.fileSize ?? '',
          preferredName: isApk ? '$name.apk' : '',
          imageUrl: Backend.productThumbUrl(app.product?.imageIds ?? const []),
          youtubeUrl: app.product?.youtubeUrl ?? '',
        ),
      ),
    );
  }

  Widget _thumb(_OwnedApp app) {
    final isApk = _isApk(app);
    final fallback = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: isApk ? kNeonGradient : kGoldGradient,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        isApk ? Icons.android_rounded : Icons.insert_drive_file_outlined,
        color: Colors.white,
        size: 20,
      ),
    );
    final url = Backend.productThumbUrl(app.product?.imageIds ?? const []);
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        headers: const {'X-Appwrite-Project': appwriteProjectId},
        errorBuilder: (c, e, s) => fallback,
      ),
    );
  }

  String _meta(_OwnedApp app) {
    final p = app.product;
    return [
      _date(app.claim.createdAt),
      _isApk(app) ? 'APK' : 'FILE',
      if (p != null && p.version.isNotEmpty) p.version,
      if (p != null && p.fileSize.isNotEmpty) p.fileSize,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(titleSpacing: 20, title: const Text('App Owned')),
      body: Stack(
        children: [
          const MeshBackground(),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (error.isNotEmpty)
            SafeArea(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load apps',
                message: error,
                action: NeonButton(
                  dense: true,
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: RefreshIndicator(
                color: AppColors.cyan,
                backgroundColor: AppColors.surface,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    const SectionLabel('App owned'),
                    const Text(
                      'Purchased apps',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${apps.length} app(s) ready to download',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (apps.isEmpty)
                      const EmptyState(
                        icon: Icons.apps_outlined,
                        title: 'No apps yet',
                        message:
                            'Buy apps and files with your coins in the Store — '
                            'they show up here to download any time.',
                      ),
                    for (final app in apps) ...[
                      GlowCard(
                        padding: const EdgeInsets.all(14),
                        onTap: () => _open(app),
                        child: Row(
                          children: [
                            _thumb(app),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _title(app),
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _meta(app),
                                    style: const TextStyle(
                                      color: AppColors.textDim,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.cyan.withValues(alpha: 0.10),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.cyan.withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Icon(
                                Icons.download_rounded,
                                size: 17,
                                color: AppColors.cyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (apps.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Center(
                        child: Text(
                          'PURCHASED ONCE · DOWNLOAD ANY TIME',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.4,
                            color: AppColors.textDim,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _date(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;
}
