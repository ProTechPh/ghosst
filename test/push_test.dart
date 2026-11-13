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
}
