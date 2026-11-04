import 'package:onesignal_flutter/onesignal_flutter.dart';

/// OneSignal broadcast notifications.
///
/// An empty app id (the default, filled only by `--dart-define`) makes this
/// whole file inert, so builds without credentials behave exactly as before.
class Push {
  Push._();

  static const appId = String.fromEnvironment('ONESIGNAL_APP_ID');

  static bool get configured => appId.isNotEmpty;

  /// The dialog belongs after the launch gates and only for a signed-in user.
  static bool shouldAsk({required bool signedIn, required bool gatesPassed}) =>
      signedIn && gatesPassed;

  static Future<void> init() async {
    if (!configured) return;
    try {
      OneSignal.initialize(appId);
    } catch (_) {
      // A push SDK that cannot start must never block the app.
    }
  }

  static Future<void> requestPermission() async {
    if (!configured) return;
    try {
      OneSignal.Notifications.requestPermission(true);
    } catch (_) {}
  }
}
