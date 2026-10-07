import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../premium.dart';
import '../services/backend.dart';
import '../services/download_service.dart';
import '../services/mediafire.dart';
import '../theme.dart';

/// Full-screen, un-skippable update gate.
///
/// Replaces the entire app tree at launch whenever the backend announces a
/// newer build: there is no route to pop and no close button — users update
/// or they don't get in. The APK downloads inside the app (live progress),
/// then the system installer takes over; cancelling the install sheet just
/// lands back here with an "Install now" retry (no re-download).
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.info,
    required this.currentBuild,
  });

  final UpdateInfo info;

  /// This build's `buildNumber` (from `pubspec` `1.0.0+N`).
  final int currentBuild;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  DownloadTask? _task;
  DownloadProgress? _progress;
  File? _file;
  bool _working = false;
  String _error = '';

  @override
  void dispose() {
    _task?.cancel();
    super.dispose();
  }

  bool get _downloading => _working && _file == null;

  /// Downloads the announcement's APK, then hands it straight to the
  /// installer (the promised auto-download → install-prompt flow).
  void _startUpdate() {
    setState(() {
      _working = true;
      _error = '';
      _progress = null;
    });
    final name = widget.info.versionName.trim().isEmpty
        ? 'build-${widget.info.versionCode}'
        : widget.info.versionName.trim();
    _task = DownloadService.start(
      pageUrl: widget.info.url,
      preferredName: 'ghosst-$name.apk',
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      onDone: (file) async {
        if (!mounted) return;
        setState(() => _file = file);
        await _openInstaller();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _working = false;
          _error = e is DownloadException || e is MediaFireException
              ? e.toString()
              : 'Download failed: $e';
        });
      },
    );
  }

  /// Hands the finished APK to Android's package installer.
  Future<void> _openInstaller() async {
    final f = _file;
    if (f == null) return;
    setState(() {
      _working = true;
      _error = '';
    });
    try {
      final r = await OpenFilex.open(
        f.path,
        type: 'application/vnd.android.package-archive',
      );
      if (!mounted) return;
      setState(() {
        // done → the system sheet is on top. Cancelling it returns here,
        // where the button already reads "Install now".
        _working = false;
        if (r.type != ResultType.done) {
          _error = r.message.isEmpty
              ? 'Could not start the installer'
              : r.message;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = '$e';
      });
    }
  }

  String _fmt(int bytes) {
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final p = _progress;
    final newName = info.versionName.trim().isEmpty
        ? 'v${info.versionCode}'
        : info.versionName.trim();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          const MeshBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionLabel('Update required'),
                      const Text(
                        'A new Ghosst version is ready',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please update to keep using the app — '
                        'this only takes a moment.',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ---- version comparison card ----
                      DoubleBezel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'INSTALLED',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 2.2,
                                          color: AppColors.textDim,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'build ${widget.currentBuild}',
                                        style: monoStyle(
                                          fontSize: 14,
                                          color: AppColors.textDim,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 17,
                                  color: AppColors.gold,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        'NEW VERSION',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 2.2,
                                          color: AppColors.gold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$newName · build ${info.versionCode}',
                                        textAlign: TextAlign.right,
                                        style: monoStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (info.message.trim().isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Divider(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              const SizedBox(height: 14),
                              const SectionLabel("What's new"),
                              Text(
                                info.message.trim(),
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error,
                          style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],

                      // ---- live progress while the APK streams in ----
                      if (_downloading) ...[
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: p?.fraction,
                            minHeight: 6,
                            color: AppColors.primary,
                            backgroundColor: AppColors.surfaceHigh,
                          ),
                        ),
                        if (p != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                p.total > 0
                                    ? '${_fmt(p.received)} / ${_fmt(p.total)}'
                                    : _fmt(p.received),
                                style: monoStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textDim,
                                ),
                              ),
                              Text(
                                '${_fmt(p.speed)}/s',
                                style: monoStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textDim,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],

                      const SizedBox(height: 18),
                      IslandButton(
                        expand: true,
                        busy: _working,
                        label: _file != null ? 'Install now' : 'Update now',
                        icon: Icons.system_update_rounded,
                        onPressed: _working
                            ? null
                            : _file != null
                            ? _openInstaller
                            : _startUpdate,
                      ),
                      const SizedBox(height: 14),
                      const Center(
                        child: Text(
                          'YOUR ACCOUNT, KEYS AND COINS STAY · '
                          'THE UPDATE INSTALLS OVER THIS APP',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                            color: AppColors.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
