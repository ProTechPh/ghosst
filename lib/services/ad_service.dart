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
/// themselves after every show.
class AdService {
  /// Real rewarded ad unit with SSV (reward item: coins).
  /// Google test unit for debugging without SSV: ca-app-pub-3940256099942544/5224354917
  static const rewardedAdUnitId = AdUnits.rewarded;

  RewardedAd? _ad;
  RewardedInterstitialAd? _ri;
  InterstitialAd? _inter;
  bool _loading = false;
  bool _riLoading = false;
  bool _interLoading = false;

  bool get ready => _ad != null;

  // ---------------------------------------------------------------------
  // Rewarded — watch a video, earn coins (SSV credits server-side).
  // ---------------------------------------------------------------------

  /// Preload an ad; safe to call repeatedly (single-flight).
  Future<void> preload() async {
    if (_ad != null || _loading) return;
    _loading = true;
    try {
      await RewardedAd.load(
        adUnitId: rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _ad?.dispose();
            _ad = ad;
            _loading = false;
          },
          onAdFailedToLoad: (err) {
            _loading = false;
          },
        ),
      );
    } catch (_) {
      _loading = false;
    }
  }

  /// Show a rewarded ad.
  ///
  /// [onEarned] fires when the user is entitled to the reward (coins are
  /// credited server-side by AdMob's SSV callback shortly after).
  /// [onClosed] fires when the ad screen is dismissed.
  Future<void> show({
    required String userId,
    required void Function(RewardItem reward) onEarned,
    required void Function(String error) onError,
    required void Function() onClosed,
  }) async {
    await preload();
    final ad = _ad;
    if (ad == null) {
      onError('Ad not loaded yet. Check your connection and try again.');
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
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        onError('Could not show ad: $error');
        onClosed();
      },
    );

    await ad.show(onUserEarnedReward: (_, reward) => onEarned(reward));

    // Prepare the next one in the background.
    // ignore: unawaited_futures
    preload();
  }

  // ---------------------------------------------------------------------
  // Rewarded interstitial — the second way to earn coins (SSV same as above).
  // ---------------------------------------------------------------------

  Future<void> preloadRewardedInterstitial() async {
    if (_ri != null || _riLoading) return;
    _riLoading = true;
    try {
      await RewardedInterstitialAd.load(
        adUnitId: AdUnits.rewardedInterstitial,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _ri?.dispose();
            _ri = ad;
            _riLoading = false;
          },
          onAdFailedToLoad: (_) {
            _riLoading = false;
          },
        ),
      );
    } catch (_) {
      _riLoading = false;
    }
  }

  /// Show the rewarded interstitial earn option. Same SSV contract as
  /// [show] — the same reward function credits the coins.
  Future<void> showRewardedInterstitial({
    required String userId,
    required void Function(RewardItem reward) onEarned,
    required void Function(String error) onError,
    required void Function() onClosed,
  }) async {
    await preloadRewardedInterstitial();
    final ad = _ri;
    if (ad == null) {
      onError('Ad not loaded yet. Check your connection and try again.');
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
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        onError('Could not show ad: $error');
        onClosed();
      },
    );

    await ad.show(onUserEarnedReward: (_, reward) => onEarned(reward));

    // ignore: unawaited_futures
    preloadRewardedInterstitial();
  }

  // ---------------------------------------------------------------------
  // Interstitial — passive profit, no coins. Fire-and-forget from the shell.
  // ---------------------------------------------------------------------

  Future<void> preloadInterstitial() async {
    if (_inter != null || _interLoading) return;
    _interLoading = true;
    try {
      await InterstitialAd.load(
        adUnitId: AdUnits.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _inter?.dispose();
            _inter = ad;
            _interLoading = false;
          },
          onAdFailedToLoad: (_) {
            _interLoading = false;
          },
        ),
      );
    } catch (_) {
      _interLoading = false;
    }
  }

  /// Show the preloaded interstitial (silently skips + retries when the ad
  /// isn't ready — passive formats must never block the UI).
  Future<void> showInterstitial({void Function()? onClosed}) async {
    await preloadInterstitial();
    final ad = _inter;
    if (ad == null) {
      onClosed?.call();
      return;
    }
    _inter = null; // one-shot

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        onClosed?.call();
        // ignore: unawaited_futures
        preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        onClosed?.call();
        // ignore: unawaited_futures
        preloadInterstitial();
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
            // ignore: unawaited_futures
            ad.show();
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

  void dispose() {
    _ad?.dispose();
    _ad = null;
    _ri?.dispose();
    _ri = null;
    _inter?.dispose();
    _inter = null;
  }
}
