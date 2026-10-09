import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Every ad unit the app uses, in one place.
///
/// AdMob app ID: `ca-app-pub-7791552060229072~1855578469` (already wired in
/// `android/app/src/main/AndroidManifest.xml`). All six units are real —
/// SSV is enabled on both rewarded formats (coins credited by the claim
/// function); passive formats need no SSV.
class AdUnits {
  AdUnits._();

  // Real units (AdMob console, app Ghosst).
  static const rewarded = 'ca-app-pub-7791552060229072/3206073177';
  static const rewardedInterstitial = 'ca-app-pub-7791552060229072/8242333892';
  static const banner = 'ca-app-pub-7791552060229072/3870834884';
  static const interstitial = 'ca-app-pub-7791552060229072/9227103348';
  static const appOpen = 'ca-app-pub-7791552060229072/5447640437';
  static const native = 'ca-app-pub-7791552060229072/4134558763';
}

/// Ad wrapper covering all six AdMob formats:
///
/// * **Rewarded** & **Rewarded interstitial** — earn coins (SSV → function).
/// * **Interstitial**, **App open**, **Banner**, **Native** — passive
///   revenue only; they never touch the coin balance.
///
/// Full-screen formats preload in the background (single-flight) and reload
/// themselves after every show. Uses a singleton cache so tab changes or
/// multiple screen builds never discard matched ads.
class AdService {
  AdService._internal();
  static final AdService instance = AdService._internal();
  factory AdService() => instance;

  /// Set only after UMP allows ad requests and Mobile Ads initializes.
  static bool adsEnabled = false;

  /// Real rewarded ad unit with SSV (reward item: coins).
  static const rewardedAdUnitId = AdUnits.rewarded;

  RewardedAd? _ad;
  RewardedInterstitialAd? _ri;
  InterstitialAd? _inter;

  Completer<RewardedAd?>? _rewardedCompleter;
  Completer<RewardedInterstitialAd?>? _riCompleter;
  Completer<InterstitialAd?>? _interCompleter;

  DateTime? _lastRewardedFailTime;
  DateTime? _lastRiFailTime;
  int? _lastRewardedErrorCode;
  int? _lastRiErrorCode;

  bool get ready => _ad != null;
  bool get riReady => _ri != null;

  static String _userFriendlyError(int? code) {
    switch (code) {
      case 3: // ERROR_CODE_NO_FILL
        return 'No ads available right now. Please try again in a few moments.';
      case 2: // ERROR_CODE_NETWORK_ERROR
        return 'Network connection issue. Please check your internet and try again.';
      case 1: // ERROR_CODE_INVALID_REQUEST
        return 'Ad servers are busy. Please wait a moment and try again.';
      case 0: // ERROR_CODE_INTERNAL_ERROR
      default:
        return 'Ad is temporarily unavailable. Please try again shortly.';
    }
  }

  // ---------------------------------------------------------------------
  // Rewarded — watch a video, earn coins (SSV credits server-side).
  // ---------------------------------------------------------------------

  /// Preload an ad; waits for an in-flight load if already running.
  Future<RewardedAd?> preload({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!adsEnabled) return null;
    if (_ad != null) return _ad;

    // Rate-limit backoff: if Google just returned No Fill, wait at least 15s
    // before sending another request to avoid Code 1 (Too many failed requests).
    if (_lastRewardedFailTime != null &&
        DateTime.now().difference(_lastRewardedFailTime!).inSeconds < 15) {
      debugPrint('[AdService] Skipping preload: failure backoff active');
      return null;
    }

    if (_rewardedCompleter != null) {
      try {
        return await _rewardedCompleter!.future.timeout(timeout);
      } catch (_) {
        return _ad;
      }
    }

    final completer = Completer<RewardedAd?>();
    _rewardedCompleter = completer;

    try {
      debugPrint('[AdService] Preloading RewardedAd...');
      await RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            debugPrint('[AdService] RewardedAd loaded successfully');
            _lastRewardedFailTime = null;
            _lastRewardedErrorCode = null;
            _ad?.dispose();
            _ad = ad;
            _rewardedCompleter = null;
            if (!completer.isCompleted) completer.complete(ad);
          },
          onAdFailedToLoad: (err) {
            _lastRewardedFailTime = DateTime.now();
            _lastRewardedErrorCode = err.code;
            debugPrint(
              '[AdService] RewardedAd failed to load: AdMob code ${err.code}: ${err.message}',
            );
            _rewardedCompleter = null;
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (e) {
      _lastRewardedFailTime = DateTime.now();
      debugPrint('[AdService] RewardedAd load exception: $e');
      _rewardedCompleter = null;
      if (!completer.isCompleted) completer.complete(null);
    }

    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      debugPrint(
        '[AdService] RewardedAd wait timed out (${timeout.inSeconds}s)',
      );
      return _ad;
    }
  }

  /// Show a rewarded ad. Waits up to [waitTimeout] if the ad is currently loading.
  Future<void> show({
    required String userId,
    required void Function(RewardItem reward) onEarned,
    required void Function(String error) onError,
    required void Function() onClosed,
    Duration waitTimeout = const Duration(seconds: 8),
  }) async {
    if (!adsEnabled) {
      onError('Ads are unavailable until privacy choices are completed.');
      return;
    }
    final ad = _ad ?? await preload(timeout: waitTimeout);

    if (ad == null) {
      final hint = _lastRewardedErrorCode != null
          ? _userFriendlyError(_lastRewardedErrorCode)
          : 'Ad is still loading. Please wait a moment and tap again.';
      onError(hint);
      return;
    }
    _ad = null; // one-shot

    // SSV callback receives this as `user_id` so the function can credit us.
    await ad.setServerSideOptions(
      ServerSideVerificationOptions(userId: userId),
    );

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        onClosed();
        // Prepare the next one in the background.
        unawaited(preload());
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        debugPrint('[AdService] Show error: ${error.message}');
        onError('Could not play video right now. Please try again.');
        onClosed();
        unawaited(preload());
      },
    );

    await ad.show(onUserEarnedReward: (_, reward) => onEarned(reward));
  }

  // ---------------------------------------------------------------------
  // Rewarded interstitial — the second way to earn coins (SSV same as above).
  // ---------------------------------------------------------------------

  Future<RewardedInterstitialAd?> preloadRewardedInterstitial({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!adsEnabled) return null;
    if (_ri != null) return _ri;

    if (_lastRiFailTime != null &&
        DateTime.now().difference(_lastRiFailTime!).inSeconds < 15) {
      debugPrint('[AdService] Skipping RI preload: failure backoff active');
      return null;
    }

    if (_riCompleter != null) {
      try {
        return await _riCompleter!.future.timeout(timeout);
      } catch (_) {
        return _ri;
      }
    }

    final completer = Completer<RewardedInterstitialAd?>();
    _riCompleter = completer;

    try {
      debugPrint('[AdService] Preloading RewardedInterstitialAd...');
      await RewardedInterstitialAd.load(
        adUnitId: AdUnits.rewardedInterstitial,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            debugPrint(
              '[AdService] RewardedInterstitialAd loaded successfully',
            );
            _lastRiFailTime = null;
            _lastRiErrorCode = null;
            _ri?.dispose();
            _ri = ad;
            _riCompleter = null;
            if (!completer.isCompleted) completer.complete(ad);
          },
          onAdFailedToLoad: (err) {
            _lastRiFailTime = DateTime.now();
            _lastRiErrorCode = err.code;
            debugPrint(
              '[AdService] RewardedInterstitialAd failed: AdMob code ${err.code}: ${err.message}',
            );
            _riCompleter = null;
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (e) {
      _lastRiFailTime = DateTime.now();
      debugPrint('[AdService] RewardedInterstitialAd load exception: $e');
      _riCompleter = null;
      if (!completer.isCompleted) completer.complete(null);
    }

    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      debugPrint('[AdService] RewardedInterstitialAd wait timed out');
      return _ri;
    }
  }

  /// Show the rewarded interstitial earn option. Same SSV contract as
  /// [show] — the same reward function credits the coins.
  Future<void> showRewardedInterstitial({
    required String userId,
    required void Function(RewardItem reward) onEarned,
    required void Function(String error) onError,
    required void Function() onClosed,
    Duration waitTimeout = const Duration(seconds: 8),
  }) async {
    final ad = _ri ?? await preloadRewardedInterstitial(timeout: waitTimeout);

    if (ad == null) {
      final hint = _lastRiErrorCode != null
          ? _userFriendlyError(_lastRiErrorCode)
          : 'Ad is still loading. Please wait a moment and tap again.';
      onError(hint);
      return;
    }
    _ri = null; // one-shot

    await ad.setServerSideOptions(
      ServerSideVerificationOptions(userId: userId),
    );

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        onClosed();
        unawaited(preloadRewardedInterstitial());
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        debugPrint('[AdService] RI Show error: ${error.message}');
        onError('Could not play video right now. Please try again.');
        onClosed();
        unawaited(preloadRewardedInterstitial());
      },
    );

    await ad.show(onUserEarnedReward: (_, reward) => onEarned(reward));
  }

  // ---------------------------------------------------------------------
  // Interstitial — passive profit, no coins. Fire-and-forget from the shell.
  // ---------------------------------------------------------------------

  Future<InterstitialAd?> preloadInterstitial({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!adsEnabled) return null;
    if (_inter != null) return _inter;

    if (_interCompleter != null) {
      try {
        return await _interCompleter!.future.timeout(timeout);
      } catch (_) {
        return _inter;
      }
    }

    final completer = Completer<InterstitialAd?>();
    _interCompleter = completer;

    try {
      await InterstitialAd.load(
        adUnitId: AdUnits.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _inter?.dispose();
            _inter = ad;
            _interCompleter = null;
            if (!completer.isCompleted) completer.complete(ad);
          },
          onAdFailedToLoad: (err) {
            debugPrint('[AdService] Interstitial failed: ${err.message}');
            _interCompleter = null;
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (_) {
      _interCompleter = null;
      if (!completer.isCompleted) completer.complete(null);
    }

    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      return _inter;
    }
  }

  /// Show the preloaded interstitial (silently skips + retries when the ad
  /// isn't ready — passive formats must never block the UI).
  Future<void> showInterstitial({void Function()? onClosed}) async {
    final ad = _inter ?? await preloadInterstitial();
    if (ad == null) {
      onClosed?.call();
      return;
    }
    _inter = null; // one-shot

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        onClosed?.call();
        unawaited(preloadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        onClosed?.call();
        unawaited(preloadInterstitial());
      },
    );

    await ad.show();
  }

  // ---------------------------------------------------------------------
  // App open — passive profit on cold start, no coins.
  // ---------------------------------------------------------------------

  /// Load + show an app-open ad once (e.g. right after the splash).
  /// Failures are silent — this format must never interrupt the UX.
  Future<void> showAppOpen({void Function()? onClosed}) async {
    if (!adsEnabled) {
      onClosed?.call();
      return;
    }
    try {
      await AppOpenAd.load(
        adUnitId: AdUnits.appOpen,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (a) {
                a.dispose();
                onClosed?.call();
              },
              onAdFailedToShowFullScreenContent: (a, error) {
                a.dispose();
                onClosed?.call();
              },
            );
            unawaited(ad.show());
          },
          onAdFailedToLoad: (_) {
            onClosed?.call();
          },
        ),
      );
    } catch (_) {
      onClosed?.call();
    }
  }

  /// App-wide cleanup (only when the whole application shuts down).
  void dispose() {
    _ad?.dispose();
    _ad = null;
    _ri?.dispose();
    _ri = null;
    _inter?.dispose();
    _inter = null;
  }
}
