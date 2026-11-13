import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/push.dart';

void main() {
  test('init and permission never throw', () async {
    // No Firebase app in a test: both calls must fail softly.
    await Push.init();
    await Push.requestPermission();
  });

  test('permission is only asked once the splash is done', () {
    expect(Push.canAsk, isFalse);
    Push.splashDone = true;
    expect(Push.canAsk, isTrue);
    Push.splashDone = false;
  });

  test('a foreground message asks the shell to refresh', () {
    // Android does not display FCM notification messages while the app is in
    // front; the shell reloads announcements instead of a tray notification.
    final before = Push.foreground.value;
    Push.handleForeground(
      const RemoteMessage(
        notification: RemoteNotification(title: 'New stock', body: 'Back'),
      ),
    );
    expect(Push.foreground.value, before + 1);
  });
}
