import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../services/session_store.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'doh_resolver.dart';

/// One Dio with diagnostics, auth (401 → single-flight refresh), and retry
/// (429/5xx/network). Everything thrown at call sites is an [ApiException].
///
/// API sockets prefer IPv4: some Wi-Fi routers hand out a broken IPv6 route,
/// while IPv6-only networks still fall back to their IPv6 answer.
class ApiClient {
  // Identify the app instead of sending Dart's bot-like default UA. Cloudflare
  // still may require the narrow BIC exception documented in docs/network-auth-waf.md.
  static const String userAgent = 'GhosstApp/1.0 (Android)';

  ApiClient({required SessionStore session, Dio? dio}) : _session = session {
    _primary = dio ?? _buildDio(ApiConfig.baseUrl);
    if (dio != null) {
      _primary.options = BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        sendTimeout: ApiConfig.sendTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
        headers: const {'accept': 'application/json', 'user-agent': userAgent},
      );
    }
    // refreshDio is a bare client pointed at the primary host; refreshing
    // through _primary would queue the refresh behind the very onError handler
    // that is awaiting it.
    _refreshDio =
        Dio(
            BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: ApiConfig.connectTimeout,
              receiveTimeout: ApiConfig.receiveTimeout,
              headers: const {
                'accept': 'application/json',
                'user-agent': userAgent,
              },
            ),
          )
          ..httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: createHttpClient,
          );
    _primary.interceptors.add(_DiagnosticInterceptor());
    _refreshDio.interceptors.add(_DiagnosticInterceptor());
    _primary.interceptors.add(
      _AuthInterceptor(
        dio: _primary,
        refreshDio: _refreshDio,
        session: _session,
        onSignedOut: () => onSignedOut?.call(),
      ),
    );
    _primary.interceptors.add(_RetryInterceptor(_primary));
  }

  final SessionStore _session;
  late final Dio _primary;
  late final Dio _refreshDio;

  /// Set once by main.dart: fires when the refresh token is dead and the UI
  /// must return to the sign-in screen.
  void Function()? onSignedOut;

  Dio get raw => _primary;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) => _run((dio) async {
    final res = await dio.get<dynamic>(path, queryParameters: query);
    return _asMap(res.data);
  });

  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) => _run((dio) async {
    final res = await dio.post<dynamic>(
      path,
      data: data,
      options: Options(headers: headers, extra: extra),
    );
    return _asMap(res.data);
  });

  Future<Map<String, dynamic>> patch(String path, {Object? data}) =>
      _run((dio) async {
        final res = await dio.patch<dynamic>(path, data: data);
        return _asMap(res.data);
      });

  Future<void> delete(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) => _run((dio) async {
    await dio.delete<dynamic>(path, data: data, queryParameters: query);
  });

  Future<Map<String, dynamic>> deleteMap(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) => _run((dio) async {
    final res = await dio.delete<dynamic>(
      path,
      data: data,
      queryParameters: query,
    );
    return _asMap(res.data);
  });

  Future<void> logout() async {
    try {
      await post(
        '/auth/logout',
        data: {'refreshToken': await _session.refreshToken()},
      );
    } on ApiException {
      // Best effort — a dead token is already signed out.
    } finally {
      await _session.clear();
    }
  }

  Future<T> _run<T>(Future<T> Function(Dio dio) op) async {
    try {
      return await op(_primary);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  static Dio _buildDio(String baseUrl) {
    final dio = Dio()
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: createHttpClient,
      );
    dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      sendTimeout: ApiConfig.sendTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
      headers: const {'accept': 'application/json', 'user-agent': userAgent},
    );
    return dio;
  }

  @visibleForTesting
  static HttpClient createHttpClient() {
    final client = HttpClient()
      ..idleTimeout = const Duration(seconds: 3)
      ..userAgent = userAgent;
    client.connectionFactory = (url, proxyHost, proxyPort) =>
        connectApiSocket(url, proxyHost: proxyHost, proxyPort: proxyPort);
    return client;
  }

  static HttpClient _dohHttpClient(List<InternetAddress> bootstrapAddresses) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..userAgent = userAgent
      ..findProxy = (_) => 'DIRECT';
    client.connectionFactory = (url, proxyHost, proxyPort) => connectApiSocket(
      url,
      proxyHost: proxyHost,
      proxyPort: proxyPort,
      resolve: (_) async => bootstrapAddresses,
      allowDoh: false,
    );
    return client;
  }

  @visibleForTesting
  static Future<ConnectionTask<Socket>> connectApiSocket(
    Uri url, {
    String? proxyHost,
    int? proxyPort,
    Future<List<InternetAddress>> Function(String)? resolve,
    Future<List<InternetAddress>> Function(String)? resolveDoh,
    Future<ConnectionTask<Socket>> Function(InternetAddress, int)? startConnect,
    Future<SecureSocket> Function(Socket, String)? secure,
    bool allowDoh = true,
    Duration systemDnsTimeout = const Duration(seconds: 2),
    Duration systemConnectBudget = const Duration(seconds: 5),
  }) async {
    final host = proxyHost ?? url.host;
    final port = proxyPort ?? url.port;
    final resolver = resolve ?? InternetAddress.lookup;
    final connector = startConnect ?? Socket.startConnect;
    final secureSocket =
        secure ??
        (Socket socket, String host) => SecureSocket.secure(socket, host: host);

    var cancelled = false;
    ConnectionTask<Socket>? tcpTask;
    Socket? currentSocket;
    final result = Completer<Socket>();

    void cancelTcp() {
      final task = tcpTask;
      if (task == null) return;
      unawaited(
        task.socket.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      task.cancel();
    }

    void cancel() {
      if (cancelled) return;
      cancelled = true;
      cancelTcp();
      currentSocket?.close();
      if (!result.isCompleted) {
        result.completeError(const SocketException('Connection cancelled'));
      }
    }

    Future<Socket> connectAddresses(
      List<InternetAddress> addresses, {
      required Duration budget,
    }) async {
      if (addresses.isEmpty) throw SocketException('No address for $host');
      final stopwatch = Stopwatch()..start();
      Duration remaining() {
        final value = budget - stopwatch.elapsed;
        if (value <= Duration.zero) {
          throw TimeoutException('API connection budget exhausted', budget);
        }
        return value;
      }

      Object? lastError;
      for (final address in addresses) {
        if (cancelled) throw const SocketException('Connection cancelled');
        if (stopwatch.elapsed >= budget) break;
        tcpTask = null;
        currentSocket = null;
        var handshakeAbandoned = false;
        try {
          final connectTime = remaining();
          final task = await connector(address, port).timeout(connectTime);
          tcpTask = task;
          if (cancelled) {
            cancelTcp();
            throw const SocketException('Connection cancelled');
          }

          final socket = await task.socket.timeout(remaining());
          currentSocket = socket;
          if (cancelled) {
            socket.close();
            throw const SocketException('Connection cancelled');
          }

          if (url.scheme == 'https' && proxyHost == null) {
            // Keep SNI and certificate validation on the API hostname, even
            // when DoH supplied the IP: https://api.dart.dev/dart-io/SecureSocket/secure.html
            // shortcut: SecureSocket.secure has no cancel handle; destroy late results and let the OS reclaim a never-completing native handshake.
            final handshake = secureSocket(socket, url.host).then((secure) {
              if (handshakeAbandoned) {
                secure.destroy();
                throw const SocketException('TLS handshake abandoned');
              }
              return secure;
            });
            final secure = await handshake.timeout(remaining());
            currentSocket = secure;
            if (cancelled) {
              secure.close();
              throw const SocketException('Connection cancelled');
            }
            tcpTask = null;
            return secure;
          }

          tcpTask = null;
          return socket;
        } catch (error) {
          handshakeAbandoned = true;
          cancelTcp();
          tcpTask = null;
          currentSocket?.close();
          currentSocket = null;
          if (cancelled) throw const SocketException('Connection cancelled');
          lastError = error;
        }
      }
      throw lastError ?? SocketException('Could not connect to $host:$port');
    }

    Future<Socket> connect() async {
      Object? lastError;
      List<InternetAddress> systemAddresses = const [];
      try {
        systemAddresses = orderedApiAddresses(
          await resolver(host).timeout(systemDnsTimeout),
        );
      } catch (error) {
        lastError = error;
        _logConnectionEvent('api_system_dns_failed', host, error);
      }
      if (systemAddresses.isEmpty) {
        _logConnectionEvent('api_system_dns_empty', host, lastError);
      } else {
        try {
          return await connectAddresses(
            systemAddresses,
            budget: systemConnectBudget,
          );
        } catch (error) {
          lastError = error;
          _logConnectionEvent('api_system_connect_failed', host, error);
        }
      }

      final canUseDoh =
          allowDoh &&
          url.scheme == 'https' &&
          proxyHost == null &&
          InternetAddress.tryParse(host) == null;
      if (!canUseDoh) {
        throw lastError ?? SocketException('No address for $host');
      }

      _logConnectionEvent('api_doh_fallback', host, lastError);
      try {
        final dohResolver =
            resolveDoh ??
            (String name) =>
                DohResolver.resolve(name, clientFactory: _dohHttpClient);
        final addresses = orderedApiAddresses(await dohResolver(host));
        final socket = await connectAddresses(
          addresses,
          budget: systemConnectBudget,
        );
        _logConnectionEvent('api_doh_connected', host, null);
        return socket;
      } catch (error) {
        throw SocketException(
          'API connection failed for $host: $lastError; DoH: $error',
        );
      }
    }

    unawaited(
      connect().then(
        (socket) {
          if (!result.isCompleted) result.complete(socket);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!result.isCompleted) result.completeError(error, stackTrace);
        },
      ),
    );

    return ConnectionTask.fromSocket(result.future, cancel);
  }

  static void _logConnectionEvent(String event, String host, Object? error) {
    if (!kDebugMode) return;
    final detail = switch (error) {
      SocketException socketError => socketError.message,
      HandshakeException tlsError => tlsError.message,
      _ => error?.runtimeType.toString(),
    };
    final fields = <String, Object?>{'event': event, 'host': host};
    if (detail != null) fields['detail'] = detail;
    debugPrint(jsonEncode(fields));
  }

  @visibleForTesting
  static List<InternetAddress> orderedApiAddresses(
    List<InternetAddress> addresses,
  ) {
    final ipv4 = addresses.where(
      (address) => address.type == InternetAddressType.IPv4,
    );
    final other = addresses.where(
      (address) => address.type != InternetAddressType.IPv4,
    );
    return [...ipv4, ...other];
  }

  static Map<String, dynamic> _asMap(dynamic data) =>
      data is Map<String, dynamic> ? data : <String, dynamic>{};

  @visibleForTesting
  static bool? refreshFailureOutcome(DioException error) {
    final api = ApiException.fromDio(error);
    return api.kind == ApiErrorKind.unauthorized || api.kind == ApiErrorKind.forbidden
        ? false
        : null;
  }

  @visibleForTesting
  static String createRequestId() {
    final random = math.Random.secure();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-$suffix';
  }
}

class _DiagnosticInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['x-request-id'] ??= ApiClient.createRequestId();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _log(response.requestOptions, {
      'event': 'api_response',
      'status': response.statusCode,
    });
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    _log(error.requestOptions, {
      'event': 'api_error',
      'diagnostic': describeDioException(error),
    });
    handler.next(error);
  }

  void _log(RequestOptions options, Map<String, Object?> fields) {
    if (!kDebugMode) return;
    final path = Uri.tryParse(options.path)?.path ?? options.path;
    debugPrint(
      jsonEncode({
        ...fields,
        'requestId': options.headers['x-request-id'],
        'method': options.method,
        'path': path,
        'attempt': options.extra['retryAttempt'] ?? 0,
      }),
    );
  }
}

class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor({
    required Dio dio,
    required Dio refreshDio,
    required SessionStore session,
    required void Function() onSignedOut,
  }) : _dio = dio,
       _refreshDio = refreshDio,
       _session = session,
       _onSignedOut = onSignedOut;

  final Dio _dio;
  final Dio _refreshDio;
  final SessionStore _session;
  final void Function() _onSignedOut;

  /// Single-flight result: `true` = new tokens, `false` = the refresh token
  /// itself was rejected (dead login), `null` = retryable failure.
  Future<bool?>? _refreshInFlight;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] == true) return handler.next(options);

    final token = await _session.accessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 ||
        options.extra['authRetried'] == true) {
      return handler.next(err);
    }

    final refreshed = await _refreshOnce();
    if (refreshed == null) {
      // Timeout / offline / 5xx: the tokens may still be good. Wiping them
      // would cost the user a password re-entry over one bad signal drop, so
      // report a retryable network failure instead of a dead login.
      return handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: err.error,
          message: 'Could not refresh the session — will retry',
        ),
      );
    }
    if (!refreshed) {
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
  Future<bool?> _refreshOnce() {
    final pending = _refreshInFlight;
    if (pending != null) return pending;

    final future = _doRefresh().catchError((Object _) => null);
    _refreshInFlight = future;
    return future.whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool?> _doRefresh() async {
    final refresh = await _session.refreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    final Response<dynamic> res;
    try {
      res = await _refreshDio.post<dynamic>(
        '/auth/refresh',
        data: {'refreshToken': refresh},
      );
    } on DioException catch (e) {
      // Only an API auth rejection means the login is dead. Edge 403s,
      // timeouts, offline errors, and 5xx responses keep the refresh token.
      return ApiClient.refreshFailureOutcome(e);
    }

    final body = res.data is Map<String, dynamic>
        ? res.data as Map<String, dynamic>
        : null;
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
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (options.extra['noRetry'] == true) return handler.next(err);

    final attempt = (options.extra['retryAttempt'] as int? ?? 0) + 1;
    if (attempt > _maxAttempts) return handler.next(err);

    // A 403 with an HTML body is a gateway/host block (Cloudflare "Attention
    // required", WAF), not our JSON envelope. Those are often transient, and
    // auth writes are safe to replay: register dedupes by email, login is
    // read-only. One retry, then give up.
    final blockedHtml =
        err.response?.statusCode == 403 &&
        err.response?.data is String &&
        (options.path.startsWith('/auth/') || options.path.contains('/ads/'));
    if (blockedHtml && attempt <= 1) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final next = options..extra['retryAttempt'] = attempt;
      try {
        handler.resolve(await _dio.fetch<dynamic>(next));
      } on DioException catch (e) {
        handler.next(e);
      }
      return;
    }

    final api = ApiException.fromDio(err);

    // POST/PATCH are only safe to replay when the caller supplied an
    // Idempotency-Key — otherwise a retried claim could charge twice.
    final isWrite = options.method == 'POST' || options.method == 'PATCH';
    final idempotent = isWrite && _hasIdempotencyKey(options.headers);
    if (isWrite && !idempotent) return handler.next(err);
    if (!api.retryable && api.kind != ApiErrorKind.rateLimited) {
      return handler.next(err);
    }

    final base = api.retryAfter ?? Duration(milliseconds: 600 * (1 << attempt));
    var delay = base + Duration(milliseconds: math.Random().nextInt(400));
    if (delay > const Duration(seconds: 30)) {
      delay = const Duration(seconds: 30);
    }
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
