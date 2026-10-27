import 'dart:io';

import 'package:flutter/services.dart';

/// Runtime identity of the Android product flavor.
///
/// Failure is conservative: unknown builds behave like the Play artifact and
/// never expose APK/file downloads intended only for the Direct build.
class Distribution {
  Distribution._();

  static const channel = MethodChannel('com.astrixtech.ghosst/build');

  static bool _isPlay = true;

  static bool get isPlay => _isPlay;
  static bool get isDirect => !_isPlay;

  /// Both distributions show downloadable products. Play saves APKs to the
  /// public Downloads folder for manual installation; only Direct can launch
  /// Android's installer from inside the app.
  static bool get showsDownloadStore => true;

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
