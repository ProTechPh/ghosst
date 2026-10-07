import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Rewarded ad wrapper: preload + show with SSV options wired to the uid.
class AdService {
  /// Real rewarded ad unit with SSV (reward item: coins).
  /// Google test unit for debugging without SSV: ca-app-pub-3940256099942544/5224354917
  static const rewardedAdUnitId = 'ca-app-pub-7791552060229072/3206073177';

  RewardedAd? _ad;
  bool _loading = false;

  bool get ready => _ad != null;

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

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
