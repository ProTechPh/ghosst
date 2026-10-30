import 'package:dio/dio.dart';

enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  quotaExceeded,
  server,
  badResponse,
}

/// One exception type for every failure the app can see: Dio transport errors,
/// our JSON envelope, R2 XML, and Cloudflare's HTML limit pages.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.code = '',
    this.status,
    this.retryAfter,
    this.requestId = '',
  });

  final ApiErrorKind kind;
  final String message;
  final String code;
  final int? status;
  final Duration? retryAfter;
  final String requestId;

  bool get retryable =>
      kind == ApiErrorKind.network ||
      kind == ApiErrorKind.timeout ||
      kind == ApiErrorKind.server ||
      kind == ApiErrorKind.rateLimited;

  /// What the user reads. Short, calm, never a stack trace.
  String get userMessage => switch (kind) {
        ApiErrorKind.network => 'Walang internet connection. Subukan ulit.',
        ApiErrorKind.timeout => 'Masyadong matagal ang sagot. Subukan ulit.',
        ApiErrorKind.unauthorized => 'Nag-expire ang session. Mag-sign in ulit.',
        ApiErrorKind.forbidden => 'Wala kang access dito.',
        ApiErrorKind.notFound => 'Hindi na-available ang item na ito.',
        ApiErrorKind.conflict => message,
        ApiErrorKind.rateLimited => 'Sobrang daming request. Subukan ulit maya-maya.',
        ApiErrorKind.quotaExceeded =>
          'Puno na ang server quota ngayong araw. Bumalik bukas — hindi nawala ang coins mo.',
        ApiErrorKind.server => 'May problema sa server. Subukan ulit.',
        ApiErrorKind.badResponse => 'Hindi maintindihan ang sagot ng server.',
      };

  int? get retryAfterSeconds => retryAfter?.inSeconds;

  factory ApiException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          kind: ApiErrorKind.timeout,
          message: e.message ?? 'Timeout',
          retryAfter: const Duration(seconds: 2),
        );
      case DioExceptionType.connectionError:
        return ApiException(kind: ApiErrorKind.network, message: e.message ?? 'Network error');
      default:
        break;
    }

    final response = e.response;
    if (response == null) {
      return ApiException(kind: ApiErrorKind.network, message: e.message ?? '$e');
    }

    final status = response.statusCode;
    final data = response.data;
    final requestId = _header(response, 'x-request-id') ?? '';
    final retryAfter = _parseRetryAfter(_header(response, 'retry-after'));

    // 1) Cloudflare edge errors (1027 daily limit, 1015, 1102 CPU) arrive as
    //    HTML, not our JSON envelope — sometimes with 429, sometimes 503.
    if (data is String && _isCloudflarePage(data)) {
      return ApiException(
        kind: ApiErrorKind.quotaExceeded,
        message: 'Cloudflare limit',
        status: status,
        retryAfter: retryAfter,
        requestId: requestId,
      );
    }

    // 2) R2 answers presigned PUT/GET failures with S3 XML.
    if (data is String && data.contains('<Error>')) {
      final code = RegExp(r'<Code>([^<]+)</Code>').firstMatch(data)?.group(1) ?? '';
      return ApiException(
        kind: code == 'SignatureDoesNotMatch' || code == 'AccessDenied'
            ? ApiErrorKind.forbidden
            : ApiErrorKind.badResponse,
        message: code.isEmpty ? 'Storage error' : code,
        code: code,
        status: status,
      );
    }

    // 3) Our envelope: { ok: false, error: { code, message, requestId } }
    if (data is Map && data['error'] is Map) {
      final error = data['error'] as Map;
      return ApiException(
        kind: _kindFor(status),
        message: (error['message'] as String?) ?? 'Request failed',
        code: (error['code'] as String?) ?? '',
        status: status,
        retryAfter: retryAfter,
        requestId: (error['requestId'] as String?) ?? requestId,
      );
    }

    if (status == 429) {
      return ApiException(
        kind: ApiErrorKind.rateLimited,
        message: 'Too many requests',
        status: status,
        retryAfter: retryAfter ?? const Duration(seconds: 30),
        requestId: requestId,
      );
    }

    return ApiException(
      kind: _kindFor(status),
      message: 'HTTP ${status ?? 'error'}',
      status: status,
      retryAfter: retryAfter,
      requestId: requestId,
    );
  }

  static ApiErrorKind _kindFor(int? status) => switch (status) {
        401 => ApiErrorKind.unauthorized,
        403 => ApiErrorKind.forbidden,
        404 => ApiErrorKind.notFound,
        409 || 402 => ApiErrorKind.conflict,
        429 => ApiErrorKind.rateLimited,
        final s? when s >= 500 => ApiErrorKind.server,
        _ => ApiErrorKind.badResponse,
      };

  static bool _isCloudflarePage(String body) {
    final lower = body.toLowerCase();
    if (!lower.contains('<html') && !lower.contains('cloudflare')) return false;
    return body.contains('1027') ||
        body.contains('1015') ||
        body.contains('1102') ||
        lower.contains('error code') ||
        lower.contains('just a moment');
  }

  static String? _header(Response<dynamic> response, String name) {
    for (final entry in response.headers.map.entries) {
      if (entry.key.toLowerCase() == name && entry.value.isNotEmpty) {
        return entry.value.first;
      }
    }
    return null;
  }

  static Duration? _parseRetryAfter(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds != null) return Duration(seconds: seconds.clamp(1, 3600));
    try {
      final delta = DateTime.parse(raw).difference(DateTime.now());
      return delta.isNegative ? const Duration(seconds: 1) : delta;
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'ApiException(${kind.name}, $status, $code: $message)';
}
