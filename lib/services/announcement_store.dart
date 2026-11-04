import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Which announcement id this device already closed, so a dismissed banner
/// does not come back on the next launch.
class AnnouncementStore {
  static final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _kDismissed = 'ghosst.announcement.dismissed';

  static Future<String> dismissedId() async =>
      await _storage.read(key: _kDismissed) ?? '';

  static Future<void> dismiss(String id) =>
      _storage.write(key: _kDismissed, value: id);
}
