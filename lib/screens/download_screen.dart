import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../appwrite_client.dart';
import '../premium.dart';
import '../services/download_service.dart';
import '../services/mediafire.dart';
import '../theme.dart';

enum _State { idle, running, done, failed }

/// In-app download manager for store purchases.
///
/// Resolves the MediaFire link, streams the file with a live progress bar,
/// then offers **Install** (APK) / **Open** (other files). No share/URL
/// export — the raw link never leaves this screen.
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({
    super.key,
    required this.url,
    required this.title,
    this.kind = 'file',
    this.version = '',
    this.fileSize = '',
    this.preferredName = '',
    this.imageUrl = '',
    this.youtubeUrl = '',
  });

  /// MediaFire share page (or a direct link).
  final String url;
  final String title;

  /// Product cover art (same file the store / details screens show).
  final String imageUrl;

  /// `'apk'` | `'file'`.
  final String kind;

  final String version;
  final String fileSize;
  final String preferredName;

  /// Product's YouTube tutorial (optional) — offers a "Watch tutorial"
  /// button on the downloaded state so buyers can learn the app after install.
  final String youtubeUrl;

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  _State _state = _State.idle;
  DownloadProgress? _progress;
  DownloadTask? _task;
  File? _file;
  String _error = '';

  bool get _isApk => widget.kind == 'apk';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _task?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _state = _State.running;
      _error = '';
      _progress = null;
      _file = null;
    });
    final name = widget.preferredName.trim().isEmpty
        ? null
        : widget.preferredName.trim();

    _task = DownloadService.start(
      pageUrl: widget.url,
      preferredName: name,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
      onDone: (file) {
        if (!mounted) return;
        setState(() {
          _file = file;
          _state = _State.done;
        });
      },
      onError: (e) {
        if (!mounted) return;
        final cancelled =
            e is DownloadException && e.message.toLowerCase() == 'cancelled';
        setState(() {
          if (cancelled) {
            _state = _State.idle;
            _progress = null;
          } else {
            _state = _State.failed;
            _error = e is MediaFireException || e is DownloadException
                ? e.toString()
                : 'Download failed: $e';
          }
        });
      },
    );

    // Cheap UI tick so the speed counter keeps moving between chunks.
    if (!mounted) return;
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _state != _State.running) {
        t.cancel();
        return;
      }
      setState(() {});
    });
  }

  void _cancel() {
    _task?.cancel();
    setState(() => _state = _State.idle);
  }

  Future<void> _openFile() async {
    final f = _file;
    if (f == null) return;
    try {
      final type = _isApk ? 'application/vnd.android.package-archive' : null;
      final r = await OpenFilex.open(f.path, type: type);
      if (r.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open: ${r.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    final pct = p?.fraction;

    return Scaffold(
      appBar: AppBar(title: Text(_isApk ? 'Install app' : 'Download file')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: [
          // ---- product header ------------------------------------------
          GlowCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _cover(),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          NeonPill(
                            icon: _isApk
                                ? Icons.android_rounded
                                : Icons.insert_drive_file_outlined,
                            label: _isApk ? 'APK' : 'FILE',
                            color: AppColors.cyan,
                          ),
                          if (widget.version.isNotEmpty)
                            NeonPill(
                              icon: Icons.tag_rounded,
                              label: widget.version,
                              color: AppColors.textDim,
                            ),
                          if (widget.fileSize.isNotEmpty)
                            NeonPill(
                              icon: Icons.data_usage_rounded,
                              label: widget.fileSize,
                              color: AppColors.gold,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ---- progress / result ---------------------------------------
          if (_state == _State.idle) _idleView(),
          if (_state == _State.running) _progressView(p, pct),
          if (_state == _State.done) _doneView(),
          if (_state == _State.failed) _failedView(),
        ],
      ),
    );
  }

  // ---- states ----------------------------------------------------------

  /// Product cover — the same art shown on the store card and the details
  /// screen. Falls back to the gradient icon when the product has no image
  /// or the file fails to load.
  Widget _cover() {
    final url = widget.imageUrl.trim();
    if (url.isEmpty) return _coverFallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Image.network(
        url,
        headers: const {'X-Appwrite-Project': appwriteProjectId},
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _coverFallback(),
      ),
    );
  }

  Widget _coverFallback() => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      gradient: _isApk ? kNeonGradient : kTealGradient,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Icon(
      _isApk ? Icons.android_rounded : Icons.download_rounded,
      color: Colors.white,
      size: 26,
    ),
  );

  Widget _idleView() {
    return DoubleBezel(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'Download paused.',
            style: TextStyle(color: AppColors.textDim, fontSize: 14),
          ),
          const SizedBox(height: 16),
          IslandButton(
            expand: true,
            label: 'Start download',
            icon: CupertinoIcons.download_circle,
            onPressed: _start,
          ),
        ],
      ),
    );
  }

  Widget _progressView(DownloadProgress? p, double? pct) {
    final total = p?.total ?? 0;
    final received = p?.received ?? 0;
    final resolving = p == null || (received == 0 && total == 0);

    return DoubleBezel(
      padding: const EdgeInsets.all(20),
      glowColor: AppColors.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                resolving ? 'RESOLVING LINK' : 'DOWNLOADING',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                  color: AppColors.textDim,
                ),
              ),
              if (!resolving && pct != null)
                Text(
                  '${(pct * 100).toStringAsFixed(0)}%',
                  style: monoStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.cyan,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
            ),
          ),
          const SizedBox(height: 16),
          if (!resolving)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_fmt(received)}${total > 0 ? ' / ${_fmt(total)}' : ''}',
                  style: monoStyle(fontSize: 13, color: AppColors.textDim),
                ),
                Text(
                  p.speed > 0 ? '${_fmt(p.speed)}/s' : '—',
                  style: monoStyle(fontSize: 13, color: AppColors.text),
                ),
              ],
            )
          else
            Text(
              p?.label ?? '',
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 20),
          IslandButton(
            expand: true,
            outline: true,
            glow: false,
            label: 'Cancel',
            icon: CupertinoIcons.xmark_circle,
            onPressed: _cancel,
          ),
        ],
      ),
    );
  }

  /// Opens the product's tutorial on YouTube (external app) — the download
  /// screen stays put so the user can come back and install afterwards.
  Future<void> _openTutorial() async {
    final url = widget.youtubeUrl.trim();
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Never block the screen on a missing browser / YouTube app.
    }
  }

  Widget _doneView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DoubleBezel(
          padding: const EdgeInsets.all(20),
          glowColor: AppColors.green,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DOWNLOADED',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                      color: AppColors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _file?.path.split(Platform.pathSeparator).last ?? '',
                style: monoStyle(fontSize: 13.5, color: AppColors.text),
              ),
              const SizedBox(height: 6),
              Text(
                _file != null ? _fmt(_file!.lengthSync()) : '',
                style: monoStyle(fontSize: 12.5, color: AppColors.textDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        IslandButton(
          expand: true,
          label: _isApk ? 'Install' : 'Open file',
          icon: _isApk ? Icons.android_rounded : Icons.open_in_new_rounded,
          onPressed: _openFile,
        ),
        const SizedBox(height: 10),
        IslandButton(
          expand: true,
          dense: true,
          outline: true,
          glow: false,
          label: 'Download',
          icon: CupertinoIcons.arrow_clockwise,
          onPressed: _start,
        ),
        if (widget.youtubeUrl.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          IslandButton(
            expand: true,
            dense: true,
            outline: true,
            glow: false,
            label: 'Watch tutorial',
            icon: Icons.play_circle_outline_rounded,
            onPressed: _openTutorial,
          ),
        ],
        const SizedBox(height: 14),
        const Center(
          child: Text(
            'SAVED TO APP DOWNLOADS · FIND IT ANY TIME IN MY KEYS',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
              color: AppColors.textDim,
            ),
          ),
        ),
      ],
    );
  }

  Widget _failedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DoubleBezel(
          padding: const EdgeInsets.all(20),
          borderColor: AppColors.red.withValues(alpha: 0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.red,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'DOWNLOAD FAILED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _error,
                style: const TextStyle(
                  color: AppColors.red,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        IslandButton(
          expand: true,
          label: 'Try again',
          icon: CupertinoIcons.arrow_clockwise,
          onPressed: _start,
        ),
      ],
    );
  }

  static String _fmt(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final s = v >= 100 || i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$s ${units[i]}';
  }
}
