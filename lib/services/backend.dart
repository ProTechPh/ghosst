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

  /// Forced-update announcements published from the Admin screen — read by
  /// every client at launch (older builds get blocked until they update).
  static const updates = 'updates';
  static const imageBucket = 'product-images';

  /// MediaFire download links for non-key products (APK / generic files).
  /// Read+write are restricted to team:admins — the claim function is the
  /// only path that hands these links to a purchaser.
  static const appFiles = 'app_files';
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

/// One selectable duration option for a key product (e.g. `1 Hour` @ 10
/// coins). Stored as a JSON array in the product's `durations` column.
class ProductDuration {
  const ProductDuration({required this.label, required this.cost});

  final String label;
  final int cost;
}

/// Parses the `durations` column (JSON array of `{label, cost}` objects).
List<ProductDuration> _parseDurations(dynamic raw) {
  if (raw is! String || raw.trim().isEmpty) return const [];
  try {
    final v = jsonDecode(raw);
    if (v is! List) return const [];
    final out = <ProductDuration>[];
    for (final e in v) {
      if (e is! Map) continue;
      final label = (e['label'] as String?)?.trim() ?? '';
      final cost = (e['cost'] as num?)?.toInt();
      if (label.isEmpty || cost == null) continue;
      out.add(ProductDuration(label: label, cost: cost));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// What a product delivers when purchased: a license key, an installable
/// APK, or a generic downloadable file.
enum ProductType { key, apk, file }

ProductType productTypeOf(String? raw) => switch (raw) {
  'apk' => ProductType.apk,
  'file' => ProductType.file,
  _ => ProductType.key,
};

class Product {
  Product({
    required this.id,
    required this.name,
    required this.cost,
    required this.active,
    this.description = '',
    this.imageIds = const [],
    this.youtubeUrl = '',
    this.type = 'key',
    this.version = '',
    this.fileSize = '',
    this.durations = const [],
  });

  final String id;
  final String name;
  final int cost;
  final bool active;
  final String description;
  final List<String> imageIds;
  final String youtubeUrl;

  /// Raw `type` column: `key` | `apk` | `file`.
  final String type;

  /// Optional display metadata for app-store products.
  final String version;
  final String fileSize;

  /// Selectable duration options (key products only). Empty ⇒ the product
  /// claims at its flat [cost] like before.
  final List<ProductDuration> durations;

  ProductType get productType => productTypeOf(type);
  bool get isKey => productType == ProductType.key;
  bool get isApk => productType == ProductType.apk;
  bool get isFile => productType == ProductType.file;

  /// True when buying unlocks a MediaFire download instead of a license key.
  bool get isDownloadable => !isKey;

  /// True when the admin gave this key product duration options.
  bool get hasDurations => durations.isNotEmpty;

  factory Product.fromDoc(Document d) => Product(
    id: d.$id,
    name: d.data['name'] as String? ?? '',
    cost: (d.data['cost'] as num?)?.toInt() ?? 0,
    active: d.data['active'] as bool? ?? true,
    description: d.data['description'] as String? ?? '',
    imageIds: _parseImageIds(d.data['images']),
    youtubeUrl: d.data['youtubeUrl'] as String? ?? '',
    type: d.data['type'] as String? ?? 'key',
    version: d.data['version'] as String? ?? '',
    fileSize: d.data['fileSize'] as String? ?? '',
    durations: _parseDurations(d.data['durations']),
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
    this.downloadUrl = '',
    this.duration = '',
  });

  final String id;
  final String productId;
  final String productName;
  final String keyText;
  final int cost;
  final String createdAt;

  /// MediaFire link for app-store purchases. Non-empty ⇒ this claim is a
  /// download, not a license key.
  final String downloadUrl;

  /// Duration option the buyer picked (key products with durations only).
  final String duration;

  bool get isDownload => downloadUrl.isNotEmpty;

  factory Claim.fromDoc(Document d) => Claim(
    id: d.$id,
    productId: d.data['productId'] as String? ?? '',
    productName: d.data['productName'] as String? ?? '',
    keyText: d.data['keyText'] as String? ?? '',
    cost: (d.data['cost'] as num?)?.toInt() ?? 0,
    createdAt: d.data['createdAt'] as String? ?? d.$createdAt,
    downloadUrl: d.data['downloadUrl'] as String? ?? '',
    duration: d.data['duration'] as String? ?? '',
  );
}

class AdReward {
  AdReward({required this.reward, required this.createdAt});

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
    this.claimedBy = '',
    this.claimedAt = '',
    this.duration = '',
  });
  final String keyId;
  final String productId;
  final String keyText;
  final String status;

  /// Filled in by the claim function once the key leaves the stock.
  final String claimedBy;
  final String claimedAt;

  /// Duration pool this key belongs to (`''` = classic flat-cost stock).
  final String duration;

  bool get claimed => status != 'available';

  factory StockEntry.fromDoc(Document d) => StockEntry(
    keyId: d.$id,
    productId: d.data['productId'] as String? ?? '',
    keyText: d.data['key'] as String? ?? '',
    status: d.data['status'] as String? ?? 'available',
    claimedBy: d.data['claimedBy'] as String? ?? '',
    claimedAt: d.data['claimedAt'] as String? ?? '',
    duration: d.data['duration'] as String? ?? '',
  );
}

/// A forced-update announcement published from the Admin screen.
///
/// Clients compare [versionCode] against their own build number at launch;
/// a higher value replaces the whole UI with the blocking update gate.
class UpdateInfo {
  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    this.message = '',
  });

  /// APK build number this announcement demands (`pubspec` `1.0.0+N` → N).
  final int versionCode;

  /// Human label, e.g. `1.0.1` (shown on the gate and admin status card).
  final String versionName;

  /// Download link for the new APK (MediaFire share page or direct URL).
  final String url;

  /// Optional "what's new" copy shown on the gate.
  final String message;

  factory UpdateInfo.fromDoc(Document d) => UpdateInfo(
    versionCode: (d.data['versionCode'] as num?)?.toInt() ?? 0,
    versionName: d.data['versionName'] as String? ?? '',
    url: d.data['url'] as String? ?? '',
    message: d.data['message'] as String? ?? '',
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

  /// Single product (used to recover art/metadata for an old purchase).
  /// Returns `null` when the doc is gone or the caller may not read it.
  static Future<Product?> product(String productId) async {
    try {
      final d = await _db.getDocument(
        databaseId: Col.dbId,
        collectionId: Col.products,
        documentId: productId,
      );
      return Product.fromDoc(d);
    } on AppwriteException {
      return null;
    }
  }

  /// Cover image URL for a product — `''` when it has no image uploaded.
  static String productThumbUrl(List<String> imageIds) =>
      imageIds.isEmpty ? '' : imageUrl(imageIds.first, width: 400);

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
  /// Appwrite forwards automatically for signed-in users. [duration] selects
  /// a duration pool when the product offers options (empty = flat claim).
  static Future<String> claim(String productId, {String duration = ''}) async {
    final exec = await _runFunction(Fn.claim, {
      'productId': productId,
      if (duration.isNotEmpty) 'duration': duration,
    });
    final body = _parseOutput(exec);
    if (body['ok'] != true) {
      throw AppwriteException(body['error'] as String? ?? 'Claim failed', 400);
    }
    return body['key'] as String;
  }

  /// Spend coins, unlock a MediaFire download. Returns the download URL.
  ///
  /// The `claim` function branches on the product's `type` column; for
  /// `apk`/`file` products it returns `downloadUrl` instead of `key`.
  static Future<String> claimApp(String productId) async {
    final exec = await _runFunction(Fn.claim, {'productId': productId});
    final body = _parseOutput(exec);
    if (body['ok'] != true) {
      throw AppwriteException(body['error'] as String? ?? 'Claim failed', 400);
    }
    final url = body['downloadUrl'] as String?;
    if (url == null || url.trim().isEmpty) {
      throw AppwriteException('Download not configured', 400);
    }
    return url;
  }

  /// True when the signed-in user already bought [productId].
  static Future<bool> owns(String productId) async {
    final claims = await myClaims();
    return claims.any((c) => c.productId == productId);
  }

  /// Product ids the signed-in user already purchased (app-store items are
  /// one purchase each — repeat buys are disabled in the UI).
  static Future<Set<String>> ownedProductIds() async {
    final claims = await myClaims();
    return claims.map((c) => c.productId).toSet();
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
    String duration = '',
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
          if (duration.isNotEmpty) 'duration': duration,
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

  /// Every stock row of a single product — used by the admin Keys dialog so
  /// the view reflects the database, not the shared 200-row list window.
  static Future<List<StockEntry>> keysForProduct(String productId) async {
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.keys,
      queries: [
        Query.equal('productId', productId),
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
      queries: [Query.equal('status', 'available'), Query.limit(1)],
    );
    return r.total;
  }

  /// Creates a product. Returns the new document id (needed to attach a
  /// MediaFire link to `app_files` right after creation).
  static Future<String> createProduct({
    required String name,
    required int cost,
    String description = '',
    String youtubeUrl = '',
    List<String> imageIds = const [],
    String type = 'key',
    String version = '',
    String fileSize = '',
    String durations = '',
  }) async {
    final data = <String, dynamic>{'name': name, 'cost': cost, 'active': true};
    // Only sent when set — keeps basic product creation working even before
    // the optional columns exist in the console.
    if (description.isNotEmpty) data['description'] = description;
    if (youtubeUrl.isNotEmpty) data['youtubeUrl'] = youtubeUrl;
    if (imageIds.isNotEmpty) data['images'] = jsonEncode(imageIds);
    if (type != 'key') data['type'] = type;
    if (version.isNotEmpty) data['version'] = version;
    if (fileSize.isNotEmpty) data['fileSize'] = fileSize;
    if (durations.isNotEmpty) data['durations'] = durations;
    final doc = await _db.createDocument(
      databaseId: Col.dbId,
      collectionId: Col.products,
      documentId: ID.unique(),
      data: data,
    );
    return doc.$id;
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
    String type = 'key',
    String version = '',
    String fileSize = '',
    String durations = '',
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
        'type': type,
        'version': version,
        'fileSize': fileSize,
        'durations': durations,
      },
    );
  }

  // ---- MediaFire app files (admin) ----

  /// Stored MediaFire link for [productId], or `''` when unset.
  ///
  /// `app_files` is readable by team:admins only — regular users (and the
  /// store UI) never read it; the claim function is the sole outlet.
  static Future<String> appFileFor(String productId) async {
    try {
      final r = await _db.listDocuments(
        databaseId: Col.dbId,
        collectionId: Col.appFiles,
        queries: [Query.equal('productId', productId), Query.limit(1)],
      );
      if (r.documents.isEmpty) return '';
      return r.documents.first.data['url'] as String? ?? '';
    } on AppwriteException {
      return '';
    }
  }

  /// Saves (or replaces) the MediaFire link for [productId]. Admin-only.
  static Future<void> upsertAppFile(String productId, String url) async {
    final link = url.trim();
    if (link.isEmpty) return;
    String? existing;
    try {
      final r = await _db.listDocuments(
        databaseId: Col.dbId,
        collectionId: Col.appFiles,
        queries: [Query.equal('productId', productId), Query.limit(1)],
      );
      if (r.documents.isNotEmpty) existing = r.documents.first.$id;
    } on AppwriteException {
      existing = null;
    }
    if (existing != null) {
      await _db.updateDocument(
        databaseId: Col.dbId,
        collectionId: Col.appFiles,
        documentId: existing,
        data: {'url': link},
      );
    } else {
      await _db.createDocument(
        databaseId: Col.dbId,
        collectionId: Col.appFiles,
        documentId: ID.unique(),
        data: {'productId': productId, 'url': link},
      );
    }
  }

  /// Deletes the stored MediaFire link for [productId] (admin).
  ///
  /// A missing document is fine, but a failed DELETE now throws — the
  /// product-delete cascade reports leftovers instead of hiding them.
  static Future<void> deleteAppFile(String productId) async {
    String? docId;
    try {
      final r = await _db.listDocuments(
        databaseId: Col.dbId,
        collectionId: Col.appFiles,
        queries: [Query.equal('productId', productId), Query.limit(1)],
      );
      if (r.documents.isEmpty) return;
      docId = r.documents.first.$id;
    } on AppwriteException {
      // Nothing stored (or the lookup failed) — same as before.
      return;
    }
    await _db.deleteDocument(
      databaseId: Col.dbId,
      collectionId: Col.appFiles,
      documentId: docId,
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

  /// Removes the product document (delete → team `admins` only).
  /// Cleaning up its keys / app file / images is the caller's job.
  static Future<void> deleteProduct(String productId) async {
    await _db.deleteDocument(
      databaseId: Col.dbId,
      collectionId: Col.products,
      documentId: productId,
    );
  }

  static Future<void> deleteKey(String keyId) async {
    await _db.deleteDocument(
      databaseId: Col.dbId,
      collectionId: Col.keys,
      documentId: keyId,
    );
  }

  /// Removes EVERY key of [productId] straight from the database — queried
  /// per product in pages, not taken from the admin's shared 200-row window,
  /// so a product delete leaves no stock rows behind.
  ///
  /// Returns how many rows could NOT be deleted (0 = fully clean).
  static Future<int> deleteKeysForProduct(String productId) async {
    final failed = <String>{};
    while (true) {
      final r = await _db.listDocuments(
        databaseId: Col.dbId,
        collectionId: Col.keys,
        queries: [Query.equal('productId', productId), Query.limit(100)],
      );
      if (r.documents.isEmpty) break;
      var anyRemoved = false;
      for (final d in r.documents) {
        try {
          await _db.deleteDocument(
            databaseId: Col.dbId,
            collectionId: Col.keys,
            documentId: d.$id,
          );
          anyRemoved = true;
        } catch (_) {
          failed.add(d.$id);
        }
      }
      // Every remaining row failed to delete — don't spin forever.
      if (!anyRemoved) break;
    }
    return failed.length;
  }

  // ---- forced app update ----

  /// Latest active announcement (highest version wins), or null when none.
  ///
  /// Never throws: the launch gate must not break the app when the
  /// `updates` collection doesn't exist yet or the client can't read it.
  static Future<UpdateInfo?> checkForcedUpdate() async {
    try {
      final r = await _db.listDocuments(
        databaseId: Col.dbId,
        collectionId: Col.updates,
        queries: [Query.equal('active', true), Query.limit(100)],
      );
      UpdateInfo? best;
      for (final d in r.documents) {
        final u = UpdateInfo.fromDoc(d);
        if (best == null || u.versionCode > best.versionCode) best = u;
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  /// Publishes a new forced update, retiring any previous announcement first
  /// so exactly one active doc exists. Create/Delete = team admins only.
  static Future<void> publishUpdate({
    required int versionCode,
    required String versionName,
    required String url,
    String message = '',
  }) async {
    await clearUpdates();
    await _db.createDocument(
      databaseId: Col.dbId,
      collectionId: Col.updates,
      documentId: ID.unique(),
      data: {
        'versionCode': versionCode,
        'versionName': versionName.trim(),
        'url': url.trim(),
        'message': message.trim(),
        'active': true,
      },
    );
  }

  /// Retires every active announcement — older builds are allowed in again.
  static Future<void> clearUpdates() async {
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.updates,
      queries: [Query.equal('active', true), Query.limit(100)],
    );
    for (final d in r.documents) {
      await _db.deleteDocument(
        databaseId: Col.dbId,
        collectionId: Col.updates,
        documentId: d.$id,
      );
    }
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
        'error': _execError(exec).trim().isEmpty
            ? 'Empty response'
            : _execError(exec),
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
