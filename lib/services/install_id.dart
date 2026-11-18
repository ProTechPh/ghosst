import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stable per-install id sent as SSV `custom_data`.
///
/// The API counts rewarded views per install as well as per account, so a
/// stack of freshly registered emails on one phone does not get a fresh daily
/// budget each. Not a security boundary — a reinstall or a rooted device can
/// reset it — just enough friction to make farming expensive.
class InstallId {
  InstallId._();

  static const String _key = 'ghosst.installId';
  static final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String? _cached;
  static Future<String>? _pending;

  /// Never throws: keystore trouble falls back to a per-session id, which
  /// still paces this run (the account hash always applies anyway).
  ///
  /// Single-flight: the startup, sign-in, push and ad paths call this at the
  /// same time. On a first run each one used to generate its own id before
  /// the first write landed, so one device became several Novu subscribers
  /// sharing one FCM token — and got the same notification once per copy.
  static Future<String> get() => _pending ??= _load();

  static Future<String> _load() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final existing = await _storage.read(key: _key);
      if (existing != null && existing.isNotEmpty) return _cached = existing;
      final fresh = _randomHex();
      await _storage.write(key: _key, value: fresh);
      return _cached = fresh;
    } catch (_) {
      return _cached = _randomHex();
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _cached = null;
    _pending = null;
  }

  static String _randomHex() {
    final rnd = Random.secure();
    return List.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
