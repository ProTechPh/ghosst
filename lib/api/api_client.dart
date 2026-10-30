import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/session_store.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// One Dio, three interceptors: auth (401 → single-flight refresh) → retry
/// (429/5xx/network) → log. Everything thrown at call sites is an [ApiException].
class ApiClient {
  ApiClient({required SessionStore session, Dio? dio})
      : _session = session,
        _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      sendTimeout: ApiConfig.sendTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      validateStatus: (status) => status != null && status >= 200 && status < 300,
      headers: const {'accept': 'application/json'},
    );

    _dio.interceptors.add(_AuthInterceptor(
      dio: _dio,
      session: _session,
      onSignedOut: () => onSignedOut?.call(),
    ));
    _dio.interceptors.add(_RetryInterceptor(_dio));
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
    }
  }

  final Dio _dio;
  final SessionStore _session;

  /// Set once by main.dart: fires when the refresh token is dead and the UI
  /// must return to the sign-in screen.
  void Function()? onSignedOut;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _run(() async {
        final res = await _dio.get<dynamic>(path, queryParameters: query);
        return _asMap(res.data);
      });

  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) =>
      _run(() async {
        final res = await _dio.post<dynamic>(
          path,
          data: data,
          options: Options(headers: headers),
        );
        return _asMap(res.data);
      });

  Future<Map<String, dynamic>> patch(String path, {Object? data}) => _run(() async {
        final res = await _dio.patch<dynamic>(path, data: data);
        return _asMap(res.data);
      });

  Future<void> delete(String path) => _run(() async {
        await _dio.delete<dynamic>(path);
      });

  /// Exposed for call sites that need cancel tokens or upload progress.
  Dio get raw => _dio;

  Future<void> logout() async {
    try {
      await post('/auth/logout', data: {'refreshToken': await _session.refreshToken()});
    } on ApiException {
      // Best effort — a dead token is already signed out.
    } finally {
      await _session.clear();
    }
  }

  Future<T> _run<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  static Map<String, dynamic> _asMap(dynamic data) =>
      data is Map<String, dynamic> ? data : <String, dynamic>{};
}

class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor({
    required Dio dio,
    required SessionStore session,
    required void Function() onSignedOut,
  })  : _dio = dio,
        _session = session,
        _onSignedOut = onSignedOut;

  final Dio _dio;
  final SessionStore _session;
  final void Function() _onSignedOut;
  Future<bool>? _refreshInFlight;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra['skipAuth'] == true) return handler.next(options);

    final token = await _session.accessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra['authRetried'] == true) {
      return handler.next(err);
    }

    if (!await _refreshOnce()) {
      await _session.clear();
      _onSignedOut();
      return handler.next(err);
    }

    options.extra['authRetried'] = true;
    options.headers['authorization'] = 'Bearer ${await _session.accessToken()}';
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Single-flight: 6 parallel 401s must trigger exactly ONE refresh, or the
  /// rotated tokens invalidate each other.
  Future<bool> _refreshOnce() {
    final pending = _refreshInFlight;
    if (pending != null) return pending;

    final future = _doRefresh().catchError((Object _) => false);
    _refreshInFlight = future;
    return future.whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refresh = await _session.refreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    final res = await _dio.post<dynamic>(
      '/auth/refresh',
      data: {'refreshToken': refresh},
      options: Options(extra: const {'skipAuth': true, 'noRetry': true}),
    );

    final body = res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : null;
    final access = body?['accessToken'] as String?;
    final next = body?['refreshToken'] as String?;
    if (access == null || next == null) return false;

    await _session.write(accessToken: access, refreshToken: next);
    return true;
  }
}

class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);

  final Dio _dio;
  static const int _maxAttempts = 3;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    if (options.extra['noRetry'] == true) return handler.next(err);

    final attempt = (options.extra['retryAttempt'] as int? ?? 0) + 1;
    if (attempt > _maxAttempts) return handler.next(err);

    final api = ApiException.fromDio(err);

    // POST/PATCH are only safe to replay when the caller supplied an
    // Idempotency-Key — otherwise a retried claim could charge twice.
    final isWrite = options.method == 'POST' || options.method == 'PATCH';
    final idempotent = isWrite && _hasIdempotencyKey(options.headers);
    if (isWrite && !idempotent) return handler.next(err);
    if (!api.retryable && api.kind != ApiErrorKind.rateLimited) return handler.next(err);

    final base = api.retryAfter ?? Duration(milliseconds: 600 * (1 << attempt));
    var delay = base + Duration(milliseconds: math.Random().nextInt(400));
    if (delay > const Duration(seconds: 30)) delay = const Duration(seconds: 30);
    await Future<void>.delayed(delay);

    final next = options..extra['retryAttempt'] = attempt;
    try {
      handler.resolve(await _dio.fetch<dynamic>(next));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static bool _hasIdempotencyKey(Map<String, dynamic> headers) =>
      headers.keys.any((k) => k.toLowerCase() == 'idempotency-key');
}
