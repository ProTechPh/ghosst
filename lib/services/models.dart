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

/// One manual announcement: the banner text, and the notification body.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.createdAt = '',
  });

  final String id;
  final String title;
  final String body;
  final String createdAt;

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
      );
}

/// Isang user na naka-mute sa world chat (admin "Muted chat users" list).
/// Ang list ay nasa Admin screen — hindi depende sa chat messages na
/// mag-e-expire, kaya laging may paraan mag-unmute.
class MutedUser {
  const MutedUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory MutedUser.fromJson(Map<String, dynamic> json) => MutedUser(
        id: json['id'] as String? ?? '',
        name: json['displayName'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}

/// Isang banned word sa auto-moderation.
class BannedWord {
  const BannedWord({required this.id, required this.word});

  final int id;
  final String word;

  factory BannedWord.fromJson(Map<String, dynamic> json) => BannedWord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        word: json['word'] as String? ?? '',
      );
}

/// Ang moderation settings: block links ba, at gaano katagal ang auto-mute.
class Moderation {
  const Moderation({this.blockLinks = false, this.muteHours = 24});

  final bool blockLinks;
  final int muteHours;

  factory Moderation.fromJson(Map<String, dynamic> json) => Moderation(
        blockLinks: json['blockLinks'] as bool? ?? false,
        muteHours: (json['muteHours'] as num?)?.toInt() ?? 24,
      );
}

/// Null when there is nothing to show or the user already closed this one.
Announcement? unreadAnnouncement(Announcement? a, String dismissedId) =>
    (a == null || a.id == dismissedId) ? null : a;

/// One purchasable duration for a premium version (e.g. `3 Days` @ ₱150).
class ShopDuration {
  const ShopDuration({
    required this.label,
    required this.price,
    required this.stock,
    required this.currency,
  });

  factory ShopDuration.fromJson(Map<String, dynamic> json, String currency) =>
      ShopDuration(
        label: json['label'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        stock: (json['stock'] as num?)?.toInt() ?? 0,
        currency: currency,
      );

  final String label;
  final double price;
  final int stock;
  final String currency;

  bool get soldOut => stock <= 0;
  String get priceLabel => shopPriceLabel(currency, price, price);
}

/// One version in the website premium shop (a game key, priced in ₱).
/// Read-only: the app never buys these; [url] opens the site's checkout page.
class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.name,
    required this.platform,
    required this.price,
    required this.priceMax,
    required this.stock,
    required this.currency,
    required this.image,
    required this.url,
    this.description = '',
    this.details = '',
    this.gallery = const [],
    this.durations = const [],
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String? ?? '₱';
    return ShopProduct(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      priceMax: (json['priceMax'] as num?)?.toDouble() ?? 0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      currency: currency,
      image: json['image'] as String? ?? '',
      url: json['url'] as String? ?? '',
      description: json['description'] as String? ?? '',
      details: json['details'] as String? ?? '',
      gallery: (json['gallery'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      durations: (json['durations'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((j) => ShopDuration.fromJson(j, currency))
          .toList(),
    );
  }

  final int id;
  final String name;
  final String platform;
  final double price;
  final double priceMax;
  final int stock;
  final String currency;
  final String image;
  final String url;

  /// Filled by the detail endpoint; empty on list rows.
  final String description;
  final String details;
  final List<String> gallery;
  final List<ShopDuration> durations;

  String get priceLabel => shopPriceLabel(currency, price, priceMax);

  /// `Android`, `iOS`, or `Android + iOS`.
  String get platformLabel => switch (platform) {
    'ios' => 'iOS',
    'both' => 'Android + iOS',
    _ => 'Android',
  };
}

/// One game category on the website premium shop, with its image carousel.
class ShopGame {
  const ShopGame({
    required this.name,
    required this.slug,
    required this.description,
    required this.image,
    required this.images,
    required this.price,
    required this.priceMax,
    required this.stock,
    required this.currency,
    required this.products,
  });

  factory ShopGame.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String? ?? '₱';
    return ShopGame(
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      description: json['description'] as String? ?? '',
      image: json['image'] as String? ?? '',
      images: (json['images'] as List? ?? const []).whereType<String>().toList(),
      price: (json['price'] as num?)?.toDouble() ?? 0,
      priceMax: (json['priceMax'] as num?)?.toDouble() ?? 0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      currency: currency,
      products: (json['products'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((j) => ShopProduct.fromJson({...j, 'currency': currency}))
          .toList(),
    );
  }

  final String name;
  final String slug;
  final String description;

  /// Hero image, or the first product image when the game has no hero.
  final String image;

  /// Carousel: the game hero followed by its product images (max 8).
  final List<String> images;

  final double price;
  final double priceMax;
  final int stock;
  final String currency;
  final List<ShopProduct> products;

  String get priceLabel => shopPriceLabel(currency, price, priceMax);
}

/// Rolling 24h reward budget from `GET /v1/ads/status` (advisory only —
/// the SSV handler still owns crediting).
class AdsRewardStatus {
  const AdsRewardStatus({
    required this.rewardsToday,
    required this.limit,
    required this.remaining,
    required this.nextRewardIn,
  });

  final int rewardsToday;
  final int limit;
  final int remaining;

  /// Seconds until the 15s pacing gap clears (0 = ready now).
  final int nextRewardIn;

  bool get atCap => remaining <= 0;
}

/// Server-driven update gate (`GET /v1/app/config`).
class AppConfig {
  const AppConfig({
    required this.minVersionCode,
    required this.latestVersionCode,
    required this.playUrl,
    required this.directUrl,
  });

  final int minVersionCode;
  final int latestVersionCode;
  final String playUrl;
  final String directUrl;

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        minVersionCode: (json['minVersionCode'] as num?)?.toInt() ?? 0,
        latestVersionCode: (json['latestVersionCode'] as num?)?.toInt() ?? 0,
        playUrl: json['playUrl'] as String? ?? '',
        directUrl: json['directUrl'] as String? ?? '',
      );

  /// True when this install must update before it can be used. A min of 0
  /// means the gate is off (nothing published yet).
  bool blocks(int installedVersionCode) =>
      minVersionCode > 0 && installedVersionCode < minVersionCode;

  /// Store link for the current distribution.
  String updateUrl({required bool isPlay}) =>
      isPlay || directUrl.isEmpty ? playUrl : directUrl;
}

/// `₱620`, `₱99.50`, or `₱620 – ₱1,200` when keys are priced differently.
String shopPriceLabel(String currency, double price, double priceMax) {
  String money(double v) {
    final digits = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2);
    return digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
  }

  final low = '$currency${money(price)}';
  return priceMax > price ? '$low – $currency${money(priceMax)}' : low;
}
