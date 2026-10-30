import 'dart:io';

import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';

class UploadResult {
  const UploadResult({
    required this.objectKey,
    this.publicUrl = '',
    this.size = 0,
  });

  final String objectKey;
  final String publicUrl;
  final int size;
}

class _Ticket {
  const _Ticket({
    required this.objectKey,
    required this.uploadUrl,
    required this.headers,
  });

  final String objectKey;
  final String uploadUrl;
  final Map<String, dynamic> headers;
}

/// Uploads go Flutter → R2 directly. The Worker only signs the URL.
class R2UploadService {
  R2UploadService(this._api, {Dio? transferClient})
      // Separate, interceptor-free Dio: our JWT must never be sent to
      // *.r2.cloudflarestorage.com.
      : _transfer = transferClient ?? Dio();

  final ApiClient _api;
  final Dio _transfer;

  Future<UploadResult> upload({
    required File file,
    required String scope, // 'product-image' | 'product-file'
    required String contentType,
    required String filename,
    String? productId,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final size = await file.length();
    var ticket = await _presign(
      scope: scope,
      filename: filename,
      contentType: contentType,
      size: size,
      productId: productId,
    );

    var rePresigned = false;
    while (true) {
      try {
        await _transfer.put<void>(
          ticket.uploadUrl,
          // Streamed: a 300 MB APK never sits in memory.
          data: file.openRead(),
          options: Options(
            headers: {
              ...ticket.headers,
              Headers.contentLengthHeader: size,
            },
            validateStatus: (status) => status != null && status >= 200 && status < 300,
            followRedirects: false,
          ),
          onSendProgress: (sent, total) {
            final denominator = total > 0 ? total : size;
            onProgress?.call(
              denominator > 0 ? (sent / denominator).clamp(0.0, 1.0) : 0,
            );
          },
          cancelToken: cancelToken,
        );
        break;
      } on DioException catch (e) {
        // 403/400 here means the 300s ticket expired mid-upload, not bad
        // credentials. Re-presign exactly once.
        final status = e.response?.statusCode;
        if (!rePresigned && (status == 403 || status == 400)) {
          rePresigned = true;
          ticket = await _presign(
            scope: scope,
            filename: filename,
            contentType: contentType,
            size: size,
            productId: productId,
          );
          continue;
        }
        throw ApiException.fromDio(e);
      }
    }

    final done = await _api.post('/uploads/complete', data: {
      'objectKey': ticket.objectKey,
      'productId': productId ?? '',
      'kind': scope == 'product-image' ? 'image' : 'file',
      'filename': filename,
      'expectedSize': size,
      'expectedType': contentType,
    });

    return UploadResult(
      objectKey: done['objectKey'] as String? ?? ticket.objectKey,
      publicUrl: done['publicUrl'] as String? ?? '',
      size: (done['size'] as num?)?.toInt() ?? size,
    );
  }

  Future<_Ticket> _presign({
    required String scope,
    required String filename,
    required String contentType,
    required int size,
    String? productId,
  }) async {
    final res = await _api.post('/uploads/presign', data: {
      'scope': scope,
      'filename': filename,
      'contentType': contentType,
      'size': size,
      'productId': productId ?? '',
    });

    return _Ticket(
      objectKey: res['objectKey'] as String,
      uploadUrl: res['uploadUrl'] as String,
      headers: (res['headers'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}
