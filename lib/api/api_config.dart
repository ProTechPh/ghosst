/// Where the API lives. Override per build:
/// `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8099/v1`
class ApiConfig {
  const ApiConfig._();

  // `mail.` points straight at the origin (Cloudflare DNS-only) so the app
  // never hits Cloudflare's automatic DDoS L7, which returned 403 to shared
  // mobile-data IPs on the old `ghossthub.com/api/v1` hostname.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mail.ghossthub.com/api/v1',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);
}
