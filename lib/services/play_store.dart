import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

import 'distribution.dart';

/// Play Store entry points: rating the app and updating it in place.
class PlayStore {
  PlayStore._();

  static const appId = 'com.astrixtech.ghosst';
  static const _web = 'https://play.google.com/store/apps/details?id=$appId';

  /// Opens the listing in the Play app, falling back to the browser.
  static Future<void> rate() async {
    if (await _open(Uri.parse('market://details?id=$appId'))) return;
    await _open(Uri.parse(_web));
  }

  static Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// True when Play had an update and showed its full-screen flow.
  ///
  /// Only Play can answer, so a debug build, the `direct` flavor or a
  /// sideloaded APK just gets `false` — never an error the user must read.
  static Future<bool> checkForUpdate() async {
    if (kIsWeb || !Distribution.isPlay) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return false;
      }
      await InAppUpdate.performImmediateUpdate();
      return true;
    } catch (_) {
      return false;
    }
  }
}
