import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../premium.dart';
import '../services/backend.dart';
import '../services/download_service.dart';
import '../services/mediafire.dart';
import '../theme.dart';

/// Streams an APK in-app (live progress) and hands it to the system
/// installer.
///
/// Shared by the forced-update gate and the modified-app gate so both paths
/// download and install the exact same way — one implementation to fix, one
/// behaviour to reason about.
class ApkInstaller extends StatefulWidget {
  const ApkInstaller({
    super.key,
    required this.info,
    this.label = 'Update now',
    this.icon = Icons.system_update_rounded,
  });

  /// Announcement carrying the APK link (MediaFire share page or direct URL).
  final UpdateInfo info;

  /// CTA before anything is downloaded — e.g. `Update now` / `Download
  /// official app`. Once the file is local it becomes `Install now`.
  final String label;

  final IconData icon;

  @override
  State<ApkInstaller> createState() => _ApkInstallerState();
}

class _ApkInstallerState extends State<ApkInstaller> {
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
  /// installer (auto-download → install-prompt flow).
  void _startDownload() {
    setState(() {
      _working = true;
      _error = '';
      _progress = null;
    });
    final info = widget.info;
    final name = info.versionName.trim().isEmpty
        ? 'build-${info.versionCode}'
        : info.versionName.trim();
    _task = DownloadService.start(
      pageUrl: info.url,
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
    final p = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          label: _file != null ? 'Install now' : widget.label,
          icon: _file != null ? Icons.system_update_rounded : widget.icon,
          onPressed: _working
              ? null
              : _file != null
              ? _openInstaller
              : _startDownload,
        ),
      ],
    );
  }
}
