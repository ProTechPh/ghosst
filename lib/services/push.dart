import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Broadcast notifications straight from FCM: the device joins one topic and
/// the API sends a single topic message. No token, install id or API call —
/// membership lives in FCM and the SDK persists/retries it itself.
class Push {
  Push._();

  /// Must match `PUSH_TOPIC` in `ghosst-web/api/config.php`.
  static const String topic = 'ghosst';

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
  /// foreground messages, then join the broadcast topic.
  static Future<void> init() async {
    try {
      FirebaseMessaging.onMessage.listen(handleForeground);
    } catch (_) {
      // A push SDK that cannot start must never block the app.
    }
    await register();
  }

  /// Idempotent, so the shell repeats it after sign-in in case [init] ran
  /// before Firebase was ready.
  static Future<void> register() async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
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
