/// Where the API lives. Override per build:
/// `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8099/v1`
class ApiConfig {
  const ApiConfig._();

  // Single host for API requests and relative media URLs.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ghossthub.com/api/v1',
  );

  /// Resolves an `uploads/...` key to an absolute URL using the API host.
  static String publicUrl(String key) {
    final value = key.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final uri = Uri.parse(baseUrl);
    return '${uri.scheme}://${uri.host}/${value.replaceFirst(RegExp(r'^/'), '')}';
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);
}
