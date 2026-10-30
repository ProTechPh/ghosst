import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_exception.dart';

DioException _error({
  int? status,
  Object? data,
  Map<String, List<String>> headers = const {},
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/v1/claims');
  return DioException(
    requestOptions: options,
    type: type,
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
    test('Cloudflare 1027 HTML page becomes quotaExceeded, not a claim failure', () {
      const html = '<!DOCTYPE html><html><head><title>Error 1027</title></head>'
          '<body><h1>Error code 1027</h1><p>This account has exceeded its daily request limit.'
          '</p></body></html>';

      final api = ApiException.fromDio(_error(status: 429, data: html));

      expect(api.kind, ApiErrorKind.quotaExceeded);
      expect(api.userMessage, contains('quota'));
      // A quota error is not a reason to replay a claim.
      expect(api.retryable, isFalse);
    });

    test('Worker envelope keeps code, message and request id', () {
      final api = ApiException.fromDio(_error(
        status: 409,
        data: {
          'ok': false,
          'error': {
            'code': 'insufficient_coins',
            'message': 'Not enough coins (need 50, have 20)',
            'requestId': 'req-123',
          },
        },
      ));

      expect(api.kind, ApiErrorKind.conflict);
      expect(api.code, 'insufficient_coins');
      expect(api.requestId, 'req-123');
      expect(api.userMessage, 'Not enough coins (need 50, have 20)');
    });

    test('429 with Retry-After is retryable and carries the wait', () {
      final api = ApiException.fromDio(_error(
        status: 429,
        data: '',
        headers: {
          'retry-after': ['120'],
        },
      ));

      expect(api.kind, ApiErrorKind.rateLimited);
      expect(api.retryAfter, const Duration(seconds: 120));
      expect(api.retryable, isTrue);
    });

    test('R2 signature error is reported as forbidden with the S3 code', () {
      const xml = '<?xml version="1.0" encoding="UTF-8"?>'
          '<Error><Code>SignatureDoesNotMatch</Code><Message>bad sig</Message></Error>';

      final api = ApiException.fromDio(_error(status: 403, data: xml));

      expect(api.kind, ApiErrorKind.forbidden);
      expect(api.code, 'SignatureDoesNotMatch');
      expect(api.retryable, isFalse);
    });

    test('connection error is a retryable network failure', () {
      final api = ApiException.fromDio(_error(
        type: DioExceptionType.connectionError,
      ));

      expect(api.kind, ApiErrorKind.network);
      expect(api.retryable, isTrue);
    });
  });
}
