import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'install_id.dart';
import 'worker_backend.dart';

/// Novu broadcast notifications, delivered as FCM through the API.
///
/// The app holds no secret: it only reports its FCM token, keyed by the
/// anonymous [InstallId], to `POST /v1/push/register`. Everything here fails
/// softly, so a missing Firebase app or a dead network never blocks the app.
class Push {
  Push._();

  /// Set once the splash (and the launch gates behind it) are done. The
  /// permission dialog must never sit over those screens.
  static bool splashDone = false;

  static bool get canAsk => splashDone;

  /// Bumped for every push that lands while the app is in front. Android does
  /// not show FCM `notification` messages in that state, so the shell listens
  /// here and reloads the announcement banner instead of a tray notification.
  static final ValueNotifier<int> foreground = ValueNotifier<int>(0);

  static void handleForeground(RemoteMessage _) => foreground.value++;

  /// Firebase is already up (`ChatService.init()` runs first): listen for
  /// foreground messages, ask for the FCM token, hand it to the API, and
  /// repeat on every rotation.
  static Future<void> init() async {
    try {
      FirebaseMessaging.onMessage.listen(handleForeground);

      // shortcut: firebase_messaging 17 points at register()/onRegistered
      // (Firebase Installation ID) instead; Novu's FCM provider still wants a
      // registration token. Upgrade when Novu accepts FID targets.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      await _register(token);
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen(_register);
    } catch (_) {
      // A push SDK that cannot start must never block the app.
    }
  }

  static Future<void> _register(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await Backend.registerPush(installId: await InstallId.get(), token: token);
    } catch (_) {}
  }

  /// Askable only after the splash: see [splashDone].
  static Future<void> requestPermission() async {
    if (!canAsk) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
  }
}
