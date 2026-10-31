import 'package:flutter/material.dart';

import '../arcade.dart';
import '../premium.dart';
import '../services/worker_backend.dart';
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
          sha256: app.claim.sha256,
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
        borderRadius: BorderRadius.circular(AppRadius.input),
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
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
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
          const Positioned.fill(
            child: IgnorePointer(child: TableSurface()),
          ),
          if (loading)
            _skeleton()
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.md,
                    AppSpace.lg,
                    AppSpace.huge,
                  ),
                  children: [
                    const Text('Purchased apps', style: AppText.headline),
                    const SizedBox(height: AppSpace.xs + 2),
                    Text(
                      '${apps.length} app(s) ready to download',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: AppSpace.xl),
                    if (apps.isEmpty)
                      const EmptyState(
                        icon: Icons.apps_outlined,
                        title: 'No apps yet',
                        message:
                            'Buy apps and files with your coins in the Store — '
                            'they show up here to download any time.',
                      )
                    else
                      for (final app in apps) _row(app),
                    if (apps.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.lg),
                      Center(
                        child: Text(
                          'PURCHASED ONCE · DOWNLOAD ANY TIME',
                          textAlign: TextAlign.center,
                          style: AppText.label.copyWith(
                            fontSize: 10,
                            letterSpacing: 2.2,
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

  Widget _skeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.huge,
      ),
      children: [
        const Skeleton(width: 210, height: 28),
        const SizedBox(height: AppSpace.xl),
        for (var i = 0; i < 4; i++)
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
                      Skeleton(width: 160, height: 15),
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

  Widget _row(_OwnedApp app) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
      ),
      child: Pressable(
        onTap: () => _open(app),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          child: Row(
            children: [
              _thumb(app),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(app),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title.copyWith(fontSize: 15.5),
                    ),
                    const SizedBox(height: AppSpace.xs + 2),
                    Text(
                      _meta(app),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Container(
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
                child: const Icon(
                  Icons.download_rounded,
                  size: 17,
                  color: AppColors.cyan,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _date(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;
}
