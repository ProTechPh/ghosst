import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/push.dart';

void main() {
  test('init and permission never throw', () async {
    // No platform channel here, so the SDK call fails softly.
    expect(Push.appId, isNotEmpty);
    await Push.init();
    await Push.requestPermission();
  });

  test('permission is only asked once the splash is done', () {
    expect(Push.canAsk, isFalse); // splash not finished yet
    Push.splashDone = true;
    expect(Push.canAsk, Push.configured);
    Push.splashDone = false;
  });
}
