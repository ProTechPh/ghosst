import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'mediafire.dart';

/// Progress snapshot emitted while a file streams to disk.
class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.speed,
    required this.label,
  });

  final int received;
  final int total; // 0 when unknown
  final int speed; // bytes/sec
  final String label; // suggested file name (before sanitising)

  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

class DownloadException implements Exception {
  const DownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Streams files into the app's private external directory.
///
/// Using `getApplicationSupportDirectory()`/`getExternalStorageDirectory()`
/// keeps the download inside the app sandbox, so no runtime storage permission
/// is required (Android scoped-storage friendly).
class DownloadService {
  DownloadService._();

  static DownloadTask? _current;

  /// Directory that downloads land in: `<app external files>/downloads`.
  ///
  /// Prefer the app-specific external dir (visible to `share_plus` /
  /// `open_filex` FileProvider, no storage permission needed) and fall back
  /// to the internal support dir on devices without external storage.
  static Future<Directory> downloadDir() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static DownloadTask? get current => _current;

  /// Resolves [pageUrl] (MediaFire share page or direct link) and streams it
  /// to a file in the app download directory.
  ///
  /// Returns the running task; [onDone] fires with the finished file.
  static DownloadTask start({
    required String pageUrl,
    String? preferredName,
    required void Function(DownloadProgress) onProgress,
    required void Function(File file) onDone,
    required void Function(Object error) onError,
  }) {
    final task = DownloadTask._(
      pageUrl: pageUrl,
      preferredName: preferredName,
      onProgress: onProgress,
      onDone: onDone,
      onError: onError,
    );
    _current = task;
    unawaited(task._run());
    return task;
  }

  /// Best-effort guess at the file name from the URL path.
  static String nameFromUrl(String url) {
    try {
      final segs = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty);
      if (segs.isNotEmpty) {
        final last = Uri.decodeComponent(segs.last);
        if (last.contains('.')) return _sanitize(last);
      }
    } catch (_) {}
    return 'download';
  }

  static String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'download' : cleaned;
  }
}

/// A single in-flight download. Call [cancel] to abort (partially written
/// file is deleted).
class DownloadTask {
  DownloadTask._({
    required this.pageUrl,
    required this.preferredName,
    required this.onProgress,
    required this.onDone,
    required this.onError,
  });

  final String pageUrl;
  final String? preferredName;
  final void Function(DownloadProgress) onProgress;
  final void Function(File file) onDone;
  final void Function(Object error) onError;

  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  Future<void> _run() async {
    final client = HttpClient()..userAgent = MediaFire.ua;
    File? partial;
    try {
      // ---- resolve -------------------------------------------------------
      _emit(0, 0, 0, 'Resolving download link…');
      final direct = await MediaFire.resolveDirectUrl(pageUrl);

      // ---- open stream ---------------------------------------------------
      final uri = Uri.parse(direct);
      final req = await client.getUrl(uri)
          .timeout(const Duration(seconds: 30));
      req.followRedirects = true;
      req.maxRedirects = 8;
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) {
        throw DownloadException('Download failed (${res.statusCode})');
      }

      var name = preferredName?.trim() ?? '';
      if (name.isEmpty) {
        final cd = res.headers.value('content-disposition') ?? '';
        final m = RegExp(
          r'filename\*?=(?:UTF-8\x27\x27)?"?([^";]+)"?',
          caseSensitive: false,
        ).firstMatch(cd);
        if (m != null) {
          name = Uri.decodeComponent(m.group(1)!).trim();
        }
      }
      if (name.isEmpty) name = DownloadService.nameFromUrl(direct);
      // strip any path separators the header may have smuggled in
      name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (name.isEmpty) name = 'download';

      final dir = await DownloadService.downloadDir();
      partial = File('${dir.path}${Platform.pathSeparator}$name.part');
      if (partial.existsSync()) partial.deleteSync();

      final out = partial.openWrite();
      var received = 0;
      var total = res.contentLength; // -1 when unknown
      if (total < 0) total = 0;
      var windowBytes = 0;
      final watch = Stopwatch()..start();
      var speed = 0;

      await for (final chunk in res) {
        if (_cancelled) {
          await out.close();
          if (partial.existsSync()) partial.deleteSync();
          throw const DownloadException('Cancelled');
        }
        out.add(chunk);
        received += chunk.length;
        windowBytes += chunk.length;
        if (watch.elapsedMilliseconds >= 500) {
          speed = (windowBytes * 1000) ~/ watch.elapsedMilliseconds;
          watch.reset();
          windowBytes = 0;
        }
        _emit(received, total, speed, name);
      }
      await out.flush();
      await out.close();

      if (_cancelled) {
        if (partial.existsSync()) partial.deleteSync();
        throw const DownloadException('Cancelled');
      }

      final file = File(
        '${dir.path}${Platform.pathSeparator}$name',
      );
      if (file.existsSync()) file.deleteSync();
      final saved = await partial.rename(file.path);
      _emit(received, total > 0 ? total : received, 0, name);
      onDone(saved);
    } catch (e) {
      if (partial != null && partial.existsSync()) {
        try {
          partial.deleteSync();
        } catch (_) {}
      }
      onError(e);
      return;
    } finally {
      client.close(force: true);
    }
  }

  void _emit(int received, int total, int speed, String label) {
    onProgress(DownloadProgress(
      received: received,
      total: total,
      speed: speed,
      label: label,
    ));
  }
}
