import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/push.dart';

void main() {
  test('init and permission never throw', () async {
    // No platform channel here, so the SDK call fails softly.
    expect(Push.appId, isNotEmpty);
    await Push.init();
    await Push.requestPermission();
  });

  test('permission is only asked after the launch gates and a session', () {
    expect(Push.shouldAsk(signedIn: false, gatesPassed: true), isFalse);
    expect(Push.shouldAsk(signedIn: true, gatesPassed: false), isFalse);
    expect(Push.shouldAsk(signedIn: true, gatesPassed: true), isTrue);
  });
}
