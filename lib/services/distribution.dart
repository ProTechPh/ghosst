import 'dart:io';

import 'package:flutter/services.dart';

/// Runtime identity of the Android product flavor.
///
/// Failure is conservative: unknown builds behave like the Play artifact and
/// never expose APK/file downloads intended only for the Direct build.
class Distribution {
  Distribution._();

  static const channel = MethodChannel('com.astrixtech.ghosst/build');

  /// Explicit exception for closed-beta/QA Play builds. Live Play artifacts
  /// leave this false so APK/file downloads are not exposed to production.
  static const bool _enableDownloadStoreForPlay = bool.fromEnvironment(
    'ENABLE_DOWNLOAD_STORE',
    defaultValue: false,
  );

  static bool _isPlay = true;

  static bool get isPlay => _isPlay;
  static bool get isDirect => !_isPlay;
  static bool get showsDownloadStore => isDirect || _enableDownloadStoreForPlay;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) {
      _isPlay = true;
      return;
    }
    try {
      final flavor = await channel.invokeMethod<String>('distribution');
      _isPlay = flavor != 'direct';
    } catch (_) {
      _isPlay = true;
    }
  }

  static void setPlayForTesting(bool value) => _isPlay = value;
}
