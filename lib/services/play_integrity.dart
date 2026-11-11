import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'distribution.dart';
import 'security.dart';

/// A Play Integrity token and the nonce it was requested with.
@immutable
class PlayIntegrityProof {
  const PlayIntegrityProof({required this.token, required this.nonce});

  final String token;
  final String nonce;
}

/// Classic Play Integrity request, **observe-only**.
///
/// The app never decides based on the verdict: the token goes to the API,
/// which decodes it with a service account and writes one log line. Blocking
/// stays with the local signature gate in [Security], which works on both
/// flavors.
///
/// Play only attests Play-installed builds, so this is skipped for debug
/// builds and the `direct` flavor — a sideloaded APK would always come back
/// `UNEVALUATED`, which is not a signal.
class PlayIntegrity {
  PlayIntegrity._();

  static const String _kLastReportAt = 'ghosst.integrity.lastReportAt';
  static const Duration _window = Duration(hours: 24);

  static final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Classic requests are capped at 5 per app instance per minute and 10k per
  /// day, and Google asks that they stay infrequent — one report per install
  /// per 24h is plenty for telemetry.
  static Future<bool> due() async {
    try {
      final raw = await _storage.read(key: _kLastReportAt);
      final at = int.tryParse(raw ?? '');
      if (at == null) return true;
      return DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(at)) >=
          _window;
    } catch (_) {
      // Storage unavailable — reporting is harmless either way.
      return true;
    }
  }

  /// Marks a *successful* report so a failed one retries on the next launch.
  static Future<void> markReported() async {
    try {
      await _storage.write(
        key: _kLastReportAt,
        value: '${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (_) {
      // Best effort.
    }
  }

  /// Returns null when the proof is unavailable (debug, direct flavor,
  /// sideloaded install, no Play Services, quota). Callers must treat null
  /// as "nothing to report", never as a failure.
  static Future<PlayIntegrityProof?> request({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!kReleaseMode || !Platform.isAndroid || !Distribution.isPlay) {
      return null;
    }
    try {
      final raw = await Security.channel
          .invokeMethod<Object>('requestPlayIntegrity')
          .timeout(timeout);
      if (raw is! Map) return null;
      final token = raw['token'];
      final nonce = raw['nonce'];
      if (token is! String || nonce is! String || token.isEmpty) return null;
      return PlayIntegrityProof(token: token, nonce: nonce);
    } catch (_) {
      // Fail open, same policy as the other launch gates.
      return null;
    }
  }
}
