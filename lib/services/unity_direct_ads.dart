import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ad_service.dart';

/// Direct Unity Ads rewarded fallback.
///
/// Used only when AdMob has no fill or fails to show. The Unity SDK is already
/// bundled by `gma_mediation_unity`; this class drives it through the Kotlin
/// bridge in `MainActivity.kt`. Coins are still credited only by the Unity
/// server-to-server callback, never from this Dart layer.
class UnityDirectAds {
  UnityDirectAds._();

  static final UnityDirectAds instance = UnityDirectAds._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'com.astrixtech.ghosst/unityads',
  );

  static const String gameId = String.fromEnvironment(
    'UNITY_GAME_ID',
    defaultValue: '800392172',
  );

  static const String placementId = String.fromEnvironment(
    'UNITY_REWARDED_PLACEMENT',
    defaultValue: 'BP_Rewarded_Direct',
  );

  /// Test hook. Production builds use the compile-time flag below.
  @visibleForTesting
  static bool debugEnabled = false;

  /// Off by default: the Unity S2S secret must be configured first, or the
  /// user can watch an ad without receiving coins.
  static bool get enabled =>
      debugEnabled ||
      const bool.fromEnvironment('UNITY_DIRECT_ENABLED', defaultValue: false);

  bool _busy = false;
  VoidCallback? _onCompleted;
  VoidCallback? _onClosed;
  ValueChanged<String>? _onError;

  /// True only for AdMob messages that mean "no ad is available" — not for
  /// "another advertisement is already showing", auth errors, etc.
  static bool isAdMobUnavailable(String error) {
    final e = error.toLowerCase();
    if (e.contains('another advertisement')) return false;
    return e.contains('no ads available') ||
        e.contains('no rewarded ads are available') ||
        e.contains('network connection') ||
        e.contains('ad servers are busy') ||
        e.contains('temporarily unavailable') ||
        e.contains('still loading') ||
        e.contains('could not play video');
  }

  /// Initializes, loads, and shows the direct Unity rewarded ad.
  ///
  /// Returns `true` when the ad started. Completion/close/failure arrive
  /// through the supplied callbacks.
  Future<bool> showRewarded({
    required String userId,
    required VoidCallback onCompleted,
    required VoidCallback onClosed,
    required ValueChanged<String> onError,
  }) async {
    if (!enabled || _busy) return false;

    _busy = true;
    _onCompleted = onCompleted;
    _onClosed = onClosed;
    _onError = onError;
    channel.setMethodCallHandler(_handleEvent);

    try {
      final initialized = await channel
          .invokeMethod<bool>('initialize', {
            'gameId': gameId,
            'testMode': AdUnits.useTestAds,
          })
          .timeout(const Duration(seconds: 10));
      if (initialized != true) {
        _fail('Unity ad is not available right now.');
        return false;
      }

      final loaded = await channel
          .invokeMethod<bool>('load', {'placementId': placementId})
          .timeout(const Duration(seconds: 10));
      if (loaded != true) {
        _fail('Unity ad is not available right now.');
        return false;
      }

      final shown = await channel
          .invokeMethod<bool>('show', {
            'placementId': placementId,
            'userId': userId,
          })
          .timeout(const Duration(seconds: 10));
      if (shown != true) {
        _fail('Unity ad is not available right now.');
        return false;
      }
      return true;
    } on TimeoutException {
      _fail('Unity ad is taking too long. Please try again.');
      return false;
    } on PlatformException catch (e) {
      _fail(e.message ?? 'Unity ad is not available right now.');
      return false;
    } on MissingPluginException {
      _fail('Unity ad is not available in this build.');
      return false;
    }
  }

  Future<void> _handleEvent(MethodCall call) async {
    if (call.method != 'event') return;
    final args = call.arguments;
    final type = args is Map ? args['type'] as String? : null;
    final rawMessage = args is Map ? args['message'] as String? : null;
    final message = (rawMessage == null || rawMessage.isEmpty)
        ? 'Unity ad is not available right now.'
        : rawMessage;

    switch (type) {
      case 'completed':
        final done = _onCompleted;
        _clear();
        done?.call();
      case 'failed':
        _fail(message);
      case 'closed':
        final closed = _onClosed;
        _clear();
        closed?.call();
      default:
        // loaded/shown/skipped are informational; completion or closed
        // settles the flow.
        break;
    }
  }

  void _fail(String message) {
    final onError = _onError;
    _clear();
    onError?.call(message);
  }

  void _clear() {
    _busy = false;
    _onCompleted = null;
    _onClosed = null;
    _onError = null;
    channel.setMethodCallHandler(null);
  }

  @visibleForTesting
  static void resetForTest() {
    debugEnabled = false;
    instance._clear();
  }
}
