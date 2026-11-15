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
  static const String _kPhoto = 'ghosst.photo_url';

  Future<String?> accessToken() => _storage.read(key: _kAccess);

  Future<String?> refreshToken() => _storage.read(key: _kRefresh);

  Future<String?> photoUrl() => _storage.read(key: _kPhoto);

  Future<void> write({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
  }

  Future<void> writePhotoUrl(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await _storage.delete(key: _kPhoto);
    } else {
      await _storage.write(key: _kPhoto, value: url.trim());
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kPhoto);
  }
}
