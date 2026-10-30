import 'package:dio/dio.dart';

/// Direct, unsigned uploads to Cloudinary.
///
/// The app needs only the cloud name and a preset marked *unsigned* in the
/// dashboard. The API secret must never ship in the APK: a mobile build is not
/// a confidential client, and anyone can read it out of the bundle.
class CloudinaryUpload {
  static const cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'zp6uwlrj',
  );
  static const uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'ghosst',
  );

  /// Bare client on purpose: a signed-in admin's JWT must not reach Cloudinary.
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  /// Uploads one image and returns its public `secure_url`.
  static Future<String> upload(
    String path, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData()
      ..fields.add(MapEntry('upload_preset', uploadPreset))
      ..files.add(MapEntry('file', await MultipartFile.fromFile(path)));
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
        data: form,
        onSendProgress: onProgress,
      );
      final url = res.data?['secure_url'] as String?;
      if (url == null || url.isEmpty) {
        throw const CloudinaryException('Walang URL sa sagot ng Cloudinary.');
      }
      return url;
    } on DioException catch (e) {
      throw CloudinaryException(_reason(e));
    }
  }

  /// Cloudinary's own wording is the useful one ("preset must be whitelisted
  /// for unsigned uploads"), so hand it back instead of a generic message.
  static String _reason(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final m = (data['error'] as Map)['message'];
      if (m is String && m.isNotEmpty) return m;
    }
    return e.type == DioExceptionType.connectionError
        ? 'Walang internet connection.'
        : 'Upload failed (${e.response?.statusCode ?? 'network'}).';
  }
}

class CloudinaryException implements Exception {
  const CloudinaryException(this.message);

  final String message;

  @override
  String toString() => message;
}
