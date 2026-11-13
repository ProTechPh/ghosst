import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:url_launcher/url_launcher.dart';

import 'distribution.dart';

/// Play Store entry points: rating the app and updating it in place.
class PlayStore {
  PlayStore._();

  static const appId = 'com.astrixtech.ghosst';
  static const _web = 'https://play.google.com/store/apps/details?id=$appId';

  /// Public listing link (used as the update fallback).
  static const webUrl = _web;

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

  /// Version code Play wants to install, or null when there is no update /
  /// this is not a Play install. Play Core cannot be asked on the `direct`
  /// flavor, so that path keeps using the server's `minVersionCode`.
  static Future<int?> updateVersionCode() async {
    if (kIsWeb || !Distribution.isPlay) return null;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return null;
      }
      return info.availableVersionCode;
    } catch (_) {
      return null;
    }
  }

  /// Shows Google Play's full-screen (immediate) update flow.
  ///
  /// Play requires [checkForUpdate] in the same session first — calling
  /// [performImmediateUpdate] without it is refused, which is why the gate's
  /// button used to do nothing at all.
  ///
  /// Returns false only when Play could not show its own UI (not a Play
  /// install, no update, or refused); the caller then opens the store listing
  /// instead of leaving the user stuck.
  static Future<bool> startImmediateUpdate() async {
    if (kIsWeb || !Distribution.isPlay) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return false;
      }
      final result = await InAppUpdate.performImmediateUpdate();
      // success / userDeniedUpdate = Play's own screen appeared and the user
      // answered it. inAppUpdateFailed = Play never showed anything.
      return result != AppUpdateResult.inAppUpdateFailed;
    } catch (_) {
      return false;
    }
  }
}
