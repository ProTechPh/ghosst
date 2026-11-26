/// Where the API lives. Override per build:
/// `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8099/v1`
class ApiConfig {
  const ApiConfig._();

  // Primary: the origin host (Cloudflare DNS-only) so the app bypasses
  // Cloudflare's automatic DDoS L7, which returned 403 to shared mobile-data
  // IPs on the proxied hostname. Some ISP resolvers fail to resolve this
  // subdomain, so ApiClient falls back to [fallbackBaseUrl] on a transport
  // failure (DNS/connection) — never on an HTTP status.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mail.ghossthub.com/api/v1',
  );

  // Fallback: the Cloudflare-proxied host, which resolves on every network.
  // Used only when the primary cannot be reached at the transport level.
  static const String fallbackBaseUrl = String.fromEnvironment(
    'API_FALLBACK_URL',
    defaultValue: 'https://ghossthub.com/api/v1',
  );

  static List<String> get baseUrls => [baseUrl, fallbackBaseUrl];

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
