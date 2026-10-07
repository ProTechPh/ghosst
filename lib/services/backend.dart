import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';

import '../appwrite_client.dart';

/// Appwrite collection ids / names used by the app.
class Col {
  static const dbId = 'ghosst';
  static const profiles = 'profiles';
  static const products = 'products';
  static const keys = 'keys';
  static const claims = 'claims';
  static const adRewards = 'ad_rewards';
  static const imageBucket = 'product-images';
}

/// Appwrite function ids.
class Fn {
  // Single combined Appwrite function (claim + AdMob SSV reward callback).
  static const claim = 'claim';
}

/// Parses a `images` column value (JSON array string, CSV string, or list).
List<String> _parseImageIds(dynamic raw) {
  if (raw is List) return raw.whereType<String>().toList();
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final v = jsonDecode(raw);
      if (v is List) return v.whereType<String>().toList();
    } catch (_) {
      // fall through to CSV parsing
    }
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const [];
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.cost,
    required this.active,
    this.description = '',
    this.imageIds = const [],
    this.youtubeUrl = '',
  });

  final String id;
  final String name;
  final int cost;
  final bool active;
  final String description;
  final List<String> imageIds;
  final String youtubeUrl;

  factory Product.fromDoc(Document d) => Product(
        id: d.$id,
        name: d.data['name'] as String? ?? '',
        cost: (d.data['cost'] as num?)?.toInt() ?? 0,
        active: d.data['active'] as bool? ?? true,
        description: d.data['description'] as String? ?? '',
        imageIds: _parseImageIds(d.data['images']),
        youtubeUrl: d.data['youtubeUrl'] as String? ?? '',
      );
}

class Claim {
  Claim({
    required this.id,
    required this.productId,
    required this.productName,
    required this.keyText,
    required this.cost,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final String keyText;
  final int cost;
  final String createdAt;

  factory Claim.fromDoc(Document d) => Claim(
        id: d.$id,
        productId: d.data['productId'] as String? ?? '',
        productName: d.data['productName'] as String? ?? '',
        keyText: d.data['keyText'] as String? ?? '',
        cost: (d.data['cost'] as num?)?.toInt() ?? 0,
        createdAt: d.data['createdAt'] as String? ?? d.$createdAt,
      );
}

class AdReward {
  AdReward({
    required this.reward,
    required this.createdAt,
  });

  final int reward;
  final String createdAt;

  factory AdReward.fromDoc(Document d) => AdReward(
        reward: (d.data['reward'] as num?)?.toInt() ?? 0,
        createdAt: d.data['createdAt'] as String? ?? d.$createdAt,
      );
}

class StockEntry {
  StockEntry({
    required this.keyId,
    required this.productId,
    required this.keyText,
    required this.status,
  });
  final String keyId;
  final String productId;
  final String keyText;
  final String status;

  factory StockEntry.fromDoc(Document d) => StockEntry(
        keyId: d.$id,
        productId: d.data['productId'] as String? ?? '',
        keyText: d.data['key'] as String? ?? '',
        status: d.data['status'] as String? ?? 'available',
      );
}

class Backend {
  static final _db = Databases(client);
  static final _account = Account(client);
  static final _functions = Functions(client);
  static final _storage = Storage(client);

  // ---- session ----

  static Future<User?> currentUser() async {
    try {
      return await _account.get();
    } on AppwriteException catch (e) {
      if (e.type == 'user_unauthorized' || e.code == 401) return null;
      rethrow;
    }
  }

  static Future<void> signOut() => _account.deleteSession(sessionId: 'current');

  // ---- profile ----

  /// Coin balance for the signed-in user (0 if profile not created yet).
  static Future<int> coins() async {
    final user = await currentUser();
    if (user == null) return 0;
    try {
      final d = await _db.getDocument(
        databaseId: Col.dbId,
        collectionId: Col.profiles,
        documentId: user.$id,
      );
      return (d.data['coins'] as num?)?.toInt() ?? 0;
    } on AppwriteException catch (e) {
      if (e.code == 404) return 0;
      rethrow;
    }
  }

  // ---- store ----

  static Future<List<Product>> products() async {
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.products,
      queries: [
        Query.equal('active', true),
        Query.orderAsc('name'),
        Query.limit(100),
      ],
    );
    return r.documents.map(Product.fromDoc).toList();
  }

  /// How many keys are still in stock for a product.
  static Future<int> availableCount(String productId) async {
    try {
      final r = await _db.listDocuments(
        databaseId: Col.dbId,
        collectionId: Col.keys,
        queries: [
          Query.equal('productId', productId),
          Query.equal('status', 'available'),
          Query.limit(1),
        ],
      );
      return r.total;
    } on AppwriteException {
      // Regular users have no read access to `keys`; stock shown as unknown.
      return -1;
    }
  }

  /// Spend coins, get the next available key. Returns the key text.
  ///
  /// The function identifies the caller from the `x-appwrite-user-jwt` header
  /// Appwrite forwards automatically for signed-in users.
  static Future<String> claim(String productId) async {
    final exec = await _runFunction(Fn.claim, {'productId': productId});
    final body = _parseOutput(exec);
    if (body['ok'] != true) {
      throw AppwriteException(
        body['error'] as String? ?? 'Claim failed',
        400,
      );
    }
    return body['key'] as String;
  }

  // ---- claims history ----

  static Future<List<Claim>> myClaims() async {
    final user = await currentUser();
    if (user == null) return [];
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.claims,
      queries: [
        Query.equal('userId', user.$id),
        Query.orderDesc('createdAt'),
        Query.limit(100),
      ],
    );
    return r.documents.map(Claim.fromDoc).toList();
  }

  // ---- ad reward ledger ----

  /// Rewards earned by watching ads, newest first.
  ///
  /// The `ad_rewards` collection is written by the reward-ssv function only
  /// (no client read permission by default), so this degrades to an empty
  /// list instead of throwing — the wallet derives totals until the
  /// collection grants `read("user:<uid>")`.
  static Future<List<AdReward>> myAdRewards() async {
    final user = await currentUser();
    if (user == null) return [];
    try {
      final r = await _db.listDocuments(
        databaseId: Col.dbId,
        collectionId: Col.adRewards,
        queries: [
          Query.equal('userId', user.$id),
          Query.orderDesc('createdAt'),
          Query.limit(100),
        ],
      );
      return r.documents.map(AdReward.fromDoc).toList();
    } catch (_) {
      return [];
    }
  }

  // ---- admin ----

  /// True when the caller can read the `keys` collection (team:admins).
  static Future<bool> isAdmin() async {
    try {
      await _db.listDocuments(
        databaseId: Col.dbId,
        collectionId: Col.keys,
        queries: [Query.limit(1)],
      );
      return true;
    } on AppwriteException {
      return false;
    }
  }

  static Future<void> addKeys({
    required String productId,
    required List<String> keys,
  }) async {
    for (final k in keys) {
      await _db.createDocument(
        databaseId: Col.dbId,
        collectionId: Col.keys,
        documentId: ID.unique(),
        data: {
          'productId': productId,
          'key': k,
          'status': 'available',
        },
      );
    }
  }

  static Future<List<StockEntry>> listKeys() async {
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.keys,
      queries: [Query.orderDesc(r'$createdAt'), Query.limit(200)],
    );
    return r.documents.map(StockEntry.fromDoc).toList();
  }

  static Future<List<StockEntry>> listAvailableKeys() async {
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.keys,
      queries: [
        Query.equal('status', 'available'),
        Query.orderDesc(r'$createdAt'),
        Query.limit(200),
      ],
    );
    return r.documents.map(StockEntry.fromDoc).toList();
  }

  static Future<int> availableStock() async {
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.keys,
      queries: [
        Query.equal('status', 'available'),
        Query.limit(1),
      ],
    );
    return r.total;
  }

  static Future<void> createProduct({
    required String name,
    required int cost,
    String description = '',
    String youtubeUrl = '',
    List<String> imageIds = const [],
  }) async {
    final data = <String, dynamic>{'name': name, 'cost': cost, 'active': true};
    // Only sent when set — keeps basic product creation working even before
    // the optional columns exist in the console.
    if (description.isNotEmpty) data['description'] = description;
    if (youtubeUrl.isNotEmpty) data['youtubeUrl'] = youtubeUrl;
    if (imageIds.isNotEmpty) data['images'] = jsonEncode(imageIds);
    await _db.createDocument(
      databaseId: Col.dbId,
      collectionId: Col.products,
      documentId: ID.unique(),
      data: data,
    );
  }

  /// Updates a product's catalog fields (always sends the optional columns so
  /// cleared values persist).
  static Future<void> updateProduct({
    required String productId,
    required String name,
    required int cost,
    required String description,
    required String youtubeUrl,
    required List<String> imageIds,
  }) async {
    await _db.updateDocument(
      databaseId: Col.dbId,
      collectionId: Col.products,
      documentId: productId,
      data: {
        'name': name,
        'cost': cost,
        'description': description,
        'youtubeUrl': youtubeUrl,
        'images': jsonEncode(imageIds),
      },
    );
  }

  /// Public URL of an uploaded product image (bucket read = Any).
  ///
  /// Uses `/view` (original file) instead of `/preview?width=` because image
  /// transformations are blocked on the Appwrite free plan (403
  /// storage_image_transformations_blocked). [width] is kept for call-site
  /// compatibility but ignored — sizing is handled by Image.network boxes.
  static String imageUrl(String fileId, {int width = 900}) =>
      '$appwriteEndpoint/storage/buckets/${Col.imageBucket}/files/$fileId'
      '/view?project=$appwriteProjectId';

  /// Uploads a local image to the product-images bucket. Returns the file id.
  static Future<String> uploadImage(String path) async {
    final f = await _storage.createFile(
      bucketId: Col.imageBucket,
      fileId: ID.unique(),
      file: InputFile.fromPath(path: path),
    );
    return f.$id;
  }

  static Future<void> deleteImage(String fileId) =>
      _storage.deleteFile(bucketId: Col.imageBucket, fileId: fileId);

  /// All products, including inactive ones (admin view).
  static Future<List<Product>> allProducts() async {
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.products,
      queries: [Query.orderAsc('name'), Query.limit(100)],
    );
    return r.documents.map(Product.fromDoc).toList();
  }

  static Future<void> setProductActive(String productId, bool active) async {
    await _db.updateDocument(
      databaseId: Col.dbId,
      collectionId: Col.products,
      documentId: productId,
      data: {'active': active},
    );
  }

  static Future<void> deleteKey(String keyId) async {
    await _db.deleteDocument(
      databaseId: Col.dbId,
      collectionId: Col.keys,
      documentId: keyId,
    );
  }

  // ---- function plumbing ----

  /// Executes a function and waits for completion.
  /// Returns the raw [Execution].
  static Future<Execution> _runFunction(
    String functionId,
    Map<String, dynamic> data,
  ) async {
    final exec = await _functions.createExecution(
      functionId: functionId,
      body: jsonEncode(data),
    );
    if (_isDone(exec.status)) return exec;
    if (_isFailed(exec.status)) {
      throw AppwriteException(
        'Function $functionId failed: ${_execError(exec)}',
        500,
      );
    }
    // Still processing (async function) — poll briefly.
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final e2 = await _functions.getExecution(
        functionId: functionId,
        executionId: exec.$id,
      );
      if (_isDone(e2.status)) return e2;
      if (_isFailed(e2.status)) {
        throw AppwriteException(
          'Function $functionId failed: ${_execError(e2)}',
          500,
        );
      }
    }
    throw AppwriteException('Function $functionId timed out', 504);
  }

  static bool _isDone(String status) =>
      status == 'completed' || status == 'ready';

  static bool _isFailed(String status) =>
      status == 'failed' || status == 'cancelled' || status == 'errors';

  static String _execError(Execution e) {
    if (e.errors.trim().isNotEmpty) return e.errors;
    if (e.responseBody.trim().isNotEmpty) return e.responseBody;
    return e.status;
  }

  /// Parses the function response body into a JSON map.
  /// Falls back to the last JSON line in logs when responseBody is empty
  /// (e.g. 204 responses from domain-triggered executions).
  static Map<String, dynamic> _parseOutput(Execution exec) {
    final raw = exec.responseBody.trim().isNotEmpty
        ? exec.responseBody
        : _lastJsonLine(exec.logs);
    if (raw.trim().isEmpty) {
      return {
        'ok': false,
        'error': _execError(exec).trim().isEmpty ? 'Empty response' : _execError(exec),
      };
    }
    try {
      final v = jsonDecode(raw);
      if (v is Map<String, dynamic>) return v;
      return {'ok': false, 'error': raw};
    } catch (_) {
      return {'ok': false, 'error': raw};
    }
  }

  static String _lastJsonLine(String logs) {
    for (final line in logs.split('\n').reversed) {
      final t = line.trim();
      if (t.startsWith('{') && t.endsWith('}')) return t;
    }
    return '';
  }
}
