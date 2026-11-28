import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_client.dart';
import 'package:ghosst/services/session_store.dart';

void main() {
  group('ApiClient.orderedApiAddresses', () {
    test('orders IPv4 answers before IPv6 answers', () {
      final ipv6 = InternetAddress('2606:4700:3033::6815:428e');
      final ipv4 = InternetAddress('104.21.66.142');

      final addresses = ApiClient.orderedApiAddresses([ipv6, ipv4]);

      expect(addresses, [ipv4, ipv6]);
    });

    test('keeps every address in resolver order within each family', () {
      final ipv4a = InternetAddress('104.21.66.142');
      final ipv4b = InternetAddress('172.67.204.135');
      final ipv6 = InternetAddress('2606:4700:3033::6815:428e');

      final addresses = ApiClient.orderedApiAddresses([ipv6, ipv4a, ipv4b]);

      expect(addresses, [ipv4a, ipv4b, ipv6]);
    });

    test('keeps IPv6 when the network has no IPv4 answer', () {
      final ipv6 = InternetAddress('2606:4700:3033::6815:428e');

      final addresses = ApiClient.orderedApiAddresses([ipv6]);

      expect(addresses, [ipv6]);
    });
  });

  group('ApiClient HTTP identity', () {
    test('sets the app User-Agent on the underlying HttpClient', () {
      final client = ApiClient.createHttpClient();
      try {
        expect(client.userAgent, 'GhosstApp/1.0 (Android)');
      } finally {
        client.close(force: true);
      }
    });

    test('configures the app User-Agent on primary requests', () {
      final client = ApiClient(session: SessionStore());
      try {
        expect(
          client.raw.options.headers['user-agent'],
          'GhosstApp/1.0 (Android)',
        );
      } finally {
        client.raw.close(force: true);
      }
    });

    test('creates unique correlation IDs for API logs', () {
      final ids = List.generate(10, (_) => ApiClient.createRequestId());

      expect(ids, everyElement(matches(RegExp(r'^[0-9a-z]+-[0-9a-f]{16}$'))));
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('ApiClient refresh failure classification', () {
    test('an edge 403 keeps the session for a later retry', () {
      final error = _dioError(
        status: 403,
        data: '<html><body>Attention Required</body></html>',
      );

      expect(ApiClient.refreshFailureOutcome(error), isNull);
    });

    test('an API 401 means the refresh token is dead', () {
      final error = _dioError(
        status: 401,
        data: {
          'ok': false,
          'error': {'code': 'unauthorized', 'message': 'Unknown refresh token'},
        },
      );

      expect(ApiClient.refreshFailureOutcome(error), isFalse);
    });

    test('a server failure keeps the refresh token', () {
      expect(ApiClient.refreshFailureOutcome(_dioError(status: 503)), isNull);
    });
  });
}

DioException _dioError({required int status, Object? data}) {
  final options = RequestOptions(path: '/auth/refresh');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: data,
    ),
  );
}
