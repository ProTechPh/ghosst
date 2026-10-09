import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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

  /// MediaFire download links for non-key products (APK / generic files).
  /// Read+write are restricted to team:admins — the claim function is the
  /// only path that hands these links to a purchaser.
  static const appFiles = 'app_files';
}

/// Appwrite function ids.
class Fn {
  // Single combined Appwrite function (claims, rewards, account deletion).
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

class BetaBonusResult {
  const BetaBonusResult({
    required this.granted,
    required this.amount,
    required this.coins,
    required this.code,
    required this.message,
    this.nextAt,
  });

  final bool granted;
  final int amount;
  final int coins;
  final String code;
  final String message;
  final DateTime? nextAt;
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

/// Outcome of a bulk stock write.
///
/// Appwrite has no all-or-nothing batch API — rows land one request at a
/// time — so a paste can partially succeed. The admin panel shows the split
/// instead of pretending the whole submit worked (or didn't).
class StockWriteResult {
  const StockWriteResult({
    required this.added,
    required this.failed,
    this.skipped = 0,
    this.failedKeys = const [],
    this.lastError = '',
  });

  /// Rows that reached the database.
  final int added;

  /// Rows that could not be written after retries.
  final int failed;

  /// Existing keys or in-batch duplicates that were safely skipped.
  final int skipped;

  /// Keys that could not be written (retained so user can re-submit).
  final List<String> failedKeys;

  /// Message of the last failure (trimmed by the caller for display).
  final String lastError;

  bool get ok => failed == 0;
}

class Backend {
  static final _db = Databases(client);
  static final _account = Account(client);
  static final _functions = Functions(client);
  static final _storage = Storage(client);

  /// Rows per stock "submit". Appwrite's batched paths (CSV import and
  /// friends) accept at most 100 rows per call, so a paste bigger than this
  /// is split into chunks of this size and posted one chunk after another
  /// instead of blowing up on the limit.
  static const stockChunkSize = 100;

  /// Requests kept in flight while a chunk is posted — enough to make a
  /// 100-row chunk finish quickly, few enough to stay under rate limits.
  static const _stockWidth = 6;

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

  /// Permanently deletes the signed-in Appwrite user and app-owned personal
  /// records through the privileged account-deletion route in `claim`.
  static Future<void> deleteAccount() async {
    final exec = await _runFunction(Fn.claim, {
      'action': 'deleteAccount',
      'confirm': 'DELETE',
    });
    final body = _parseOutput(exec);
    if (body['ok'] != true) {
      throw AppwriteException(
        body['error'] as String? ?? 'Account deletion failed',
        400,
      );
    }
  }

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

  /// Claims the temporary no-inventory beta fallback. The server owns both
  /// the amount and the once-per-UTC-day limit; the client cannot mint coins.
  static Future<BetaBonusResult> claimBetaBonus() async {
    final exec = await _runFunction(Fn.claim, {'action': 'claimBetaBonus'});
    final body = _parseOutput(exec);
    final nextRaw = body['nextAt'] as String?;
    return BetaBonusResult(
      granted: body['ok'] == true,
      amount: (body['amount'] as num?)?.toInt() ?? 0,
      coins: (body['coins'] as num?)?.toInt() ?? 0,
      code: body['code'] as String? ?? '',
      message: body['error'] as String? ?? '',
      nextAt: nextRaw == null ? null : DateTime.tryParse(nextRaw),
    );
  }

  /// Credits one completed test ad during closed beta. The function enforces
  /// its own cooldown, so bypassing the client timer cannot mint rapid rewards.
  static Future<BetaBonusResult> claimBetaTestReward() async {
    final exec = await _runFunction(Fn.claim, {
      'action': 'claimBetaTestReward',
    });
    final body = _parseOutput(exec);
    final nextRaw = body['nextAt'] as String?;
    return BetaBonusResult(
      granted: body['ok'] == true,
      amount: (body['amount'] as num?)?.toInt() ?? 0,
      coins: (body['coins'] as num?)?.toInt() ?? 0,
      code: body['code'] as String? ?? '',
      message: body['error'] as String? ?? '',
      nextAt: nextRaw == null ? null : DateTime.tryParse(nextRaw),
    );
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

  /// Adds [keys] to a product's stock, posting in manageable chunks and
  /// intelligently handling Appwrite rate limits (429) with exponential
  /// cooldown so bulk uploads do not get blocked halfway through.
  static Future<StockWriteResult> addKeys({
    required String productId,
    required List<String> keys,
    String duration = '',
    bool skipExisting = true,
    void Function(int done, int total, String? status)? onProgress,
  }) async {
    // 1. Deduplicate & trim within the pasted batch:
    final cleanBatch = <String>[];
    final seenInBatch = <String>{};
    var skippedInBatch = 0;
    for (final raw in keys) {
      final k = raw.trim();
      if (k.isEmpty) continue;
      if (seenInBatch.contains(k)) {
        skippedInBatch++;
      } else {
        seenInBatch.add(k);
        cleanBatch.add(k);
      }
    }

    // 2. Existing key detection: check against current keys in database for this product
    var skippedExisting = 0;
    List<String> toInsert = cleanBatch;
    if (skipExisting && cleanBatch.isNotEmpty) {
      onProgress?.call(
        0,
        cleanBatch.length,
        'Checking existing keys in stock…',
      );
      try {
        final existing = await keysForProduct(productId, limit: 5000);
        final existingSet = existing.map((e) => e.keyText.trim()).toSet();
        final freshList = <String>[];
        for (final k in cleanBatch) {
          if (existingSet.contains(k)) {
            skippedExisting++;
          } else {
            freshList.add(k);
          }
        }
        toInsert = freshList;
      } catch (_) {
        // Fallback: proceed with cleanBatch if query failed
      }
    }

    final totalSkipped = skippedInBatch + skippedExisting;
    if (toInsert.isEmpty) {
      return StockWriteResult(
        added: 0,
        failed: 0,
        skipped: totalSkipped,
        failedKeys: const [],
        lastError: '',
      );
    }

    var added = 0;
    var failed = 0;
    final failedKeys = <String>[];
    var lastError = '';
    final total = toInsert.length;

    // Concurrency controls: keep requests paced and polite to stay under
    // Appwrite's rate limit window.
    const chunkSize = 50;
    const workerWidth = 2;

    // Mutex for rate-limit cooldown: ensures only one worker ticks the countdown
    // and other workers pause gracefully without stacking timeouts.
    Future<void>? activeCooldown;
    var rateLimitConsecutive = 0;

    Future<void> handle429() async {
      if (activeCooldown != null) {
        await activeCooldown;
        return;
      }

      rateLimitConsecutive++;
      // Appwrite Cloud enforces a strict 60-second quota window per client.
      // Waiting 60s with a live ticker ensures the window fully resets so
      // all remaining keys can land successfully.
      final cooldownSeconds = 60;

      final completer = Completer<void>();
      activeCooldown = completer.future;

      try {
        for (var sec = cooldownSeconds; sec > 0; sec--) {
          onProgress?.call(
            added + failed,
            total,
            'Rate limit reached — resuming in ${sec}s… ($added/$total)',
          );
          await Future.delayed(const Duration(seconds: 1));
        }
      } finally {
        activeCooldown = null;
        completer.complete();
      }
    }

    Future<void> waitIfRateLimited() async {
      while (activeCooldown != null) {
        await activeCooldown;
      }
    }

    for (var start = 0; start < total; start += chunkSize) {
      final chunk = toInsert.sublist(start, math.min(start + chunkSize, total));
      await _pooled(chunk, workerWidth, (k) async {
        final docId = ID.unique();
        final data = <String, dynamic>{
          'productId': productId,
          'key': k,
          'status': 'available',
          if (duration.isNotEmpty) 'duration': duration,
        };

        const maxAttempts = 12;
        var landed = false;

        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
          await waitIfRateLimited();
          try {
            await _db.createDocument(
              databaseId: Col.dbId,
              collectionId: Col.keys,
              documentId: docId,
              data: data,
            );
            added++;
            landed = true;
            rateLimitConsecutive = math.max(0, rateLimitConsecutive - 1);
            break;
          } on AppwriteException catch (e) {
            if (e.code == 409) {
              // Our own earlier attempt landed before network response was received
              added++;
              landed = true;
              break;
            }
            if (e.code == 429) {
              if (attempt < maxAttempts) {
                await handle429();
                continue;
              }
            } else if ((e.code == 0 || (e.code != null && e.code! >= 500)) &&
                attempt < maxAttempts) {
              await Future.delayed(Duration(milliseconds: 500 * attempt));
              continue;
            }
            // Non-transient or retries exhausted
            lastError = e.message ?? '$e';
            break;
          } catch (e) {
            if (attempt < maxAttempts) {
              await Future.delayed(Duration(milliseconds: 500 * attempt));
              continue;
            }
            lastError = '$e';
            break;
          }
        }

        if (!landed) {
          failed++;
          failedKeys.add(k);
        }

        // Polite inter-item pacing to avoid burst rate limits
        await Future.delayed(const Duration(milliseconds: 60));
        onProgress?.call(added + failed, total, null);
      });

      // Breather between submits so a multi-chunk paste stays polite.
      if (start + chunkSize < total) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }

    return StockWriteResult(
      added: added,
      failed: failed,
      skipped: totalSkipped,
      failedKeys: failedKeys,
      lastError: lastError,
    );
  }

  /// Total rows stored for [productId], straight from the server — the admin
  /// dialog's lists can display up to 5 000 rows. [usedOnly] counts the
  /// claimed rows: `claimed` is the only non-`available` value this app ever
  /// writes, and the filter rides the existing `product_status` index.
  static Future<int> countKeys(
    String productId, {
    bool usedOnly = false,
  }) async {
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.keys,
      queries: [
        Query.equal('productId', productId),
        if (usedOnly) Query.equal('status', 'claimed'),
        Query.limit(1),
      ],
    );
    return r.total;
  }

  /// Counts available (unclaimed) keys for a product, optionally scoped to a
  /// specific duration pool. Returns -1 if index is missing or query fails.
  static Future<int> countAvailableKeys(
    String productId, {
    String duration = '',
  }) async {
    if (duration.isNotEmpty) {
      try {
        final r = await _db.listDocuments(
          databaseId: Col.dbId,
          collectionId: Col.keys,
          queries: [
            Query.equal('productId', productId),
            Query.equal('status', 'available'),
            Query.equal('duration', duration),
            Query.limit(1),
          ],
        );
        return r.total;
      } catch (_) {
        return -1;
      }
    }
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
    } catch (_) {
      return -1;
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
  /// Safely handles products with thousands of keys and optional duration filter.
  static Future<List<StockEntry>> keysForProduct(
    String productId, {
    String duration = '',
    int limit = 5000,
  }) async {
    if (duration.isNotEmpty) {
      try {
        final r = await _db.listDocuments(
          databaseId: Col.dbId,
          collectionId: Col.keys,
          queries: [
            Query.equal('productId', productId),
            Query.equal('duration', duration),
            Query.orderDesc(r'$createdAt'),
            Query.limit(limit),
          ],
        );
        return r.documents.map(StockEntry.fromDoc).toList();
      } catch (_) {
        // Appwrite may lack an index on `duration` — fallback below queries by productId
      }
    }
    final r = await _db.listDocuments(
      databaseId: Col.dbId,
      collectionId: Col.keys,
      queries: [
        Query.equal('productId', productId),
        Query.orderDesc(r'$createdAt'),
        Query.limit(limit),
      ],
    );
    final all = r.documents.map(StockEntry.fromDoc).toList();
    if (duration.isNotEmpty) {
      return all.where((k) => k.duration == duration).toList();
    }
    return all;
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

  /// Removes stock rows of [productId] straight from the database — queried
  /// in pages of 100 (Appwrite's per-submit cap), not taken from the admin's
  /// shared 200-row window, so a bulk delete leaves nothing behind.
  ///
  /// [usedOnly] limits the sweep to claimed rows; the default clears every
  /// key of the product. [onProgress] reports (rows removed, rows matched).
  ///
  /// Returns how many rows could NOT be deleted (0 = fully clean).
  static Future<int> deleteKeysForProduct(
    String productId, {
    bool usedOnly = false,
    void Function(int done, int total)? onProgress,
  }) async {
    var total = -1;
    try {
      total = await countKeys(productId, usedOnly: usedOnly);
    } catch (_) {
      // Count is cosmetic — a failed tally must not stop the delete.
    }

    var done = 0;
    final failed = <String>{};
    while (true) {
      final r = await _db.listDocuments(
        databaseId: Col.dbId,
        collectionId: Col.keys,
        queries: [
          Query.equal('productId', productId),
          // `claimed` = used. Exact match on purpose: it reuses the
          // `product_status` composite index (like `availableCount`) while
          // deleted rows fall out of the result set on the next pass.
          if (usedOnly) Query.equal('status', 'claimed'),
          Query.limit(100),
        ],
      );
      // Rows that already failed once stay in the result set — drop them so
      // a stubborn row can't loop this page forever.
      final page = r.documents.where((d) => !failed.contains(d.$id)).toList();
      if (page.isEmpty) break;

      var anyRemoved = false;
      await _pooled(page, _stockWidth, (d) async {
        try {
          await _retry(
            () => _db.deleteDocument(
              databaseId: Col.dbId,
              collectionId: Col.keys,
              documentId: d.$id,
            ),
          );
          anyRemoved = true;
          done++;
          onProgress?.call(done, total);
        } catch (_) {
          failed.add(d.$id);
        }
      });
      // Every remaining row failed to delete — don't spin forever.
      if (!anyRemoved) break;
    }
    return failed.length;
  }

  // ---- stock bulk helpers ----

  /// Runs [job] over [items] with at most [width] in flight, pulling the next
  /// item as soon as a worker frees up. Safe for Dart's single-threaded event
  /// loop: the index hand-out between `await`s is never interleaved.
  static Future<void> _pooled<T>(
    List<T> items,
    int width,
    Future<void> Function(T item) job,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next;
        if (i >= items.length) return;
        next = i + 1;
        await job(items[i]);
      }
    }

    await Future.wait([
      for (var i = 0; i < width && i < items.length; i++) worker(),
    ]);
  }

  /// Retries transient failures (rate limit, server error, dead connection)
  /// with a short backoff; everything else — permissions, validation — fails
  /// immediately, since repeating it won't help.
  static Future<T> _retry<T>(
    Future<T> Function() op, {
    int attempts = 4,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await op();
      } on AppwriteException catch (e) {
        final code = e.code ?? 0;
        final transient = code == 429 || code == 0 || code >= 500;
        if (!transient || attempt >= attempts) rethrow;
        final delayMs = code == 429 ? 2000 * attempt : 350 * attempt;
        await Future.delayed(Duration(milliseconds: delayMs));
      }
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
