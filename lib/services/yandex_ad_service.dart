import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

import 'ad_service.dart';

/// Direct Yandex fallback used only after the primary Google/Unity request
/// reports no fill. Google mediation remains the primary ad path for every
/// format; Yandex never pre-empts a healthy AdMob load.
class YandexAdService {
  YandexAdService._();

  static final YandexAdService instance = YandexAdService._();

  static const productionRewardedAdUnitId = 'R-M-20209152-1';
  static const demoRewardedAdUnitId = 'demo-rewarded-yandex';

  static const productionBannerAdUnitId = 'R-M-20209152-2';
  static const demoBannerAdUnitId = 'demo-banner-yandex';

  static const productionInterstitialAdUnitId = 'R-M-20209152-4';
  static const demoInterstitialAdUnitId = 'demo-interstitial-yandex';

  static String get rewardedAdUnitId =>
      AdUnits.useTestAds ? demoRewardedAdUnitId : productionRewardedAdUnitId;

  static String get bannerAdUnitId =>
      AdUnits.useTestAds ? demoBannerAdUnitId : productionBannerAdUnitId;

  static String get interstitialAdUnitId => AdUnits.useTestAds
      ? demoInterstitialAdUnitId
      : productionInterstitialAdUnitId;

  RewardedAdLoader? _loader;
  RewardedAd? _rewardedAd;
  Completer<bool>? _loadCompleter;
  Future<void>? _initialization;
  DateTime? _loadedAt;
  bool _initialized = false;
  bool _showing = false;

  InterstitialAdLoader? _interstitialLoader;
  InterstitialAd? _interstitialAd;
  Completer<InterstitialAd?>? _interstitialLoadCompleter;
  DateTime? _interstitialLoadedAt;
  bool _interstitialShowing = false;

  bool get ready => _rewardedAd != null && !_isExpired;
  bool get isShowing => _showing;

  /// True while any Yandex fullscreen ad owns the screen, so callers can
  /// keep AdMob and Yandex from stacking on top of each other.
  bool get isShowingFullscreen => _showing || _interstitialShowing;

  bool get interstitialReady =>
      _interstitialAd != null && !_isInterstitialExpired;

  bool get _isInterstitialExpired =>
      _interstitialLoadedAt != null &&
      DateTime.now().difference(_interstitialLoadedAt!) >=
          const Duration(hours: 4);

  bool get _isExpired =>
      _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) >= const Duration(hours: 4);

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    try {
      await YandexAds.initialize();
      _initialized = true;
      debugPrint(
        '[YandexAds] Initialized (${AdUnits.useTestAds ? 'demo' : 'production'} unit)',
      );
    } finally {
      _initialization = null;
    }
  }

  /// Loads at most one rewarded ad at a time and reuses a fresh cached ad.
  Future<bool> preload({Duration timeout = const Duration(seconds: 10)}) async {
    if (!AdService.adsEnabled) return false;
    if (!_initialized) {
      try {
        await initialize();
      } catch (error, stackTrace) {
        debugPrint('[YandexAds] Initialization failed: $error\n$stackTrace');
        return false;
      }
    }

    if (_isExpired) await _destroyRewardedAd();
    if (_rewardedAd != null) return true;
    if (_loadCompleter != null) {
      try {
        return await _loadCompleter!.future.timeout(timeout);
      } on TimeoutException {
        return false;
      }
    }

    final completer = Completer<bool>();
    _loadCompleter = completer;
    try {
      _loader ??= RewardedAdLoader();
      final ad = await _loader!.loadAd(
        adRequest: AdRequest(adUnitId: rewardedAdUnitId),
      );
      _rewardedAd = ad;
      _loadedAt = DateTime.now();
      debugPrint('[YandexAds] Rewarded ad loaded: $rewardedAdUnitId');
      if (!completer.isCompleted) completer.complete(true);
      _loadCompleter = null;
    } catch (error, stackTrace) {
      debugPrint('[YandexAds] Rewarded load exception: $error\n$stackTrace');
      if (!completer.isCompleted) completer.complete(false);
      _loadCompleter = null;
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      debugPrint('[YandexAds] Rewarded load timed out');
      return false;
    }
  }

  Future<void> showRewarded({
    required void Function(Reward reward) onRewarded,
    required void Function(String error) onError,
    required VoidCallback onClosed,
    Duration waitTimeout = const Duration(seconds: 10),
  }) async {
    if (!AdService.adsEnabled) {
      onError('Ads are temporarily unavailable.');
      return;
    }
    if (_showing) {
      onError('Another advertisement is already displaying.');
      return;
    }

    if (!ready && !await preload(timeout: waitTimeout)) {
      onError('No Yandex rewarded ad is available right now.');
      return;
    }

    final ad = _rewardedAd;
    if (ad == null) {
      onError('No Yandex rewarded ad is available right now.');
      return;
    }

    _rewardedAd = null;
    _loadedAt = null;
    _showing = true;
    var rewardDelivered = false;
    var callbacksFinished = false;
    final finished = Completer<void>();

    Future<void> finish({required bool notifyClosed}) async {
      if (callbacksFinished) return;
      callbacksFinished = true;
      _showing = false;
      try {
        await ad.destroy();
      } catch (error) {
        debugPrint('[YandexAds] Rewarded destroy failed: $error');
      }
      if (notifyClosed) onClosed();
      if (!finished.isCompleted) finished.complete();
      unawaited(preload());
    }

    try {
      await ad.setAdEventListener(
        eventListener: RewardedAdEventListener(
          onAdShown: () => debugPrint('[YandexAds] Rewarded ad shown'),
          onAdFailedToShow: (error) {
            debugPrint('[YandexAds] Rewarded show failed: $error');
            onError('Could not play the Yandex ad right now.');
            unawaited(finish(notifyClosed: true));
          },
          onAdDismissed: () {
            debugPrint('[YandexAds] Rewarded ad dismissed');
            unawaited(finish(notifyClosed: true));
          },
          onRewarded: (reward) {
            if (rewardDelivered) return;
            rewardDelivered = true;
            debugPrint(
              '[YandexAds] Reward earned: ${reward.amount} ${reward.type}',
            );
            onRewarded(reward);
          },
          onAdClicked: () => debugPrint('[YandexAds] Rewarded ad clicked'),
          onAdImpression: (data) =>
              debugPrint('[YandexAds] Rewarded impression: $data'),
        ),
      );
      await ad.show();
      await finished.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      debugPrint('[YandexAds] Rewarded dismissal timed out');
      await finish(notifyClosed: true);
    } catch (error, stackTrace) {
      debugPrint('[YandexAds] Rewarded show exception: $error\n$stackTrace');
      onError('Could not play the Yandex ad right now.');
      await finish(notifyClosed: true);
    }
  }

  // ---------------------------------------------------------------------
  // Banner — passive fallback when the AdMob banner reports no fill.
  // ---------------------------------------------------------------------

  /// Primes a Yandex sticky banner for the given logical width.
  ///
  /// The banner is **not** cached here: every screen owns the ad it creates so
  /// the Home shelf and the Store shelf can fall back independently. The
  /// caller MUST mount `AdWidget(bannerAd: ad)` afterwards — the plugin only
  /// issues the network request once its native view is attached, so an ad
  /// that is never mounted never resolves. Observe `ad.loadStateStream` for
  /// `BannerAdLoadStateLoaded` / `BannerAdLoadStateError`, then call
  /// [destroyBanner] when the ad is no longer wanted.
  Future<BannerAd?> prepareBanner({
    required int width,
    String? adUnitId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!AdService.adsEnabled) return null;
    try {
      await initialize();
    } catch (error, stackTrace) {
      debugPrint('[YandexAds] Banner init failed: $error\n$stackTrace');
      return null;
    }

    final unit = adUnitId ?? bannerAdUnitId;
    try {
      final ad = BannerAd(adSize: BannerAdSize.sticky(width: width));
      await ad.load(AdRequest(adUnitId: unit)).timeout(timeout);
      debugPrint('[YandexAds] Banner prepared: $unit');
      return ad;
    } catch (error, stackTrace) {
      debugPrint('[YandexAds] Banner prepare failed: $error\n$stackTrace');
      return null;
    }
  }

  Future<void> destroyBanner(BannerAd ad) async {
    try {
      await ad.destroy();
    } catch (error) {
      debugPrint('[YandexAds] Banner destroy failed: $error');
    }
  }

  // ---------------------------------------------------------------------
  // Interstitial — passive fallback when AdMob has no interstitial ready.
  // ---------------------------------------------------------------------

  Future<InterstitialAd?> preloadInterstitial({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!AdService.adsEnabled) return null;
    try {
      await initialize();
    } catch (error, stackTrace) {
      debugPrint('[YandexAds] Interstitial init failed: $error\n$stackTrace');
      return null;
    }

    if (_isInterstitialExpired) await _destroyInterstitialAd();
    if (_interstitialAd != null) return _interstitialAd;
    if (_interstitialLoadCompleter != null) {
      try {
        return await _interstitialLoadCompleter!.future.timeout(timeout);
      } on TimeoutException {
        return _interstitialAd;
      }
    }

    final completer = Completer<InterstitialAd?>();
    _interstitialLoadCompleter = completer;
    try {
      _interstitialLoader ??= InterstitialAdLoader();
      final ad = await _interstitialLoader!.loadAd(
        adRequest: AdRequest(adUnitId: interstitialAdUnitId),
      );
      _interstitialAd = ad;
      _interstitialLoadedAt = DateTime.now();
      debugPrint('[YandexAds] Interstitial ad loaded: $interstitialAdUnitId');
      if (!completer.isCompleted) completer.complete(ad);
      _interstitialLoadCompleter = null;
    } catch (error, stackTrace) {
      debugPrint(
        '[YandexAds] Interstitial load exception: $error\n$stackTrace',
      );
      if (!completer.isCompleted) completer.complete(null);
      _interstitialLoadCompleter = null;
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      debugPrint('[YandexAds] Interstitial load timed out');
      return _interstitialAd;
    }
  }

  /// Presents the cached Yandex interstitial. Returns `false` without showing
  /// anything when ads are off, another fullscreen ad owns the screen, or no
  /// inventory is available — so callers can stay silent instead of freezing
  /// navigation.
  Future<bool> showInterstitial({
    required VoidCallback onClosed,
    Duration waitTimeout = const Duration(seconds: 4),
  }) async {
    if (!AdService.adsEnabled) return false;
    if (isShowingFullscreen || AdService.instance.isShowingFullScreenAd) {
      return false;
    }

    if (!interstitialReady &&
        await preloadInterstitial(timeout: waitTimeout) == null) {
      debugPrint('[YandexAds] Interstitial not ready; skipping');
      return false;
    }

    final ad = _interstitialAd;
    if (ad == null) return false;

    _interstitialAd = null;
    _interstitialLoadedAt = null;
    _interstitialShowing = true;
    var callbacksFinished = false;
    final finished = Completer<void>();

    Future<void> finish({required bool notifyClosed}) async {
      if (callbacksFinished) return;
      callbacksFinished = true;
      _interstitialShowing = false;
      try {
        await ad.destroy();
      } catch (error) {
        debugPrint('[YandexAds] Interstitial destroy failed: $error');
      }
      if (notifyClosed) onClosed();
      if (!finished.isCompleted) finished.complete();
      unawaited(preloadInterstitial());
    }

    try {
      await ad.setAdEventListener(
        eventListener: InterstitialAdEventListener(
          onAdShown: () => debugPrint('[YandexAds] Interstitial ad shown'),
          onAdFailedToShow: (error) {
            debugPrint('[YandexAds] Interstitial show failed: $error');
            unawaited(finish(notifyClosed: true));
          },
          onAdDismissed: () {
            debugPrint('[YandexAds] Interstitial ad dismissed');
            unawaited(finish(notifyClosed: true));
          },
          onAdClicked: () => debugPrint('[YandexAds] Interstitial ad clicked'),
          onAdImpression: (data) =>
              debugPrint('[YandexAds] Interstitial impression: $data'),
        ),
      );
      await ad.show();
      await finished.future.timeout(const Duration(minutes: 2));
    } on TimeoutException {
      debugPrint('[YandexAds] Interstitial dismissal timed out');
      await finish(notifyClosed: true);
    } catch (error, stackTrace) {
      debugPrint(
        '[YandexAds] Interstitial show exception: $error\n$stackTrace',
      );
      await finish(notifyClosed: true);
    }
    return true;
  }

  Future<void> _destroyInterstitialAd() async {
    final ad = _interstitialAd;
    _interstitialAd = null;
    _interstitialLoadedAt = null;
    if (ad != null) {
      try {
        await ad.destroy();
      } catch (error) {
        debugPrint('[YandexAds] Interstitial destroy failed: $error');
      }
    }
  }

  Future<void> _destroyRewardedAd() async {
    final ad = _rewardedAd;
    _rewardedAd = null;
    _loadedAt = null;
    if (ad != null) await ad.destroy();
  }

  Future<void> dispose() async {
    await _destroyRewardedAd();
    await _destroyInterstitialAd();
    final loader = _loader;
    _loader = null;
    loader?.destroy();
    final interstitialLoader = _interstitialLoader;
    _interstitialLoader = null;
    interstitialLoader?.destroy();
    _initialized = false;
  }
}
