import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/push.dart';

void main() {
  test('unconfigured build is inert and never throws', () async {
    // No --dart-define in tests, so there is no app id and no platform channel.
    expect(Push.configured, isFalse);
    await Push.init();
    await Push.requestPermission();
  });
}
