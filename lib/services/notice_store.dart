import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// When the user last skipped the launch notice — keeps it hidden for 24h so
/// someone who already read it is not held up again the same day.
class NoticeStore {
  static final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _kSkippedAt = 'ghosst.notice.skippedAt';
  static const Duration _window = Duration(hours: 24);

  /// True while the last skip is younger than 24 hours.
  static Future<bool> hidden() async {
    final raw = await _storage.read(key: _kSkippedAt);
    final at = int.tryParse(raw ?? '');
    if (at == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) <
        _window;
  }

  static Future<void> skip() => _storage.write(
    key: _kSkippedAt,
    value: '${DateTime.now().millisecondsSinceEpoch}',
  );
}
