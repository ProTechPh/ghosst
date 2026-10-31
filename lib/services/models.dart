// Data the screens render. Nothing here reaches the network.

/// One selectable duration option for a key product (e.g. `1 Hour` @ 10
/// coins). The Worker stores these as JSON on the product.
class ProductDuration {
  const ProductDuration({required this.label, required this.cost});

  final String label;
  final int cost;
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
  /// claims at its flat [cost].
  final List<ProductDuration> durations;

  ProductType get productType => productTypeOf(type);
  bool get isKey => productType == ProductType.key;
  bool get isApk => productType == ProductType.apk;
  bool get isFile => productType == ProductType.file;

  /// True when buying unlocks a MediaFire download instead of a license key.
  bool get isDownloadable => !isKey;

  /// True when the admin gave this key product duration options.
  bool get hasDurations => durations.isNotEmpty;
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
    this.sha256,
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

  /// Lowercase hex SHA-256 of the file for download claims, when the server
  /// has one. Null for legacy MediaFire links — those downloads are unverified.
  final String? sha256;

  /// Download claims never carry a link in `keyText`; the Worker stores the
  /// product type there instead. The URL can be missing when its ticket fails.
  bool get isDownload =>
      downloadUrl.isNotEmpty ||
      keyText == 'app' ||
      keyText == 'apk' ||
      keyText == 'file';
}

class AdReward {
  AdReward({required this.reward, required this.createdAt});

  final int reward;
  final String createdAt;
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

  /// Filled in by the claim route once the key leaves the stock.
  final String claimedBy;
  final String claimedAt;

  /// Duration pool this key belongs to (`''` = classic flat-cost stock).
  final String duration;

  bool get claimed => status != 'available';
}

/// Outcome of a bulk stock write.
///
/// The bulk insert is not all-or-nothing — rows land in batches — so a paste
/// can partially succeed. The admin panel shows the split instead of
/// pretending the whole submit worked (or didn't).
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
