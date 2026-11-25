import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'models.dart';

class ReelUploadResult {
  const ReelUploadResult({
    required this.videoUrl,
    required this.sha256,
    required this.sizeBytes,
    this.durationMs,
    this.posterUrl,
  });

  final String videoUrl;
  final String sha256;
  final int sizeBytes;
  final int? durationMs;
  final String? posterUrl;
}

class ReelUploadService {
  ReelUploadService({Dio? dio, void Function()? disposeDio})
    : _dio = dio ?? Dio(),
      _disposeDio = disposeDio ?? (dio == null ? () => _owned.close() : null);

  final Dio _dio;
  static final Dio _owned = Dio();
  final void Function()? _disposeDio;
  static const int maxBytes = 50 * 1024 * 1024;

  static String? validateInput({
    required String filePath,
    required int sizeBytes,
    required String sha256,
    required ReelUploadTicket ticket,
  }) {
    if (!filePath.toLowerCase().endsWith('.mp4')) {
      return 'Only MP4 videos are allowed.';
    }
    if (sizeBytes < 1 || sizeBytes > maxBytes || sizeBytes > ticket.maxBytes) {
      return 'Video must be between 1 byte and 50 MB.';
    }
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      return 'Invalid SHA-256.';
    }
    if (ticket.expiresAt.isBefore(DateTime.now())) {
      return 'Upload ticket expired.';
    }
    if (ticket.uploadUrl.isEmpty || ticket.token.isEmpty) {
      return 'Upload is not configured.';
    }
    return null;
  }

  void close() => _disposeDio?.call();

  static Future<String> sha256File(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString();
  }

  Future<ReelUploadResult> upload({
    required String filePath,
    required ReelUploadTicket ticket,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(filePath);
    final size = await file.length();
    final invalid = validateInput(
      filePath: filePath,
      sizeBytes: size,
      sha256: ticket.sha256,
      ticket: ticket,
    );
    if (invalid != null) throw ArgumentError(invalid);

    final form = FormData.fromMap({
      'video': await MultipartFile.fromFile(
        filePath,
        filename: filePath.split(RegExp(r'[/\\]')).last,
      ),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      ticket.uploadUrl,
      data: form,
      options: Options(
        headers: {'authorization': 'Bearer ${ticket.token}'},
        sendTimeout: const Duration(seconds: 120),
        receiveTimeout: const Duration(seconds: 120),
      ),
      onSendProgress: onProgress,
    );
    final data = response.data ?? const {};
    return ReelUploadResult(
      videoUrl: data['videoUrl'] as String? ?? '',
      sha256: data['sha256'] as String? ?? '',
      sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? size,
      durationMs: (data['durationMs'] as num?)?.toInt(),
      posterUrl: data['posterUrl'] as String?,
    );
  }
}
