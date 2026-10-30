import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Access + refresh tokens live in the platform keystore, never in shared prefs.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const String _kAccess = 'ghosst.access';
  static const String _kRefresh = 'ghosst.refresh';

  Future<String?> accessToken() => _storage.read(key: _kAccess);

  Future<String?> refreshToken() => _storage.read(key: _kRefresh);

  Future<void> write({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  Future<bool> get isSignedIn async {
    final token = await refreshToken();
    return token != null && token.isNotEmpty;
  }
}
