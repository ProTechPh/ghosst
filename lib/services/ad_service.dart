import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Every ad unit the app uses, in one place.
///
/// AdMob app ID: `ca-app-pub-7791552060229072~1855578469` (configured in
/// `android/app/src/main/AndroidManifest.xml`).
///
/// In debug builds ([kDebugMode]), Google's official sample test unit IDs are
/// used by default to protect the publisher account from invalid traffic flags.
/// In release builds, real production unit IDs are used.
class AdUnits {
  AdUnits._();

  // Production units (AdMob console, app Ghosst).
  static const prodRewarded = 'ca-app-pub-7791552060229072/3206073177';
  static const prodRewardedInterstitial =
      'ca-app-pub-7791552060229072/8242333892';
  static const prodBanner = 'ca-app-pub-7791552060229072/3870834884';
  static const prodInterstitial = 'ca-app-pub-7791552060229072/9227103348';
  static const prodAppOpen = 'ca-app-pub-7791552060229072/5447640437';
  static const prodNative = 'ca-app-pub-7791552060229072/4134558763';

  // Google official test ad unit IDs (Android).
  // https://developers.google.com/admob/android/test-ads
  static const testRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const testRewardedInterstitial =
      'ca-app-pub-3940256099942544/5354046379';
  static const testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const testAppOpen = 'ca-app-pub-3940256099942544/9257395921';
  static const testNative = 'ca-app-pub-3940256099942544/2247696110';

  /// No production device is registered as an AdMob test device. Builds using
  /// [useTestAds] remain safe because they use Google's official sample units.
  static const List<String> testDeviceIds = [];

  /// Debug builds use Google's guaranteed-fill sample inventory. Release builds
  /// use the real Ghosst units unless explicitly overridden for release QA with
  /// `--dart-define=USE_TEST_ADS=true`.
  static bool useTestAds = const bool.fromEnvironment(
    'USE_TEST_ADS',
    defaultValue: kDebugMode,
  );

  static String get rewarded => useTestAds ? testRewarded : prodRewarded;
  static String get rewardedInterstitial =>
      useTestAds ? testRewardedInterstitial : prodRewardedInterstitial;
  static String get banner => useTestAds ? testBanner : prodBanner;
  static String get interstitial =>
      useTestAds ? testInterstitial : prodInterstitial;
  static String get appOpen => useTestAds ? testAppOpen : prodAppOpen;
  static String get native => useTestAds ? testNative : prodNative;
}

/// Lifecycle states for an individual advertisement slot.
enum AdState { idle, loading, loaded, showing, failed }

/// Centralized advertisement manager covering all six AdMob formats:
///
/// * **Rewarded** & **Rewarded interstitial** — earn coins (SSV → function).
/// * **Interstitial**, **App open**, **Banner**, **Native** — passive
///   revenue only; they never touch the coin balance.
///
/// Enforces:
/// - Explicit ad state management (idle, loading, loaded, showing, failed).
/// - Concurrency mutex preventing multiple full-screen ads from opening at once.
/// - Duplicate reward prevention on rewarded video completion.
/// - Single-flight preloading with timeout guards.
/// - 4-hour TTL caching for AdMob full-screen inventory.
/// - Bounded exponential backoff with jitter on load failures.
/// - Structured diagnostic logging of error codes, domains, and response info.
/// - Safe disposal without tearing down singleton state across screen builds.
class AdService {
  AdService._internal();
  static final AdService instance = AdService._internal();
  factory AdService() => instance;

  /// Reactive notifier for when ads are permitted by consent and initialized.
  final ValueNotifier<bool> adsEnabledNotifier = ValueNotifier<bool>(false);

  /// Backwards-compatible static property for `AdService.adsEnabled`.
  static bool get adsEnabled => instance.adsEnabledNotifier.value;
  static set adsEnabled(bool v) => instance.adsEnabledNotifier.value = v;

  /// Real rewarded ad unit with SSV (reward item: coins).
  static String get rewardedAdUnitId => AdUnits.rewarded;

  // Active full-screen ad instances.
  RewardedAd? _ad;
  RewardedInterstitialAd? _ri;
  InterstitialAd? _inter;
  AppOpenAd? _appOpen;

  // States
  AdState _adState = AdState.idle;
  AdState _riState = AdState.idle;
  AdState _interState = AdState.idle;
  AdState _appOpenState = AdState.idle;

  // Timestamps
  DateTime? _adLoadedTime;
  DateTime? _riLoadedTime;
  DateTime? _interLoadedTime;
  DateTime? _appOpenLoadedTime;

  // In-flight single-flight completers.
  Completer<RewardedAd?>? _rewardedCompleter;
  Completer<RewardedInterstitialAd?>? _riCompleter;
  Completer<InterstitialAd?>? _interCompleter;
  Completer<AppOpenAd?>? _appOpenCompleter;

  // Failure tracking & backoff
  DateTime? _lastRewardedFailTime;
  DateTime? _lastRiFailTime;
  DateTime? _lastInterFailTime;
  DateTime? _lastAppOpenFailTime;

  int? _lastRewardedErrorCode;
  int? _lastRiErrorCode;
  int? _lastInterErrorCode;
  int? _lastAppOpenErrorCode;

  int _rewardedRetryAttempts = 0;
  int _riRetryAttempts = 0;
  int _interRetryAttempts = 0;
  int _appOpenRetryAttempts = 0;

  Duration? _rewardedRetryDelay;
  Duration? _riRetryDelay;
  Duration? _interRetryDelay;
  Duration? _appOpenRetryDelay;

  // Global full-screen presentation mutex.
  bool _isShowingFullScreenAd = false;
  bool get isShowingFullScreenAd => _isShowingFullScreenAd;

  // Readiness getters
  bool get ready => _ad != null && !_isAdExpired(_adLoadedTime);
  bool get riReady => _ri != null && !_isAdExpired(_riLoadedTime);
  bool get interReady => _inter != null && !_isAdExpired(_interLoadedTime);
  bool get appOpenReady =>
      _appOpen != null && !_isAdExpired(_appOpenLoadedTime);

  AdState get rewardedState => _adState;
  AdState get riState => _riState;
  AdState get interState => _interState;
  AdState get appOpenState => _appOpenState;

  int? get lastRewardedErrorCode => _lastRewardedErrorCode;
  int? get lastRiErrorCode => _lastRiErrorCode;
  int? get lastInterErrorCode => _lastInterErrorCode;
  int? get lastAppOpenErrorCode => _lastAppOpenErrorCode;

  // Mediation adapter initialization tracking
  InitializationStatus? _initializationStatus;
  InitializationStatus? get initializationStatus => _initializationStatus;
  Map<String, AdapterStatus> get adapterStatuses =>
      _initializationStatus?.adapterStatuses ?? const {};

  /// Checks whether Unity Ads mediation adapter is registered and ready.
  bool get isUnityAdapterReady {
    final statuses = adapterStatuses;
    for (final entry in statuses.entries) {
      if (entry.key.toLowerCase().contains('unity')) {
        return entry.value.state == AdapterInitializationState.ready;
      }
    }
    return false;
  }

  /// Returns a diagnostic report string of all mediation adapter statuses.
  String get mediationDiagnostics {
    if (_initializationStatus == null) {
      return 'Mediation not initialized (MobileAds.initialize pending)';
    }
    final statuses = adapterStatuses;
    if (statuses.isEmpty) {
      return 'Mediation initialized: No adapters reported in initializationStatus.';
    }
    final buffer = StringBuffer('Mediation Adapter Statuses:\n');
    for (final entry in statuses.entries) {
      final name = entry.key;
      final st = entry.value;
      final isUnity = name.toLowerCase().contains('unity');
      buffer.writeln(
        '  - $name: ${st.state.name} (${st.latency}s) "${st.description}"'
        '${isUnity ? " [Unity Ads Adapter]" : ""}',
      );
    }
    return buffer.toString().trim();
  }

  /// Centralized initialization entry point that configures test devices,
  /// initializes the Mobile Ads SDK with mediation adapters, records adapter
  /// statuses, logs diagnostics, and enables ad preloading.
  Future<InitializationStatus> initialize() async {
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: AdUnits.testDeviceIds),
    );
    final status = await MobileAds.instance.initialize();
    _initializationStatus = status;
    adsEnabledNotifier.value = true;
    _logMediationInitialization(status);
    return status;
  }

  /// Records an initialization status instance directly (used for testing and diagnostics).
  void recordInitializationStatus(InitializationStatus status) {
    _initializationStatus = status;
    _logMediationInitialization(status);
  }

  static void _logMediationInitialization(InitializationStatus status) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[$timestamp][AdService][Mediation] MobileAds initialized.');
    final adapters = status.adapterStatuses;
    if (adapters.isEmpty) {
      debugPrint(
        '[$timestamp][AdService][Mediation] No adapter statuses returned.',
      );
      return;
    }
    var unityFound = false;
    for (final entry in adapters.entries) {
      final name = entry.key;
      final adapterStatus = entry.value;
      final isUnity = name.toLowerCase().contains('unity');
      if (isUnity) unityFound = true;
      debugPrint(
        '[$timestamp][AdService][Mediation] Adapter: $name | '
        'State: ${adapterStatus.state.name} | Latency: ${adapterStatus.latency}s | '
        'Description: "${adapterStatus.description}"'
        '${isUnity ? " [Unity Ads]" : ""}',
      );
    }
    if (!unityFound) {
      debugPrint(
        '[$timestamp][AdService][Mediation] Unity Ads adapter not yet reporting in adapterStatuses. '
        'Ensure Unity Ads is enabled in AdMob Mediation groups for unit $rewardedAdUnitId.',
      );
    }
  }

  /// AdMob full-screen ads expire 4 hours after being loaded.
  static bool _isAdExpired(DateTime? loadedAt) {
    if (loadedAt == null) return true;
    return DateTime.now().difference(loadedAt) > const Duration(hours: 4);
  }

  /// Calculates bounded exponential backoff with jitter.
  static Duration _calculateBackoff(int attempt, {bool isNoFill = false}) {
    final baseSeconds = isNoFill ? 15 : 3;
    final maxSeconds = isNoFill ? 60 : 30;
    final exponential = baseSeconds * math.pow(2, math.min(attempt, 4)).toInt();
    final clamped = math.min(exponential, maxSeconds);
    final jitter = math.Random().nextInt(3);
    return Duration(seconds: clamped + jitter);
  }

  // ---------------------------------------------------------------------
  // Startup request pacing
  // ---------------------------------------------------------------------

  /// When the first full-screen load fired; opens the pacing window.
  static DateTime? _pacingWindowStart;

  /// Earliest wall-clock time the next full-screen load may start.
  static DateTime? _nextFullscreenSlot;

  /// Paces full-screen load requests [gap] apart — but only during the
  /// startup burst.
  ///
  /// Rewarded, Rewarded Interstitial and Interstitial are kicked off by
  /// different widgets (App boot, Earn tab, tab switching) that all mount in
  /// the same few hundred milliseconds. Firing three simultaneous requests
  /// from one device against a brand-new AdMob app looks like request spam
  /// and can contribute to ad-serving limits and blanket no-fill responses.
  ///
  /// The window closes after [pacingWindow], so steady-state behaviour — a
  /// user tapping Watch, or a tab switch waiting on an interstitial — is
  /// never delayed by this gate.
  static Future<void> _paceFullscreenRequest() async {
    const gap = Duration(seconds: 2);
    const pacingWindow = Duration(seconds: 30);

    final now = DateTime.now();
    _pacingWindowStart ??= now;
    if (now.difference(_pacingWindowStart!) > pacingWindow) return;

    // Reserve the slot before awaiting. There is no `await` between the read
    // and the write, so concurrent callers queue behind one another instead
    // of all resolving against the same deadline.
    final slot = _nextFullscreenSlot;
    final startAt = (slot == null || now.isAfter(slot)) ? now : slot;
    _nextFullscreenSlot = startAt.add(gap);

    if (startAt.isAfter(now)) {
      final wait = startAt.difference(now);
      debugPrint(
        '[AdService] Pacing full-screen ad request by '
        '${(wait.inMilliseconds / 1000).toStringAsFixed(1)}s '
        '(startup burst window).',
      );
      await Future<void>.delayed(wait);
    }
  }

  /// Structured diagnostic logging for all ad lifecycle events.
  static void _logAdError(
    String format,
    String adUnitId,
    dynamic error, {
    String action = 'load',
  }) {
    final timestamp = DateTime.now().toIso8601String();
    if (error is LoadAdError) {
      final responseInfo = error.responseInfo;
      final adapter = responseInfo?.mediationAdapterClassName ?? 'None';
      final responseId = responseInfo?.responseId ?? 'None';
      debugPrint(
        '[$timestamp][AdService][$format][$action] FAILED: '
        'code=${error.code}, domain="${error.domain}", message="${error.message}", '
        'adapter="$adapter", responseId="$responseId", unit="$adUnitId"',
      );
      final responses = responseInfo?.adapterResponses;
      if (responses != null && responses.isNotEmpty) {
        for (final ar in responses) {
          final isUnity =
              ar.adapterClassName.toLowerCase().contains('unity') ||
              ar.adSourceName.toLowerCase().contains('unity');
          debugPrint(
            '[$timestamp][AdService][$format][Waterfall] '
            'adapter="${ar.adapterClassName}", source="${ar.adSourceName}", '
            'latency=${ar.latencyMillis}ms, '
            'error="${ar.adError?.message ?? 'None'}"'
            '${isUnity ? " [Unity Ads]" : ""}',
          );
        }
      } else {
        // Distinguish "nobody bid" from "a mediator bid and lost": an empty
        // adapterResponses on code 3 means no mediation line item responded
        // at all (Unity never bid), which is a console-side inventory issue
        // rather than an in-app block.
        debugPrint(
          '[$timestamp][AdService][$format][Waterfall] '
          'no mediator responded — Google had no ad to serve and no '
          'mediation source (Unity) placed a bid.',
        );
      }
    } else if (error is AdError) {
      debugPrint(
        '[$timestamp][AdService][$format][$action] FAILED: '
        'code=${error.code}, domain="${error.domain}", message="${error.message}", '
        'unit="$adUnitId"',
      );
    } else {
      debugPrint(
        '[$timestamp][AdService][$format][$action] FAILED: $error, unit="$adUnitId"',
      );
    }
  }

  static String userFriendlyError(int? code) {
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

  /// Preload a rewarded ad; awaits an in-flight load if already running.
  Future<RewardedAd?> preload({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!adsEnabled) return null;

    // Check cached ad TTL.
    if (_ad != null) {
      if (_isAdExpired(_adLoadedTime)) {
        debugPrint('[AdService] Cached RewardedAd expired (>4h); clearing');
        _ad?.dispose();
        _ad = null;
        _adState = AdState.idle;
      } else {
        return _ad;
      }
    }

    // Rate-limit backoff: if Google recently failed, respect backoff delay.
    if (_lastRewardedFailTime != null && _rewardedRetryDelay != null) {
      final elapsed = DateTime.now().difference(_lastRewardedFailTime!);
      if (elapsed < _rewardedRetryDelay!) {
        final remaining = (_rewardedRetryDelay! - elapsed).inSeconds;
        debugPrint(
          '[AdService] Skipping RewardedAd preload: backoff active (${remaining}s remaining)',
        );
        return null;
      }
    }

    // If an in-flight load is pending, await it.
    if (_rewardedCompleter != null) {
      try {
        return await _rewardedCompleter!.future.timeout(timeout);
      } catch (_) {
        return _ad;
      }
    }

    final completer = Completer<RewardedAd?>();
    _rewardedCompleter = completer;
    _adState = AdState.loading;

    try {
      await _paceFullscreenRequest();
      debugPrint(
        '[AdService] Preloading RewardedAd (unit: ${AdUnits.rewarded})...',
      );
      await RewardedAd.load(
        adUnitId: AdUnits.rewarded,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _adState = AdState.loaded;
            _adLoadedTime = DateTime.now();
            _lastRewardedFailTime = null;
            _lastRewardedErrorCode = null;
            _rewardedRetryAttempts = 0;
            _rewardedRetryDelay = null;
            _ad?.dispose();
            _ad = ad;
            _rewardedCompleter = null;
            final adapter =
                ad.responseInfo?.mediationAdapterClassName ?? 'None';
            final responseId = ad.responseInfo?.responseId ?? 'None';
            final isUnity = adapter.toLowerCase().contains('unity');
            debugPrint(
              '[AdService] RewardedAd loaded successfully via adapter="$adapter"'
              '${isUnity ? " (Unity Ads Mediation)" : ""}'
              ' (responseId: $responseId)',
            );
            if (!completer.isCompleted) completer.complete(ad);
          },
          onAdFailedToLoad: (err) {
            _adState = AdState.failed;
            _lastRewardedFailTime = DateTime.now();
            _lastRewardedErrorCode = err.code;
            _rewardedRetryAttempts++;
            _rewardedRetryDelay = _calculateBackoff(
              _rewardedRetryAttempts,
              isNoFill: err.code == 3,
            );
            _logAdError('Rewarded', AdUnits.rewarded, err, action: 'load');
            _rewardedCompleter = null;
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (e) {
      _adState = AdState.failed;
      _lastRewardedFailTime = DateTime.now();
      _rewardedRetryAttempts++;
      _rewardedRetryDelay = _calculateBackoff(_rewardedRetryAttempts);
      _logAdError('Rewarded', AdUnits.rewarded, e, action: 'load_exception');
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
      onError('Ads are temporarily unavailable. Please try again shortly.');
      return;
    }
    if (_isShowingFullScreenAd) {
      onError('Another advertisement is already currently displaying.');
      return;
    }

    final ad = _ad ?? await preload(timeout: waitTimeout);

    if (ad == null) {
      final hint = _lastRewardedErrorCode != null
          ? userFriendlyError(_lastRewardedErrorCode)
          : 'Ad is still loading. Please wait a moment and tap again.';
      onError(hint);
      return;
    }

    // Take ownership and enter showing state.
    _ad = null;
    _adState = AdState.showing;
    _isShowingFullScreenAd = true;

    try {
      await ad.setServerSideOptions(
        ServerSideVerificationOptions(userId: userId),
      );
    } catch (e) {
      debugPrint('[AdService] Failed to set SSV options: $e');
    }

    var rewardGranted = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (a) {
        debugPrint('[AdService] RewardedAd displayed full screen');
      },
      onAdImpression: (a) {
        debugPrint('[AdService] RewardedAd impression recorded');
      },
      onAdClicked: (a) {
        debugPrint('[AdService] RewardedAd clicked');
      },
      onAdDismissedFullScreenContent: (a) {
        debugPrint('[AdService] RewardedAd dismissed');
        a.dispose();
        _isShowingFullScreenAd = false;
        _adState = AdState.idle;
        onClosed();
        // Prepare the next one in the background.
        unawaited(preload());
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        _logAdError('Rewarded', AdUnits.rewarded, error, action: 'show');
        a.dispose();
        _isShowingFullScreenAd = false;
        _adState = AdState.idle;
        onError('Could not play video right now. Please try again.');
        onClosed();
        unawaited(preload());
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (_, reward) {
          if (!rewardGranted) {
            rewardGranted = true;
            debugPrint(
              '[AdService] User earned reward: ${reward.amount} ${reward.type}',
            );
            onEarned(reward);
          }
        },
      );
    } catch (e) {
      debugPrint('[AdService] RewardedAd show exception: $e');
      _isShowingFullScreenAd = false;
      _adState = AdState.idle;
      ad.dispose();
      onError('Could not play video right now. Please try again.');
      onClosed();
      unawaited(preload());
    }
  }

  // ---------------------------------------------------------------------
  // Rewarded interstitial — the second way to earn coins (SSV same as above).
  // ---------------------------------------------------------------------

  Future<RewardedInterstitialAd?> preloadRewardedInterstitial({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!adsEnabled) return null;

    if (_ri != null) {
      if (_isAdExpired(_riLoadedTime)) {
        debugPrint(
          '[AdService] Cached RewardedInterstitialAd expired (>4h); clearing',
        );
        _ri?.dispose();
        _ri = null;
        _riState = AdState.idle;
      } else {
        return _ri;
      }
    }

    if (_lastRiFailTime != null && _riRetryDelay != null) {
      final elapsed = DateTime.now().difference(_lastRiFailTime!);
      if (elapsed < _riRetryDelay!) {
        final remaining = (_riRetryDelay! - elapsed).inSeconds;
        debugPrint(
          '[AdService] Skipping RI preload: backoff active (${remaining}s remaining)',
        );
        return null;
      }
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
    _riState = AdState.loading;

    try {
      await _paceFullscreenRequest();
      debugPrint(
        '[AdService] Preloading RewardedInterstitialAd (unit: ${AdUnits.rewardedInterstitial})...',
      );
      await RewardedInterstitialAd.load(
        adUnitId: AdUnits.rewardedInterstitial,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _riState = AdState.loaded;
            _riLoadedTime = DateTime.now();
            _lastRiFailTime = null;
            _lastRiErrorCode = null;
            _riRetryAttempts = 0;
            _riRetryDelay = null;
            _ri?.dispose();
            _ri = ad;
            _riCompleter = null;
            final adapter =
                ad.responseInfo?.mediationAdapterClassName ?? 'None';
            final responseId = ad.responseInfo?.responseId ?? 'None';
            final isUnity = adapter.toLowerCase().contains('unity');
            debugPrint(
              '[AdService] RewardedInterstitialAd loaded successfully via adapter="$adapter"'
              '${isUnity ? " (Unity Ads Mediation)" : ""}'
              ' (responseId: $responseId)',
            );
            if (!completer.isCompleted) completer.complete(ad);
          },
          onAdFailedToLoad: (err) {
            _riState = AdState.failed;
            _lastRiFailTime = DateTime.now();
            _lastRiErrorCode = err.code;
            _riRetryAttempts++;
            _riRetryDelay = _calculateBackoff(
              _riRetryAttempts,
              isNoFill: err.code == 3,
            );
            _logAdError(
              'RewardedInterstitial',
              AdUnits.rewardedInterstitial,
              err,
              action: 'load',
            );
            _riCompleter = null;
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (e) {
      _riState = AdState.failed;
      _lastRiFailTime = DateTime.now();
      _riRetryAttempts++;
      _riRetryDelay = _calculateBackoff(_riRetryAttempts);
      _logAdError(
        'RewardedInterstitial',
        AdUnits.rewardedInterstitial,
        e,
        action: 'load_exception',
      );
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
    if (!adsEnabled) {
      onError('Ads are temporarily unavailable. Please try again shortly.');
      return;
    }
    if (_isShowingFullScreenAd) {
      onError('Another advertisement is already currently displaying.');
      return;
    }

    final ad = _ri ?? await preloadRewardedInterstitial(timeout: waitTimeout);

    if (ad == null) {
      final hint = _lastRiErrorCode != null
          ? userFriendlyError(_lastRiErrorCode)
          : 'Ad is still loading. Please wait a moment and tap again.';
      onError(hint);
      return;
    }

    _ri = null;
    _riState = AdState.showing;
    _isShowingFullScreenAd = true;

    try {
      await ad.setServerSideOptions(
        ServerSideVerificationOptions(userId: userId),
      );
    } catch (e) {
      debugPrint('[AdService] Failed to set RI SSV options: $e');
    }

    var rewardGranted = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (a) {
        debugPrint('[AdService] RewardedInterstitialAd displayed full screen');
      },
      onAdImpression: (a) {
        debugPrint('[AdService] RewardedInterstitialAd impression recorded');
      },
      onAdClicked: (a) {
        debugPrint('[AdService] RewardedInterstitialAd clicked');
      },
      onAdDismissedFullScreenContent: (a) {
        debugPrint('[AdService] RewardedInterstitialAd dismissed');
        a.dispose();
        _isShowingFullScreenAd = false;
        _riState = AdState.idle;
        onClosed();
        // Do not eagerly reload RI here; load lazily when user is on Earn screen
        // to avoid ad-hoarding penalties.
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        _logAdError(
          'RewardedInterstitial',
          AdUnits.rewardedInterstitial,
          error,
          action: 'show',
        );
        a.dispose();
        _isShowingFullScreenAd = false;
        _riState = AdState.idle;
        onError('Could not play video right now. Please try again.');
        onClosed();
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (_, reward) {
          if (!rewardGranted) {
            rewardGranted = true;
            debugPrint(
              '[AdService] User earned RI reward: ${reward.amount} ${reward.type}',
            );
            onEarned(reward);
          }
        },
      );
    } catch (e) {
      debugPrint('[AdService] RewardedInterstitialAd show exception: $e');
      _isShowingFullScreenAd = false;
      _riState = AdState.idle;
      ad.dispose();
      onError('Could not play video right now. Please try again.');
      onClosed();
    }
  }

  /// Shows the requested rewarded format, then transparently falls back to the
  /// other rewarded format when the preferred unit has no inventory.
  ///
  /// Network fallback (AdMob -> Unity Ads) happens inside each AdMob mediation
  /// request. This method adds a second layer by trying both rewarded ad units,
  /// because mediation groups and inventory can differ between the two units.
  Future<void> showRewardedWithFallback({
    required String userId,
    required void Function(RewardItem reward) onEarned,
    required void Function(String error) onError,
    required void Function() onClosed,
    bool preferInterstitial = false,
    Duration waitTimeout = const Duration(seconds: 8),
  }) async {
    if (!adsEnabled) {
      onError('Ads are temporarily unavailable. Please try again shortly.');
      return;
    }
    if (_isShowingFullScreenAd) {
      onError('Another advertisement is already currently displaying.');
      return;
    }

    // Load both units together. A cached ad returns immediately and an
    // in-flight load is shared by the existing single-flight completers.
    if (!ready && !riReady) {
      await Future.wait([
        preload(timeout: waitTimeout),
        preloadRewardedInterstitial(timeout: waitTimeout),
      ]);
    } else {
      // Keep the alternate warm without delaying a ready preferred format.
      if (!ready) unawaited(preload(timeout: waitTimeout));
      if (!riReady) {
        unawaited(preloadRewardedInterstitial(timeout: waitTimeout));
      }
    }

    final useInterstitial = preferInterstitial
        ? (riReady || !ready)
        : (!ready && riReady);

    if (useInterstitial && riReady) {
      await showRewardedInterstitial(
        userId: userId,
        onEarned: onEarned,
        onError: onError,
        onClosed: onClosed,
        waitTimeout: waitTimeout,
      );
      return;
    }
    if (ready) {
      await show(
        userId: userId,
        onEarned: onEarned,
        onError: onError,
        onClosed: onClosed,
        waitTimeout: waitTimeout,
      );
      return;
    }
    if (riReady) {
      await showRewardedInterstitial(
        userId: userId,
        onEarned: onEarned,
        onError: onError,
        onClosed: onClosed,
        waitTimeout: waitTimeout,
      );
      return;
    }

    final codes = {_lastRewardedErrorCode, _lastRiErrorCode};
    if (codes.contains(2)) {
      onError(userFriendlyError(2));
    } else if (_lastRewardedErrorCode == 3 && _lastRiErrorCode == 3) {
      onError(
        'No rewarded ads are available from any ad source right now. '
        'Please try again in a few minutes.',
      );
    } else {
      onError('Rewarded ads are still loading. Please try again shortly.');
    }
  }

  // ---------------------------------------------------------------------
  // Interstitial — passive profit, no coins. Preloaded for instant show.
  // ---------------------------------------------------------------------

  Future<InterstitialAd?> preloadInterstitial({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!adsEnabled) return null;

    if (_inter != null) {
      if (_isAdExpired(_interLoadedTime)) {
        debugPrint('[AdService] Cached InterstitialAd expired (>4h); clearing');
        _inter?.dispose();
        _inter = null;
        _interState = AdState.idle;
      } else {
        return _inter;
      }
    }

    if (_lastInterFailTime != null && _interRetryDelay != null) {
      final elapsed = DateTime.now().difference(_lastInterFailTime!);
      if (elapsed < _interRetryDelay!) {
        return null;
      }
    }

    if (_interCompleter != null) {
      try {
        return await _interCompleter!.future.timeout(timeout);
      } catch (_) {
        return _inter;
      }
    }

    final completer = Completer<InterstitialAd?>();
    _interCompleter = completer;
    _interState = AdState.loading;

    try {
      await _paceFullscreenRequest();
      debugPrint(
        '[AdService] Preloading InterstitialAd (unit: ${AdUnits.interstitial})...',
      );
      await InterstitialAd.load(
        adUnitId: AdUnits.interstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interState = AdState.loaded;
            _interLoadedTime = DateTime.now();
            _lastInterFailTime = null;
            _lastInterErrorCode = null;
            _interRetryAttempts = 0;
            _interRetryDelay = null;
            _inter?.dispose();
            _inter = ad;
            _interCompleter = null;
            final adapter =
                ad.responseInfo?.mediationAdapterClassName ?? 'None';
            final responseId = ad.responseInfo?.responseId ?? 'None';
            final isUnity = adapter.toLowerCase().contains('unity');
            debugPrint(
              '[AdService] InterstitialAd loaded successfully via adapter="$adapter"'
              '${isUnity ? " (Unity Ads Mediation)" : ""}'
              ' (responseId: $responseId)',
            );
            if (!completer.isCompleted) completer.complete(ad);
          },
          onAdFailedToLoad: (err) {
            _interState = AdState.failed;
            _lastInterFailTime = DateTime.now();
            _lastInterErrorCode = err.code;
            _interRetryAttempts++;
            _interRetryDelay = _calculateBackoff(
              _interRetryAttempts,
              isNoFill: err.code == 3,
            );
            _logAdError(
              'Interstitial',
              AdUnits.interstitial,
              err,
              action: 'load',
            );
            _interCompleter = null;
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (e) {
      _interState = AdState.failed;
      _lastInterFailTime = DateTime.now();
      _interRetryAttempts++;
      _interRetryDelay = _calculateBackoff(_interRetryAttempts);
      _logAdError(
        'Interstitial',
        AdUnits.interstitial,
        e,
        action: 'load_exception',
      );
      _interCompleter = null;
      if (!completer.isCompleted) completer.complete(null);
    }

    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      return _inter;
    }
  }

  /// Show the preloaded interstitial (silently skips if the ad isn't ready
  /// or if another full-screen ad is active — passive formats must never
  /// freeze the navigation).
  ///
  /// Returns `true` only when an AdMob interstitial was actually handed to
  /// the SDK, so callers can fall back to another network when inventory is
  /// missing.
  Future<bool> showInterstitial({void Function()? onClosed}) async {
    if (!adsEnabled || _isShowingFullScreenAd) {
      onClosed?.call();
      return false;
    }

    final ad =
        _inter ??
        await preloadInterstitial(timeout: const Duration(seconds: 2));
    if (ad == null) {
      debugPrint(
        '[AdService] Interstitial not ready; skipping to avoid UX delay',
      );
      onClosed?.call();
      // Trigger preload for the next opportunity
      unawaited(preloadInterstitial());
      return false;
    }

    _inter = null;
    _interState = AdState.showing;
    _isShowingFullScreenAd = true;
    var presented = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (a) {
        presented = true;
        debugPrint('[AdService] InterstitialAd displayed full screen');
      },
      onAdImpression: (a) {
        debugPrint('[AdService] InterstitialAd impression recorded');
      },
      onAdClicked: (a) {
        debugPrint('[AdService] InterstitialAd clicked');
      },
      onAdDismissedFullScreenContent: (a) {
        debugPrint('[AdService] InterstitialAd dismissed');
        a.dispose();
        _isShowingFullScreenAd = false;
        _interState = AdState.idle;
        onClosed?.call();
        unawaited(preloadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        _logAdError(
          'Interstitial',
          AdUnits.interstitial,
          error,
          action: 'show',
        );
        a.dispose();
        _isShowingFullScreenAd = false;
        _interState = AdState.idle;
        onClosed?.call();
        unawaited(preloadInterstitial());
      },
    );

    try {
      await ad.show();
      return presented;
    } catch (e) {
      debugPrint('[AdService] Interstitial show exception: $e');
      _isShowingFullScreenAd = false;
      _interState = AdState.idle;
      ad.dispose();
      onClosed?.call();
      unawaited(preloadInterstitial());
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // App open — passive profit on cold start, preloaded during splash.
  // ---------------------------------------------------------------------

  /// Preload App Open ad in the background.
  Future<AppOpenAd?> preloadAppOpen({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (!adsEnabled) return null;

    if (_appOpen != null) {
      if (_isAdExpired(_appOpenLoadedTime)) {
        debugPrint('[AdService] Cached AppOpenAd expired (>4h); clearing');
        _appOpen?.dispose();
        _appOpen = null;
        _appOpenState = AdState.idle;
      } else {
        return _appOpen;
      }
    }

    if (_lastAppOpenFailTime != null && _appOpenRetryDelay != null) {
      final elapsed = DateTime.now().difference(_lastAppOpenFailTime!);
      if (elapsed < _appOpenRetryDelay!) {
        return null;
      }
    }

    if (_appOpenCompleter != null) {
      try {
        return await _appOpenCompleter!.future.timeout(timeout);
      } catch (_) {
        return _appOpen;
      }
    }

    final completer = Completer<AppOpenAd?>();
    _appOpenCompleter = completer;
    _appOpenState = AdState.loading;

    try {
      debugPrint(
        '[AdService] Preloading AppOpenAd (unit: ${AdUnits.appOpen})...',
      );
      await AppOpenAd.load(
        adUnitId: AdUnits.appOpen,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            _appOpenState = AdState.loaded;
            _appOpenLoadedTime = DateTime.now();
            _lastAppOpenFailTime = null;
            _lastAppOpenErrorCode = null;
            _appOpenRetryAttempts = 0;
            _appOpenRetryDelay = null;
            _appOpen?.dispose();
            _appOpen = ad;
            _appOpenCompleter = null;
            final adapter =
                ad.responseInfo?.mediationAdapterClassName ?? 'None';
            final responseId = ad.responseInfo?.responseId ?? 'None';
            final isUnity = adapter.toLowerCase().contains('unity');
            debugPrint(
              '[AdService] AppOpenAd loaded successfully via adapter="$adapter"'
              '${isUnity ? " (Unity Ads Mediation)" : ""}'
              ' (responseId: $responseId)',
            );
            if (!completer.isCompleted) completer.complete(ad);
          },
          onAdFailedToLoad: (err) {
            _appOpenState = AdState.failed;
            _lastAppOpenFailTime = DateTime.now();
            _lastAppOpenErrorCode = err.code;
            _appOpenRetryAttempts++;
            _appOpenRetryDelay = _calculateBackoff(
              _appOpenRetryAttempts,
              isNoFill: err.code == 3,
            );
            _logAdError('AppOpen', AdUnits.appOpen, err, action: 'load');
            _appOpenCompleter = null;
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (e) {
      _appOpenState = AdState.failed;
      _lastAppOpenFailTime = DateTime.now();
      _appOpenRetryAttempts++;
      _appOpenRetryDelay = _calculateBackoff(_appOpenRetryAttempts);
      _logAdError('AppOpen', AdUnits.appOpen, e, action: 'load_exception');
      _appOpenCompleter = null;
      if (!completer.isCompleted) completer.complete(null);
    }

    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      return _appOpen;
    }
  }

  /// Show App Open ad ONLY IF it was preloaded and is already ready.
  /// Never delays or cold-loads over active UI.
  Future<void> showAppOpenIfAvailable({void Function()? onClosed}) async {
    if (!adsEnabled || _isShowingFullScreenAd) {
      onClosed?.call();
      return;
    }

    final ad = _appOpen;
    if (ad == null || _isAdExpired(_appOpenLoadedTime)) {
      debugPrint('[AdService] AppOpen ad not preloaded; skipping presentation');
      onClosed?.call();
      return;
    }

    _appOpen = null;
    _appOpenState = AdState.showing;
    _isShowingFullScreenAd = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (a) {
        debugPrint('[AdService] AppOpenAd displayed full screen');
      },
      onAdImpression: (a) {
        debugPrint('[AdService] AppOpenAd impression recorded');
      },
      onAdClicked: (a) {
        debugPrint('[AdService] AppOpenAd clicked');
      },
      onAdDismissedFullScreenContent: (a) {
        debugPrint('[AdService] AppOpenAd dismissed');
        a.dispose();
        _isShowingFullScreenAd = false;
        _appOpenState = AdState.idle;
        onClosed?.call();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        _logAdError('AppOpen', AdUnits.appOpen, error, action: 'show');
        a.dispose();
        _isShowingFullScreenAd = false;
        _appOpenState = AdState.idle;
        onClosed?.call();
      },
    );

    try {
      await ad.show();
    } catch (e) {
      debugPrint('[AdService] AppOpen show exception: $e');
      _isShowingFullScreenAd = false;
      _appOpenState = AdState.idle;
      ad.dispose();
      onClosed?.call();
    }
  }

  /// Backwards-compatible signature for `showAppOpen`.
  Future<void> showAppOpen({void Function()? onClosed}) =>
      showAppOpenIfAvailable(onClosed: onClosed);

  /// Application-wide teardown (only when the whole application process terminates).
  /// Individual widgets MUST NOT call this method on the singleton.
  void dispose() {
    _ad?.dispose();
    _ad = null;
    _adState = AdState.idle;

    _ri?.dispose();
    _ri = null;
    _riState = AdState.idle;

    _inter?.dispose();
    _inter = null;
    _interState = AdState.idle;

    _appOpen?.dispose();
    _appOpen = null;
    _appOpenState = AdState.idle;

    _isShowingFullScreenAd = false;
  }
}
