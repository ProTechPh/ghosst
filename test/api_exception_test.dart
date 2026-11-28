import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_exception.dart';

DioException _error({
  int? status,
  Object? data,
  Object? cause,
  Map<String, List<String>> headers = const {},
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/v1/claims');
  return DioException(
    requestOptions: options,
    type: type,
    error: cause,
    response: status == null
        ? null
        : Response<dynamic>(
            requestOptions: options,
            statusCode: status,
            data: data,
            headers: Headers.fromMap(headers),
          ),
  );
}

void main() {
  group('ApiException.fromDio', () {
    test(
      'Cloudflare 1027 HTML page becomes quotaExceeded, not a claim failure',
      () {
        const html =
            '<!DOCTYPE html><html><head><title>Error 1027</title></head>'
            '<body><h1>Error code 1027</h1><p>This account has exceeded its daily request limit.'
            '</p></body></html>';

        final api = ApiException.fromDio(_error(status: 429, data: html));

        expect(api.kind, ApiErrorKind.quotaExceeded);
        expect(api.userMessage, contains('quota'));
        // A quota error is not a reason to replay a claim.
        expect(api.retryable, isFalse);
      },
    );

    test('Worker envelope keeps code, message and request id', () {
      final api = ApiException.fromDio(
        _error(
          status: 409,
          data: {
            'ok': false,
            'error': {
              'code': 'insufficient_coins',
              'message': 'Not enough coins (need 50, have 20)',
              'requestId': 'req-123',
            },
          },
        ),
      );

      expect(api.kind, ApiErrorKind.conflict);
      expect(api.code, 'insufficient_coins');
      expect(api.requestId, 'req-123');
      expect(api.userMessage, 'Not enough coins (need 50, have 20)');
    });

    test('429 with Retry-After is retryable and carries the wait', () {
      final api = ApiException.fromDio(
        _error(
          status: 429,
          data: '',
          headers: {
            'retry-after': ['120'],
          },
        ),
      );

      expect(api.kind, ApiErrorKind.rateLimited);
      expect(api.retryAfter, const Duration(seconds: 120));
      expect(api.retryable, isTrue);
    });

    test('R2 signature error is reported as forbidden with the S3 code', () {
      const xml =
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<Error><Code>SignatureDoesNotMatch</Code><Message>bad sig</Message></Error>';

      final api = ApiException.fromDio(_error(status: 403, data: xml));

      expect(api.kind, ApiErrorKind.forbidden);
      expect(api.code, 'SignatureDoesNotMatch');
      expect(api.retryable, isFalse);
    });

    test('reel post ban keeps its friendly in-app message', () {
      final api = ApiException.fromDio(
        _error(
          status: 403,
          data: {
            'ok': false,
            'error': {
              'code': 'reels_post_banned',
              'message':
                  'Posting reels is temporarily disabled for your account.',
            },
          },
        ),
      );

      expect(api.kind, ApiErrorKind.forbidden);
      expect(
        api.userMessage,
        'You cannot post reels right now. You can still browse and chat.',
      );
    });

    test('gateway HTML 403 is a block, not a DNS or VPN error', () {
      const html =
          '<!DOCTYPE html><html><head><title>Attention Required</title></head>'
          '<body><h1>Error code: 1010</h1><p>Access denied</p></body></html>';

      final api = ApiException.fromDio(
        _error(
          status: 403,
          data: html,
          headers: {
            'cf-ray': ['abc123-SIN'],
          },
        ),
      );

      expect(api.kind, ApiErrorKind.blocked);
      expect(api.code, 'gateway_blocked');
      expect(api.status, 403);
      expect(api.userMessage, contains('security service'));
      expect(api.userMessage, isNot(contains('Private DNS')));
      expect(api.diagnostic, contains('status=403'));
      expect(api.diagnostic, contains('cfRay=abc123-SIN'));
      expect(api.diagnostic, contains('1010'));
    });

    test('empty and plain-text 403 responses are gateway blocks', () {
      for (final body in const <Object?>[null, '', 'blocked by edge policy']) {
        final api = ApiException.fromDio(_error(status: 403, data: body));

        expect(api.kind, ApiErrorKind.blocked);
        expect(api.code, 'gateway_blocked');
        expect(api.userMessage, contains('security service'));
      }
    });

    test('an API permission error keeps the server message', () {
      final api = ApiException.fromDio(
        _error(
          status: 403,
          data: {
            'ok': false,
            'error': {'code': 'forbidden', 'message': 'Admin only'},
          },
        ),
      );

      expect(api.kind, ApiErrorKind.forbidden);
      expect(api.userMessage, 'Admin only');
    });

    test('socket diagnostics preserve the underlying network error', () {
      final api = ApiException.fromDio(
        _error(
          type: DioExceptionType.connectionError,
          cause: const SocketException('Failed host lookup: ghossthub.com'),
        ),
      );

      expect(api.kind, ApiErrorKind.network);
      expect(api.retryable, isTrue);
      expect(api.diagnostic, contains('SocketException'));
      expect(api.diagnostic, contains('Failed host lookup'));
    });

    test('TLS diagnostics preserve the handshake error', () {
      final api = ApiException.fromDio(
        _error(
          type: DioExceptionType.connectionError,
          cause: const HandshakeException('Certificate validation failed'),
        ),
      );

      expect(api.kind, ApiErrorKind.network);
      expect(api.diagnostic, contains('HandshakeException'));
      expect(api.diagnostic, contains('Certificate validation failed'));
    });

    test('diagnostics redact token fields but keep error envelopes', () {
      final diagnostic = describeDioException(
        _error(
          status: 500,
          data: {
            'accessToken': 'secret-access-token',
            'password': 'secret-password',
            'ok': false,
            'error': {'code': 'internal', 'message': 'Something went wrong'},
          },
        ),
      );

      expect(diagnostic, contains('status=500'));
      expect(diagnostic, contains('internal'));
      expect(diagnostic, isNot(contains('secret-access-token')));
      expect(diagnostic, isNot(contains('secret-password')));
    });

    test('diagnostics never echo arbitrary string bodies', () {
      final diagnostic = describeDioException(
        _error(
          status: 403,
          data: 'password=secret-password accessToken=secret-access-token',
        ),
      );

      expect(diagnostic, contains('status=403'));
      expect(diagnostic, contains('textResponse'));
      expect(diagnostic, isNot(contains('secret-password')));
      expect(diagnostic, isNot(contains('secret-access-token')));
    });

    test('a busy database says so instead of a blanket server error', () {
      final api = ApiException.fromDio(
        _error(
          status: 500,
          data: {
            'ok': false,
            'error': {
              'code': 'server_busy',
              'message': 'Something went wrong on our side',
            },
          },
        ),
      );

      expect(api.kind, ApiErrorKind.server);
      expect(api.userMessage, contains('server is full'));
    });

    test('a missing table points at the setup, not at the user', () {
      final api = ApiException.fromDio(
        _error(
          status: 500,
          data: {
            'ok': false,
            'error': {
              'code': 'server_schema',
              'message': 'Something went wrong on our side',
            },
          },
        ),
      );

      expect(api.userMessage, contains('missing some setup'));
    });
  });
}
