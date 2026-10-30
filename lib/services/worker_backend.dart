import 'dart:convert';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'api_backend.dart';
import 'backend.dart';
import 'session_store.dart';

// The screens talk to `Backend`. Swapping this file's import for
// `services/backend.dart` puts them back on Appwrite.
export 'backend.dart'
    show
        AdReward,
        Claim,
        Product,
        ProductDuration,
        ProductType,
        StockEntry,
        StockWriteResult,
        productTypeOf;

/// The signed-in account, as much of it as the UI shows.
class AppUser {
  const AppUser({required this.id, required this.email, required this.name});

  final String id;
  final String email;
  final String name;
}

/// Same surface as the Appwrite `Backend`, served by the `ghosst-api` Worker.
class Backend {
  Backend._();

  static const stockChunkSize = 100;

  static final SessionStore _session = SessionStore();
  static final ApiClient _api = ApiClient(session: _session);
  static final ApiBackend _apiBackend = ApiBackend(_api);

  static AppUser? _user;
  static bool? _isAdmin;

  /// Set once by main.dart: the refresh token died, go back to sign-in.
  static set onSignedOut(void Function()? cb) => _api.onSignedOut = cb;

  // ---- session ----

  static Future<AppUser?> currentUser() async {
    final cached = _user;
    if (cached != null) return cached;
    if (await _session.accessToken() == null) return null;
    try {
      return _user = await _me();
    } on ApiException {
      return null;
    }
  }

  static Future<void> signIn(String email, String password) =>
      _startSession('/auth/login', {'email': email, 'password': password});

  static Future<void> signUp(String email, String password, {String name = ''}) =>
      _startSession('/auth/register', {
        'email': email,
        'password': password,
        if (name.isNotEmpty) 'displayName': name,
      });

  static Future<void> _startSession(String path, Map<String, dynamic> body) async {
    final res = await _api.post(path, data: body);
    await _session.write(
      accessToken: res['accessToken'] as String,
      refreshToken: res['refreshToken'] as String,
    );
    _user = null;
    _isAdmin = null;
  }

  static Future<void> signOut() async {
    await _api.logout();
    _user = null;
    _isAdmin = null;
  }

  static Future<void> deleteAccount() async {
    await _api.delete('/account', data: {'confirm': 'DELETE'});
    await _session.clear();
    _user = null;
    _isAdmin = null;
  }

  static Future<AppUser> _me() async {
    final u = (await _api.get('/me'))['user'] as Map<String, dynamic>;
    return AppUser(
      id: u['id'] as String,
      email: u['email'] as String? ?? '',
      name: u['displayName'] as String? ?? '',
    );
  }

  static Future<bool> isAdmin() async {
    final cached = _isAdmin;
    if (cached != null) return cached;
    try {
      final u = (await _api.get('/me'))['user'] as Map<String, dynamic>;
      return _isAdmin = u['isAdmin'] as bool? ?? false;
    } on ApiException {
      return false;
    }
  }

  // ---- profile ----

  static Future<int> coins() async {
    if (await _session.accessToken() == null) return 0;
    try {
      return (await _api.get('/wallet'))['coins'] as int? ?? 0;
    } on ApiException {
      return 0;
    }
  }

  // ---- store ----

  static Future<List<Product>> products() async =>
      (await _apiBackend.products()).map(_product).toList();

  static Future<List<Product>> allProducts() async {
    final res = await _api.get('/products', query: {'all': '1'});
    return (res['products'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((j) => _product(ApiProduct.fromJson(j)))
        .toList();
  }

  static Future<Product?> product(String productId) async {
    try {
      return _product(await _apiBackend.product(productId));
    } on ApiException {
      return null;
    }
  }

  static String productThumbUrl(List<String> imageIds) =>
      imageIds.isEmpty ? '' : imageUrl(imageIds.first, width: 400);

  static Future<int> availableCount(String productId) async {
    try {
      return (await _apiBackend.product(productId)).availableCount;
    } on ApiException {
      return -1;
    }
  }

  static Future<String> claim(String productId, {String duration = ''}) async {
    final res = await _apiBackend.claim(productId, duration: duration);
    final key = res['key'] as String?;
    if (key == null || key.isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: 'Walang key sa sagot ng server',
      );
    }
    return key;
  }

  static Future<String> claimApp(String productId) async {
    final res = await _apiBackend.claim(productId);
    final url = res['downloadUrl'] as String?;
    if (url == null || url.trim().isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.conflict,
        message: 'Wala pang download link ang produktong ito.',
      );
    }
    return url;
  }

  static Future<bool> owns(String productId) async =>
      (await myClaims()).any((c) => c.productId == productId);

  static Future<Set<String>> ownedProductIds() async =>
      (await myClaims()).map((c) => c.productId).toSet();

  // ---- history ----

  static Future<List<Claim>> myClaims() async {
    if (await _session.accessToken() == null) return [];
    try {
      final raw = await _apiBackend.myClaims();
      final out = <Claim>[];
      for (final c in raw) {
        // The claim row never carries the link; ask for a fresh one instead.
        var url = '';
        if (c.isDownload) {
          try {
            url = (await _apiBackend.downloadTicket(c.productId)).url;
          } on ApiException {
            url = '';
          }
        }
        out.add(_claim(c, url));
      }
      return out;
    } on ApiException {
      return [];
    }
  }

  static Future<List<AdReward>> myAdRewards() async {
    if (await _session.accessToken() == null) return [];
    try {
      final res = await _api.get('/wallet');
      return (res['rewards'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (r) => AdReward(
              reward: (r['reward'] as num?)?.toInt() ?? 0,
              createdAt: r['createdAt'] as String? ?? '',
            ),
          )
          .toList();
    } on ApiException {
      return [];
    }
  }

  // ---- stock (admin) ----

  static Future<StockWriteResult> addKeys({
    required String productId,
    required List<String> keys,
    String duration = '',
    bool skipExisting = true,
    void Function(int done, int total, String? status)? onProgress,
  }) async {
    final clean = <String>[];
    final seen = <String>{};
    for (final raw in keys) {
      final k = raw.trim();
      if (k.isNotEmpty && seen.add(k)) clean.add(k);
    }
    final inBatchSkipped = keys.length - clean.length;

    var added = 0;
    var skipped = inBatchSkipped;
    var done = 0;
    for (var i = 0; i < clean.length; i += 500) {
      final chunk = clean.sublist(i, (i + 500).clamp(0, clean.length));
      final res = await _api.post(
        '/admin/keys',
        data: {
          'productId': productId,
          'keys': chunk,
          if (duration.isNotEmpty) 'duration': duration,
        },
      );
      added += (res['added'] as num?)?.toInt() ?? 0;
      skipped += (res['skipped'] as num?)?.toInt() ?? 0;
      done += chunk.length;
      onProgress?.call(done, clean.length, null);
    }
    return StockWriteResult(added: added, failed: 0, skipped: skipped);
  }

  static Future<int> countKeys(String productId, {bool usedOnly = false}) async {
    final rows = await _adminKeys(productId: productId, status: usedOnly ? 'claimed' : '');
    return rows.length;
  }

  static Future<int> countAvailableKeys(String productId, {String duration = ''}) async {
    final rows = await _adminKeys(productId: productId, status: 'available');
    return duration.isEmpty ? rows.length : rows.where((k) => k.duration == duration).length;
  }

  static Future<List<StockEntry>> listKeys() => _adminKeys();

  static Future<List<StockEntry>> listAvailableKeys() => _adminKeys(status: 'available');

  static Future<List<StockEntry>> keysForProduct(
    String productId, {
    String duration = '',
    int limit = 5000,
  }) async {
    final rows = await _adminKeys(productId: productId, limit: limit);
    return duration.isEmpty ? rows : rows.where((k) => k.duration == duration).toList();
  }

  static Future<int> availableStock() async =>
      (await _adminKeys(status: 'available', limit: 5000)).length;

  static Future<List<StockEntry>> _adminKeys({
    String productId = '',
    String status = '',
    int limit = 5000,
  }) async {
    final res = await _api.get(
      '/admin/keys',
      query: {
        if (productId.isNotEmpty) 'productId': productId,
        if (status.isNotEmpty) 'status': status,
        'limit': '$limit',
      },
    );
    return (res['keys'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (k) => StockEntry(
            keyId: _pick(k, 'id'),
            productId: _pick(k, 'productId', 'product_id'),
            keyText: _pick(k, 'key', 'key_value'),
            status: _pick(k, 'status'),
            claimedBy: _pick(k, 'claimedBy', 'claimed_by'),
            claimedAt: _pick(k, 'claimedAt', 'claimed_at'),
            duration: _pick(k, 'duration'),
          ),
        )
        .toList();
  }

  // ---- products (admin) ----

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
    final res = await _api.post('/products', data: {
      'name': name,
      'cost': cost,
      'description': description,
      'youtubeUrl': youtubeUrl,
      'type': type,
      'version': version,
      'fileSize': fileSize,
      if (imageIds.isNotEmpty) 'imageKeys': imageIds,
      if (durations.isNotEmpty) 'durations': _durations(durations),
    });
    final id = res['id'] ?? (res['product'] as Map?)?['id'];
    if (id is! String || id.isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: 'Walang id sa sagot ng server',
      );
    }
    return id;
  }

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
  }) =>
      _api.patch('/products/$productId', data: {
        'name': name,
        'cost': cost,
        'description': description,
        'youtubeUrl': youtubeUrl,
        'imageKeys': imageIds,
        'type': type,
        'version': version,
        'fileSize': fileSize,
        'durations': _durations(durations),
      });

  static Future<void> setProductActive(String productId, bool active) =>
      _api.patch('/products/$productId', data: {'active': active});

  static Future<void> deleteProduct(String productId) => _api.delete('/products/$productId');

  // ---- download link (admin) ----

  static Future<String> appFileFor(String productId) async {
    try {
      final p = (await _api.get('/products/$productId'))['product'] as Map<String, dynamic>;
      return p['fileUrl'] as String? ?? '';
    } on ApiException {
      return '';
    }
  }

  static Future<void> upsertAppFile(String productId, String url) async {
    final link = url.trim();
    if (link.isEmpty) return;
    await _api.patch('/products/$productId', data: {'fileUrl': link});
  }

  static Future<void> deleteAppFile(String productId) =>
      _api.patch('/products/$productId', data: {'fileUrl': ''});

  // ---- images ----

  /// Images are links: an absolute URL, or a key the CDN will complete.
  static String imageUrl(String fileId, {int width = 900}) => fileId;

  static Future<void> deleteKey(String keyId) => _api.delete('/admin/keys/$keyId');

  static Future<int> deleteKeysForProduct(
    String productId, {
    bool usedOnly = false,
    void Function(int done, int total)? onProgress,
  }) async {
    var total = 0;
    try {
      total = await countKeys(productId, usedOnly: usedOnly);
    } catch (_) {}
    // The Worker route clears the whole stock; used-only deletes row by row.
    if (usedOnly) {
      final rows = await _adminKeys(productId: productId, status: 'claimed');
      for (final k in rows) {
        await deleteKey(k.keyId);
      }
    } else {
      await _api.delete('/admin/products/$productId/keys');
    }
    onProgress?.call(total, total);
    return 0;
  }

  // ---- mapping ----

  static Product _product(ApiProduct p) => Product(
        id: p.id,
        name: p.name,
        cost: p.cost,
        active: p.active,
        description: p.description,
        imageIds: p.imageUrls,
        youtubeUrl: p.youtubeUrl,
        type: p.type,
        version: p.version,
        fileSize: p.fileSize,
        durations: p.durations
            .map((d) => ProductDuration(label: d.label, cost: d.cost))
            .toList(),
      );

  static Claim _claim(ApiClaim c, String downloadUrl) => Claim(
        id: c.id,
        productId: c.productId,
        productName: c.productName,
        keyText: c.keyText,
        cost: c.cost,
        createdAt: c.createdAt?.toIso8601String() ?? '',
        downloadUrl: downloadUrl,
        duration: c.duration,
      );

  /// The admin UI still hands durations over as a JSON string.
  static List<Map<String, dynamic>> _durations(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final v = jsonDecode(raw);
      return v is List ? v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  static String _pick(Map<String, dynamic> m, String camel, [String? snake]) =>
      (m[camel] ?? (snake == null ? null : m[snake]) ?? '') as String;
}
