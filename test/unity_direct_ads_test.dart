import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/unity_direct_ads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    UnityDirectAds.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UnityDirectAds.channel, null);
  });

  test('defaults to disabled', () {
    expect(UnityDirectAds.enabled, isFalse);
  });

  test('classifies only AdMob availability errors as fallback candidates', () {
    expect(
      UnityDirectAds.isAdMobUnavailable('No ads available right now.'),
      isTrue,
    );
    expect(
      UnityDirectAds.isAdMobUnavailable('Network connection issue.'),
      isTrue,
    );
    expect(
      UnityDirectAds.isAdMobUnavailable('Could not play video right now.'),
      isTrue,
    );
    expect(
      UnityDirectAds.isAdMobUnavailable(
        'Another advertisement is already displaying.',
      ),
      isFalse,
    );
  });

  test('requires the AdMob consent gate and an availability error', () {
    UnityDirectAds.debugEnabled = true;
    expect(
      UnityDirectAds.shouldFallback(
        adsEnabled: false,
        error: 'No ads available right now.',
      ),
      isFalse,
    );
    expect(
      UnityDirectAds.shouldFallback(
        adsEnabled: true,
        error: 'Another advertisement is already displaying.',
      ),
      isFalse,
    );
    expect(
      UnityDirectAds.shouldFallback(
        adsEnabled: true,
        error: 'No ads available right now.',
      ),
      isTrue,
    );
  });

  test('returns false without touching the channel when disabled', () async {
    final result = await UnityDirectAds.instance.showRewarded(
      userId: 'u1',
      onCompleted: () {},
      onClosed: () {},
      onError: (_) {},
    );
    expect(result, isFalse);
  });

  test('runs initialize, load and show when enabled', () async {
    UnityDirectAds.debugEnabled = true;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UnityDirectAds.channel, (call) async {
      calls.add(call.method);
      return true;
    });

    final shown = await UnityDirectAds.instance.showRewarded(
      userId: 'u1',
      onCompleted: () {},
      onClosed: () {},
      onError: (_) {},
    );

    expect(shown, isTrue);
    expect(calls, ['initialize', 'load', 'show']);
  });

  test('completes and clears the persisted Unity server id', () async {
    UnityDirectAds.debugEnabled = true;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UnityDirectAds.channel, (call) async {
      calls.add(call.method);
      return true;
    });

    var completed = false;
    final shown = await UnityDirectAds.instance.showRewarded(
      userId: 'u1',
      onCompleted: () => completed = true,
      onClosed: () {},
      onError: (_) {},
    );
    expect(shown, isTrue);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      UnityDirectAds.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('event', {'type': 'completed', 'message': ''}),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(completed, isTrue);
    expect(calls, contains('clearServerId'));
  });
}
