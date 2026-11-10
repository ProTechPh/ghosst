import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_exception.dart';
import 'package:ghosst/api/error_feedback.dart';

ApiException _limited(ApiErrorKind kind,
        {Duration retryAfter = const Duration(seconds: 10)}) =>
    ApiException(kind: kind, message: 'x', retryAfter: retryAfter);

void main() {
  group('BackendStatus', () {
    test('third consecutive limited error degrades the backend', () {
      final s = BackendStatus();
      expect(s.degraded, isFalse);
      s.record(_limited(ApiErrorKind.rateLimited));
      expect(s.degraded, isFalse);
      s.record(_limited(ApiErrorKind.quotaExceeded));
      expect(s.degraded, isFalse);
      s.record(_limited(ApiErrorKind.rateLimited));
      expect(s.degraded, isTrue);
    });

    test('retryAfter becomes the wait window', () {
      final s = BackendStatus();
      s.record(_limited(ApiErrorKind.rateLimited,
          retryAfter: const Duration(seconds: 120)));
      expect(s.wait, isNotNull);
      expect(s.wait!.inSeconds, greaterThan(100));
    });

    test('non-limited errors reset the streak', () {
      final s = BackendStatus();
      s.record(_limited(ApiErrorKind.rateLimited));
      s.record(_limited(ApiErrorKind.rateLimited));
      s.record(const ApiException(kind: ApiErrorKind.conflict, message: 'x'));
      expect(s.degraded, isFalse);
      s.record(_limited(ApiErrorKind.rateLimited));
      expect(s.degraded, isFalse);
    });

    test('network errors neither advance nor reset the streak', () {
      final s = BackendStatus();
      s.record(_limited(ApiErrorKind.rateLimited));
      s.record(_limited(ApiErrorKind.rateLimited));
      s.record(const ApiException(kind: ApiErrorKind.network, message: 'x'));
      s.record(_limited(ApiErrorKind.rateLimited));
      expect(s.degraded, isTrue);
    });

    test('recordSuccess clears degraded state', () {
      final s = BackendStatus();
      s.record(_limited(ApiErrorKind.rateLimited));
      s.record(_limited(ApiErrorKind.rateLimited));
      s.record(_limited(ApiErrorKind.rateLimited));
      expect(s.degraded, isTrue);
      s.recordSuccess();
      expect(s.degraded, isFalse);
      expect(s.wait, isNull);
    });

    test('non-ApiException is ignored', () {
      final s = BackendStatus();
      s.record(Exception('boom'));
      expect(s.degraded, isFalse);
    });
  });
}
