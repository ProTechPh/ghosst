import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// JSON DoH fallback for the API host only. Both providers use the same
/// `Status`/`Answer` schema documented by Cloudflare and Google:
/// https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/
/// https://developers.google.com/speed/public-dns/docs/doh/json
class DohResolver {
  // shortcut: fixed provider anycast IPs bootstrap DoH without ISP DNS; update if a provider changes them.
  static const _providers = [
    _DohProvider(
      endpoint: 'https://cloudflare-dns.com/dns-query',
      bootstrapAddresses: ['1.1.1.1', '1.0.0.1'],
    ),
    _DohProvider(
      endpoint: 'https://dns.google/resolve',
      bootstrapAddresses: ['8.8.8.8', '8.8.4.4'],
    ),
  ];

  static const _providerTimeout = Duration(seconds: 5);
  static const _maxResponseBytes = 64 * 1024;

  static Future<List<InternetAddress>> resolve(
    String host, {
    required HttpClient Function(List<InternetAddress>) clientFactory,
    Future<Map<String, dynamic>> Function(Uri uri)? query,
    Duration providerTimeout = _providerTimeout,
  }) async {
    Object? lastError;
    for (final provider in _providers) {
      HttpClient? client;
      try {
        client = clientFactory(
          provider.bootstrapAddresses.map(InternetAddress.new).toList(),
        );
        final addresses = await _resolveProvider(
          provider,
          host,
          client,
          query: query,
          timeout: providerTimeout,
        );
        if (addresses.isNotEmpty) return addresses;
      } catch (error) {
        lastError = error;
      } finally {
        // Also runs when a query times out, aborting a slow-trickled response.
        client?.close(force: true);
      }
    }
    throw SocketException(
      'DoH resolution failed for $host: ${lastError?.runtimeType ?? 'no answers'}',
    );
  }

  static Future<List<InternetAddress>> _resolveProvider(
    _DohProvider provider,
    String host,
    HttpClient client, {
    required Future<Map<String, dynamic>> Function(Uri uri)? query,
    required Duration timeout,
  }) async {
    final addresses = <InternetAddress>[];
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    for (final type in const ['A', 'AAAA']) {
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('DoH provider timed out', timeout);
      }
      final uri = Uri.parse(
        provider.endpoint,
      ).replace(queryParameters: {'name': host, 'type': type});
      try {
        final pending = query == null ? _query(client, uri) : query(uri);
        final data = await pending.timeout(remaining);
        addresses.addAll(addressesFromResponse(data));
      } catch (error) {
        lastError = error;
      }
    }
    if (addresses.isNotEmpty) return addresses;
    if (lastError != null) throw lastError;
    return const [];
  }

  static Future<Map<String, dynamic>> _query(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri).timeout(_providerTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
    final response = await request.close().timeout(_providerTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw SocketException('DoH HTTP ${response.statusCode} from ${uri.host}');
    }
    final bytes = await _readBounded(response).timeout(_providerTimeout);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('DoH response is not a JSON object');
    }
    return decoded;
  }

  static Future<Uint8List> _readBounded(HttpClientResponse response) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > _maxResponseBytes) {
        throw const FormatException('DoH response is too large');
      }
    }
    return bytes.takeBytes();
  }

  static List<InternetAddress> addressesFromResponse(
    Map<String, dynamic> data,
  ) {
    if (data['Status'] != 0 || data['TC'] == true) return const [];
    final answers = data['Answer'];
    if (answers is! List) return const [];

    final addresses = <InternetAddress>[];
    final seen = <String>{};
    for (final answer in answers) {
      if (answer is! Map) continue;
      final type = answer['type'];
      final value = answer['data'];
      if ((type != 1 && type != 28) || value is! String) continue;
      final address = InternetAddress.tryParse(value);
      if (address == null) continue;
      final matchesType = type == 1
          ? address.type == InternetAddressType.IPv4
          : address.type == InternetAddressType.IPv6;
      if (matchesType && seen.add(address.address)) addresses.add(address);
    }
    return addresses;
  }
}

class _DohProvider {
  const _DohProvider({
    required this.endpoint,
    required this.bootstrapAddresses,
  });

  final String endpoint;
  final List<String> bootstrapAddresses;
}
