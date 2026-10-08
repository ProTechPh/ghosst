import 'dart:async';

import 'package:flutter/services.dart';

/// Snapshot of an in-flight / finished official-APK download.
class ApkDownloadState {
  const ApkDownloadState({
    required this.state,
    this.received = 0,
    this.total = 0,
    this.message = '',
    this.uri = '',
  });

  /// Native status: `pending`, `running`, `paused`, `successful`, `failed`
  /// or `missing` (the DownloadManager no longer knows the id).
  final String state;

  final int received;
  final int total; // 0 when unknown
  final String message; // failure reason, when [state] is `failed`
  final String uri; // content:// location of the finished file

  bool get done => state == 'successful';
  bool get failed =>
      state == 'failed' || state == 'missing' || state == 'error';

  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  static const ApkDownloadState unknown = ApkDownloadState(state: 'error');
}

/// Official-APK download driven by Android's system DownloadManager.
///
/// The file is written straight into the public `Downloads` folder rather
/// than the app sandbox on purpose: the modified build this screen is shown
/// on has to be uninstalled before the official one can be installed, and
/// anything in the sandbox dies with it. DownloadManager also survives the
/// uninstall — its "Download complete" notification is what the user taps to
/// install once this copy is gone.
class OfficialApk {
  OfficialApk._();

  /// Channel shared with `MainActivity.kt`.
  static const MethodChannel channel = MethodChannel(
    'com.astrixtech.ghosst/apk',
  );

  /// Queues the download and returns its DownloadManager id.
  static Future<int> start({required String url, required String name}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const DownloadLinkException('That download link is not valid');
    }
    final id = await channel
        .invokeMethod<int>('start', <String, Object?>{
          'url': uri.toString(),
          'name': name,
        })
        // Never leave the button spinning if the platform side goes quiet.
        .timeout(const Duration(seconds: 15));
    if (id == null) {
      throw const DownloadLinkException('Could not start the download');
    }
    return id;
  }

  /// Asks DownloadManager where [id] is. Throws when the platform channel is
  /// gone (shouldn't happen on Android, but never leaves the UI hanging).
  static Future<ApkDownloadState> status(int id) async {
    final raw = await channel
        .invokeMapMethod<String, Object?>('status', <String, Object?>{'id': id})
        .timeout(const Duration(seconds: 10));
    if (raw == null) return ApkDownloadState.unknown;
    return ApkDownloadState(
      state: (raw['state'] as String?) ?? 'missing',
      received: (raw['received'] as num?)?.toInt() ?? 0,
      total: (raw['total'] as num?)?.toInt() ?? 0,
      message: (raw['message'] as String?) ?? '',
      uri: (raw['uri'] as String?) ?? '',
    );
  }
}

/// A link the app refuses to hand to DownloadManager.
class DownloadLinkException implements Exception {
  const DownloadLinkException(this.message);
  final String message;

  @override
  String toString() => message;
}
