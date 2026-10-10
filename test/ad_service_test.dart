import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/ad_service.dart';
import 'package:ghosst/services/yandex_ad_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdUnits Configuration & Separation', () {
    test('production and test ad unit IDs are configured and distinct', () {
      expect(AdUnits.prodRewarded, isNotEmpty);
      expect(AdUnits.prodRewardedInterstitial, isNotEmpty);
      expect(AdUnits.prodBanner, isNotEmpty);
      expect(AdUnits.prodInterstitial, isNotEmpty);
      expect(AdUnits.prodAppOpen, isNotEmpty);
      expect(AdUnits.prodNative, isNotEmpty);

      expect(AdUnits.testRewarded, isNotEmpty);
      expect(AdUnits.testRewardedInterstitial, isNotEmpty);
      expect(AdUnits.testBanner, isNotEmpty);
      expect(AdUnits.testInterstitial, isNotEmpty);
      expect(AdUnits.testAppOpen, isNotEmpty);
      expect(AdUnits.testNative, isNotEmpty);

      // Verify separation between test and prod
      expect(AdUnits.testRewarded, isNot(equals(AdUnits.prodRewarded)));
      expect(
        AdUnits.testRewardedInterstitial,
        isNot(equals(AdUnits.prodRewardedInterstitial)),
      );
      expect(AdUnits.testBanner, isNot(equals(AdUnits.prodBanner)));
      expect(AdUnits.testInterstitial, isNot(equals(AdUnits.prodInterstitial)));
      expect(AdUnits.testAppOpen, isNot(equals(AdUnits.prodAppOpen)));
      expect(AdUnits.testNative, isNot(equals(AdUnits.prodNative)));
    });

    test('switches dynamically between test and production ad unit IDs', () {
      AdUnits.useTestAds = true;
      expect(AdUnits.rewarded, equals(AdUnits.testRewarded));
      expect(
        AdUnits.rewardedInterstitial,
        equals(AdUnits.testRewardedInterstitial),
      );
      expect(AdUnits.banner, equals(AdUnits.testBanner));
      expect(AdUnits.interstitial, equals(AdUnits.testInterstitial));
      expect(AdUnits.appOpen, equals(AdUnits.testAppOpen));
      expect(AdUnits.native, equals(AdUnits.testNative));

      AdUnits.useTestAds = false;
      expect(AdUnits.rewarded, equals(AdUnits.prodRewarded));
      expect(
        AdUnits.rewardedInterstitial,
        equals(AdUnits.prodRewardedInterstitial),
      );
      expect(AdUnits.banner, equals(AdUnits.prodBanner));
      expect(AdUnits.interstitial, equals(AdUnits.prodInterstitial));
      expect(AdUnits.appOpen, equals(AdUnits.prodAppOpen));
      expect(AdUnits.native, equals(AdUnits.prodNative));

      // Reset
      AdUnits.useTestAds = true;
    });

    test('does not force production devices into AdMob test mode', () {
      expect(AdUnits.testDeviceIds, isEmpty);
    });

    test('Yandex rewarded switches between demo and production units', () {
      AdUnits.useTestAds = true;
      expect(
        YandexAdService.rewardedAdUnitId,
        YandexAdService.demoRewardedAdUnitId,
      );

      AdUnits.useTestAds = false;
      expect(
        YandexAdService.rewardedAdUnitId,
        YandexAdService.productionRewardedAdUnitId,
      );
      expect(YandexAdService.productionRewardedAdUnitId, 'R-M-20209152-1');

      AdUnits.useTestAds = true;
    });

    test(
      'Yandex banner and interstitial switch between demo and production',
      () {
        AdUnits.useTestAds = true;
        expect(
          YandexAdService.bannerAdUnitId,
          YandexAdService.demoBannerAdUnitId,
        );
        expect(
          YandexAdService.interstitialAdUnitId,
          YandexAdService.demoInterstitialAdUnitId,
        );

        AdUnits.useTestAds = false;
        expect(
          YandexAdService.bannerAdUnitId,
          YandexAdService.productionBannerAdUnitId,
        );
        expect(
          YandexAdService.interstitialAdUnitId,
          YandexAdService.productionInterstitialAdUnitId,
        );
        expect(YandexAdService.productionBannerAdUnitId, 'R-M-20209152-2');
        expect(
          YandexAdService.productionInterstitialAdUnitId,
          'R-M-20209152-4',
        );

        // Each placement must stay on its own ad unit — reusing one unit for
        // every format makes reporting and house-cut debugging impossible.
        expect({
          YandexAdService.productionRewardedAdUnitId,
          YandexAdService.productionBannerAdUnitId,
          YandexAdService.productionInterstitialAdUnitId,
        }, hasLength(3));

        AdUnits.useTestAds = true;
      },
    );
  });

  group('AdService State & Error Mapping', () {
    test('maps AdMob error codes to user-friendly messages', () {
      expect(
        AdService.userFriendlyError(3),
        contains('No ads available right now'),
      );
      expect(
        AdService.userFriendlyError(2),
        contains('Network connection issue'),
      );
      expect(AdService.userFriendlyError(1), contains('Ad servers are busy'));
      expect(
        AdService.userFriendlyError(0),
        contains('Ad is temporarily unavailable'),
      );
      expect(
        AdService.userFriendlyError(999),
        contains('Ad is temporarily unavailable'),
      );
      expect(
        AdService.userFriendlyError(null),
        contains('Ad is temporarily unavailable'),
      );
    });

    test('maintains singleton instance and reactive adsEnabledNotifier', () {
      final a = AdService();
      final b = AdService.instance;
      expect(identical(a, b), isTrue);

      var notified = false;
      void listener() => notified = true;

      AdService.instance.adsEnabledNotifier.addListener(listener);
      AdService.adsEnabled = false;
      expect(AdService.adsEnabled, isFalse);

      AdService.adsEnabled = true;
      expect(AdService.adsEnabled, isTrue);
      expect(notified, isTrue);

      AdService.instance.adsEnabledNotifier.removeListener(listener);
    });

    test('initial state defaults to idle and not ready without crashing', () {
      final service = AdService.instance;
      service.dispose();

      expect(service.ready, isFalse);
      expect(service.riReady, isFalse);
      expect(service.interReady, isFalse);
      expect(service.appOpenReady, isFalse);
      expect(service.isShowingFullScreenAd, isFalse);

      expect(service.rewardedState, equals(AdState.idle));
      expect(service.riState, equals(AdState.idle));
      expect(service.interState, equals(AdState.idle));
      expect(service.appOpenState, equals(AdState.idle));
    });

    test(
      'show calls reject when adsEnabled is false without unhandled exceptions',
      () async {
        final service = AdService.instance;
        AdService.adsEnabled = false;

        String? errorReceived;
        await service.show(
          userId: 'test_user_123',
          onEarned: (_) {},
          onError: (err) => errorReceived = err,
          onClosed: () {},
        );

        expect(errorReceived, contains('temporarily unavailable'));
      },
    );

    test('showRewardedInterstitial rejects when adsEnabled is false', () async {
      final service = AdService.instance;
      AdService.adsEnabled = false;

      String? errorReceived;
      await service.showRewardedInterstitial(
        userId: 'test_user_123',
        onEarned: (_) {},
        onError: (err) => errorReceived = err,
        onClosed: () {},
      );

      expect(errorReceived, contains('temporarily unavailable'));
    });

    test('rewarded fallback rejects safely when ads are disabled', () async {
      final service = AdService.instance;
      AdService.adsEnabled = false;

      String? errorReceived;
      await service.showRewardedWithFallback(
        userId: 'test_user_123',
        onEarned: (_) {},
        onError: (err) => errorReceived = err,
        onClosed: () {},
      );

      expect(errorReceived, contains('temporarily unavailable'));
    });
  });

  group('AdMob Mediation & Unity Ads Diagnostics', () {
    test('reports mediation uninitialized before MobileAds.initialize', () {
      final service = AdService.instance;
      expect(service.initializationStatus, isNull);
      expect(service.adapterStatuses, isEmpty);
      expect(service.isUnityAdapterReady, isFalse);
      expect(
        service.mediationDiagnostics,
        contains('Mediation not initialized'),
      );
    });

    test(
      'correctly diagnoses and reports ready Unity Ads mediation adapter',
      () {
        final service = AdService.instance;
        final status = InitializationStatus({
          'com.google.android.gms.ads.MobileAds': AdapterStatus(
            AdapterInitializationState.ready,
            'Google Mobile Ads SDK is ready.',
            0.05,
          ),
          'com.google.ads.mediation.unity.UnityMediationAdapter': AdapterStatus(
            AdapterInitializationState.ready,
            'Unity Ads SDK initialized successfully.',
            0.12,
          ),
        });

        service.recordInitializationStatus(status);

        expect(service.initializationStatus, isNotNull);
        expect(service.adapterStatuses.length, equals(2));
        expect(service.isUnityAdapterReady, isTrue);
        expect(service.mediationDiagnostics, contains('Unity Ads Adapter'));
        expect(
          service.mediationDiagnostics,
          contains('UnityMediationAdapter: ready'),
        );
      },
    );

    test('flags when Unity Ads mediation adapter is notReady or missing', () {
      final service = AdService.instance;
      final status = InitializationStatus({
        'com.google.android.gms.ads.MobileAds': AdapterStatus(
          AdapterInitializationState.ready,
          'Google Mobile Ads SDK is ready.',
          0.05,
        ),
        'com.google.ads.mediation.unity.UnityMediationAdapter': AdapterStatus(
          AdapterInitializationState.notReady,
          'Unity Ads initialization in progress.',
          0.0,
        ),
      });

      service.recordInitializationStatus(status);

      expect(service.isUnityAdapterReady, isFalse);
      expect(
        service.mediationDiagnostics,
        contains('UnityMediationAdapter: notReady'),
      );
    });
  });
}
