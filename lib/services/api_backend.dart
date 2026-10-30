import 'dart:math' as math;

import '../api/api_client.dart';
import '../api/api_exception.dart';

class ApiProduct {
  const ApiProduct({
    required this.id,
    required this.name,
    required this.cost,
    required this.active,
    required this.description,
    required this.imageUrls,
    required this.youtubeUrl,
    required this.type,
    required this.version,
    required this.fileSize,
    required this.durations,
    required this.availableCount,
  });

  final String id;
  final String name;
  final int cost;
  final bool active;
  final String description;
  final List<String> imageUrls;
  final String youtubeUrl;
  final String type;
  final String version;
  final String fileSize;
  final List<({String label, int cost})> durations;
  final int availableCount;

  bool get isKey => type == 'key';
  bool get isDownloadable => type != 'key';
  bool get hasDurations => durations.isNotEmpty;

  factory ApiProduct.fromJson(Map<String, dynamic> json) => ApiProduct(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        cost: (json['cost'] as num?)?.toInt() ?? 0,
        active: json['active'] as bool? ?? true,
        description: json['description'] as String? ?? '',
        imageUrls: (json['imageUrls'] as List?)?.whereType<String>().toList() ?? const [],
        youtubeUrl: json['youtubeUrl'] as String? ?? '',
        type: json['type'] as String? ?? 'key',
        version: json['version'] as String? ?? '',
        fileSize: json['fileSize'] as String? ?? '',
        durations: (json['durations'] as List? ?? const [])
            .whereType<Map>()
            .map((d) => (
                  label: d['label'] as String? ?? '',
                  cost: (d['cost'] as num?)?.toInt() ?? 0,
                ))
            .toList(),
        availableCount: (json['availableCount'] as num?)?.toInt() ?? 0,
      );
}

class ApiClaim {
  const ApiClaim({
    required this.id,
    required this.productId,
    required this.productName,
    required this.keyText,
    required this.cost,
    required this.duration,
    required this.isDownload,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final String keyText;
  final int cost;
  final String duration;
  final bool isDownload;
  final DateTime? createdAt;

  factory ApiClaim.fromJson(Map<String, dynamic> json) => ApiClaim(
        id: json['id'] as String,
        productId: json['productId'] as String? ?? '',
        productName: json['productName'] as String? ?? '',
        keyText: json['keyText'] as String? ?? '',
        cost: (json['cost'] as num?)?.toInt() ?? 0,
        duration: json['duration'] as String? ?? '',
        isDownload: json['isDownload'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}

class DownloadTicket {
  const DownloadTicket({
    required this.url,
    required this.filename,
    required this.size,
  });

  final String url;
  final String filename;
  final int size;
}

/// Thin, typed wrapper over the Worker. Deliberately separate from
/// `Backend` so the Appwrite path keeps working until the cutover.
class ApiBackend {
  ApiBackend(this._api);

  final ApiClient _api;

  /// Survives in-process retries so a flaky network cannot charge twice.
  final Map<String, String> _claimKeys = {};

  Future<int> coins() async => (await _api.get('/wallet'))['coins'] as int? ?? 0;

  Future<List<ApiProduct>> products() async {
    final res = await _api.get('/products');
    return (res['products'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ApiProduct.fromJson)
        .toList();
  }

  Future<ApiProduct> product(String id) async {
    final res = await _api.get('/products/$id');
    return ApiProduct.fromJson(res['product'] as Map<String, dynamic>);
  }

  Future<List<ApiClaim>> myClaims() async {
    final res = await _api.get('/claims');
    return (res['claims'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ApiClaim.fromJson)
        .toList();
  }

  Future<Set<String>> ownedProductIds() async {
    final claims = await myClaims();
    return claims.where((c) => c.isDownload).map((c) => c.productId).toSet();
  }

  /// Returns `{key}` for license products, `{downloadUrl}` for app/file ones.
  Future<Map<String, dynamic>> claim(String productId, {String duration = ''}) async {
    final cacheKey = '$productId|$duration';
    final idemKey = _claimKeys.putIfAbsent(cacheKey, _randomKey);

    try {
      final res = await _api.post(
        '/claims',
        data: {'productId': productId, if (duration.isNotEmpty) 'duration': duration},
        headers: {'idempotency-key': idemKey},
      );
      _claimKeys.remove(cacheKey);
      return res;
    } on ApiException catch (e) {
      // Keep the key for retryable failures so the retry is free; drop it for
      // terminal ones so the user's next attempt is a fresh decision.
      if (!e.retryable) _claimKeys.remove(cacheKey);
      rethrow;
    }
  }

  Future<DownloadTicket> downloadTicket(String productId) async {
    final res = await _api.get('/downloads/$productId');
    return DownloadTicket(
      url: res['url'] as String,
      filename: res['filename'] as String? ?? 'download',
      size: (res['size'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> deleteAccount() => _api.delete('/account', data: {'confirm': 'DELETE'});

  static String _randomKey() {
    final random = math.Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
