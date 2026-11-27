import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'models.dart';

class ReelDraftImage {
  const ReelDraftImage({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.mimeType,
  });

  final String path;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String mimeType;

  ReelDraftImage copyWith({
    String? path,
    String? fileName,
    int? sizeBytes,
    String? sha256,
    String? mimeType,
  }) => ReelDraftImage(
    path: path ?? this.path,
    fileName: fileName ?? this.fileName,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256 ?? this.sha256,
    mimeType: mimeType ?? this.mimeType,
  );

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'mimeType': mimeType,
  };
}

class ReelUploadDraft {
  const ReelUploadDraft({
    required this.caption,
    required this.images,
    required this.idempotencyBase,
    this.onProgress,
  });

  final String caption;
  final List<ReelDraftImage> images;
  final String idempotencyBase;
  final void Function(int done, int total)? onProgress;

  ReelUploadDraft copyWith({
    String? caption,
    List<ReelDraftImage>? images,
    String? idempotencyBase,
    void Function(int done, int total)? onProgress,
  }) => ReelUploadDraft(
    caption: caption ?? this.caption,
    images: images ?? this.images,
    idempotencyBase: idempotencyBase ?? this.idempotencyBase,
    onProgress: onProgress ?? this.onProgress,
  );
}

class ReelImageUploadResult {
  const ReelImageUploadResult({
    required this.position,
    required this.imageUrl,
    required this.sha256,
    required this.sizeBytes,
    this.width,
    this.height,
  });

  final int position;
  final String imageUrl;
  final String sha256;
  final int sizeBytes;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson() => {
    'position': position,
    'imageUrl': imageUrl,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };
}

class ReelUploadService {
  ReelUploadService({Dio? dio}) : _dio = dio ?? Dio(), _ownsDio = dio == null;

  final Dio _dio;
  final bool _ownsDio;
  static const int maxImages = 5;
  static const int maxBytesPerImage = 10 * 1024 * 1024;
  static const int maxTotalBytes = 50 * 1024 * 1024;
  static const Set<String> allowedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  static String? validateImages(
    List<ReelDraftImage> images, {
    int totalMaxBytes = maxTotalBytes,
  }) {
    if (images.isEmpty || images.length > maxImages) {
      return 'Upload 1 to 5 images.';
    }
    var total = 0;
    for (final image in images) {
      final ext = image.fileName.toLowerCase().split('.').last;
      final mimeOk =
          allowedMimeTypes.contains(image.mimeType.toLowerCase()) &&
          ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
      if (!mimeOk) return 'Only JPG, PNG, or WebP images are allowed.';
      if (image.sizeBytes < 1 || image.sizeBytes > maxBytesPerImage) {
        return 'Each image must be 10 MB or less.';
      }
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(image.sha256)) {
        return 'Invalid image hash.';
      }
      total += image.sizeBytes;
    }
    if (total > totalMaxBytes) return 'Total image size must be 50 MB or less.';
    return null;
  }

  static String? validateTicket(
    List<ReelDraftImage> images,
    ReelUploadTicket ticket,
  ) {
    if (ticket.expiresAt.isBefore(DateTime.now())) {
      return 'Upload ticket expired.';
    }
    if (ticket.uploads.length != images.length) {
      return 'Upload ticket does not match selected images.';
    }
    for (final upload in ticket.uploads) {
      if (upload.uploadUrl.isEmpty || upload.token.isEmpty) {
        return 'Upload is not configured.';
      }
    }
    return null;
  }

  void close() {
    if (_ownsDio) _dio.close(force: true);
  }

  static Future<String> sha256File(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString();
  }

  Future<List<ReelImageUploadResult>> uploadImages({
    required List<ReelDraftImage> images,
    required ReelUploadTicket ticket,
    void Function(int done, int total)? onImageProgress,
  }) async {
    final invalidImages = validateImages(images);
    if (invalidImages != null) throw ArgumentError(invalidImages);
    final invalidTicket = validateTicket(images, ticket);
    if (invalidTicket != null) throw ArgumentError(invalidTicket);

    final sortedTickets = [...ticket.uploads]
      ..sort((a, b) => a.position.compareTo(b.position));
    final results = <ReelImageUploadResult>[];
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final upload = sortedTickets[i];
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          image.path,
          filename: image.fileName,
        ),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        upload.uploadUrl,
        data: form,
        options: Options(
          headers: {'authorization': 'Bearer ${upload.token}'},
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      final data = response.data ?? const {};
      results.add(
        ReelImageUploadResult(
          position: upload.position,
          imageUrl: data['imageUrl'] as String? ?? '',
          sha256: (data['sha256'] as String? ?? image.sha256).toLowerCase(),
          sizeBytes: (data['sizeBytes'] as num?)?.toInt() ?? image.sizeBytes,
          width: (data['width'] as num?)?.toInt(),
          height: (data['height'] as num?)?.toInt(),
        ),
      );
      onImageProgress?.call(i + 1, images.length);
    }
    return results;
  }
}
