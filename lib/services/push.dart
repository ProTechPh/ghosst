import 'package:onesignal_flutter/onesignal_flutter.dart';

/// OneSignal broadcast notifications.
///
/// An empty app id (the default, filled only by `--dart-define`) makes this
/// whole file inert, so builds without credentials behave exactly as before.
class Push {
  Push._();

  // Public app id — safe in the repo. `--dart-define` still wins if set.
  static const appId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
    defaultValue: 'cb151c2b-07e6-4240-88fe-36905ff390a8',
  );

  static bool get configured => appId.isNotEmpty;

  static Future<void> init() async {
    if (!configured) return;
    try {
      await OneSignal.initialize(appId);
    } catch (_) {
      // A push SDK that cannot start must never block the app.
    }
  }

  /// Set once the splash (and the launch gates behind it) are done. The
  /// permission dialog must never sit over those screens.
  static bool splashDone = false;

  static bool get canAsk => configured && splashDone;

  /// Askable only after the splash: see [splashDone].
  static Future<void> requestPermission() async {
    if (!canAsk) return;
    try {
      await OneSignal.Notifications.requestPermission(true);
    } catch (_) {}
  }
}
