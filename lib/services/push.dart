import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  /// not display FCM `notification` messages there, so [handleForeground]
  /// posts the tray notification itself and the shell listens here to reload
  /// the announcement banner.
  static final ValueNotifier<int> foreground = ValueNotifier<int>(0);

  /// MainActivity posts the tray notification for foreground messages; the
  /// plugin-free channel keeps the app free of a notification dependency.
  static const MethodChannel _notify =
      MethodChannel('com.astrixtech.ghosst/notify');

  static void handleForeground(RemoteMessage message) {
    foreground.value++;
    final notification = message.notification;
    final title = notification?.title ?? '';
    final body = notification?.body ?? '';
    if (title.isEmpty && body.isEmpty) return;
    _notify
        .invokeMethod<void>('show', {'title': title, 'body': body})
        .catchError((_) {});
  }

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
