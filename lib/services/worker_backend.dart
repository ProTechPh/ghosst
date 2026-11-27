import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exception.dart';
import 'api_backend.dart';
import 'models.dart';
import 'session_store.dart';

// The screens import this file and keep using `Backend` + the models below,
// which are re-exported so a screen needs only one import.
export 'models.dart';

/// Fixed reward credited by the API when a referral code is claimed.
const int referralReward = 100;

/// The signed-in account, as much of it as the UI shows.
enum BackendSessionState { live, unknown, revoked }

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.photoUrl,
    this.createdAt = '',
    this.chatMuted = false,
    this.referralCode = '',
  });

  final String id;
  final String email;
  final String name;
  final String? photoUrl;
  final String createdAt;
  final bool chatMuted;
  final String referralCode;
}

/// Same surface the screens already used, served by the `ghosst-api` Worker.
class Backend {
  Backend._();

  static final SessionStore _session = SessionStore();
  static final ApiClient _api = ApiClient(session: _session);
  static final ApiBackend _apiBackend = ApiBackend(_api);

  static AppUser? _user;
  static DateTime? _userCheckedAt;
  static bool? _isAdmin;
  static bool? _isModerator;
  static bool? _chatMuted;

  /// Set once by main.dart: the refresh token died, go back to sign-in.
  static set onSignedOut(void Function()? cb) => _api.onSignedOut = cb;

  // ---- session ----

  static AppUser? get cachedUser => _user;

  static const _sessionCacheTtl = Duration(minutes: 5);

  static Future<AppUser?> currentUser() async {
    final status = await sessionStatus();
    return status.user;
  }

  /// Live = verified recently; unknown = transient failure (keep Firebase
  /// cache); revoked = definitive authentication rejection.
  static Future<({BackendSessionState state, AppUser? user})> sessionStatus({
    bool refresh = false,
  }) async {
    final cached = _user;
    final checkedAt = _userCheckedAt;
    final now = DateTime.now();
    if (!refresh &&
        cached != null &&
        checkedAt != null &&
        now.difference(checkedAt) < _sessionCacheTtl) {
      return (state: BackendSessionState.live, user: cached);
    }
    if (await _session.accessToken() == null) {
      return (state: BackendSessionState.revoked, user: null);
    }
    try {
      final user = await _me();
      _user = user;
      _userCheckedAt = DateTime.now();
      return (state: BackendSessionState.live, user: user);
    } on ApiException catch (e) {
      return (
        state: sessionStateAfterError(e, hasCachedUser: cached != null),
        user: cached,
      );
    }
  }

  static BackendSessionState sessionStateAfterError(
    ApiException? error, {
    required bool hasCachedUser,
  }) {
    if (error == null) return BackendSessionState.live;
    if (error.kind == ApiErrorKind.unauthorized ||
        error.kind == ApiErrorKind.forbidden) {
      return BackendSessionState.revoked;
    }
    return BackendSessionState.unknown;
  }

  static Future<void> signIn(String email, String password) =>
      _startSession('/auth/login', {'email': email, 'password': password});

  /// Google ang ID token; ang server ang nagbe-verify at gumagawa ng account
  /// kung wala pa sa email.
  static Future<void> signInWithGoogle(
    String idToken, {
    String? photoUrl,
  }) async {
    await _startSession('/auth/google', {
      'idToken': idToken,
      if (photoUrl != null && photoUrl.trim().isNotEmpty)
        'photoUrl': photoUrl.trim(),
    });
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      await _session.writePhotoUrl(photoUrl.trim());
    }
  }

  static Future<String?> photoUrl() => _session.photoUrl();

  static Future<void> setPhotoUrl(String? url) async {
    await _session.writePhotoUrl(url);
    _user = null;
  }

  static Future<void> _startSession(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _api.post(path, data: body);
    await _session.write(
      accessToken: res['accessToken'] as String,
      refreshToken: res['refreshToken'] as String,
    );
    _user = null;
    _userCheckedAt = null;
    _isAdmin = null;
    _isModerator = null;
    _chatMuted = null;
  }

  static Future<void> signOut() async {
    await _api.logout();
    _user = null;
    _userCheckedAt = null;
    _isAdmin = null;
    _isModerator = null;
    _chatMuted = null;
  }

  /// Custom token para sa world chat (503 `chat_disabled` kapag hindi
  /// naka-setup ang service account sa API).
  static Future<String> firebaseToken() async =>
      (await _api.get('/firebase/token'))['token'] as String;

  /// Admin product image → the site's FTP storage (uploads/products).
  static Future<String> updateBio(String bio, {String? cover}) async {
    final data = <String, dynamic>{'bio': bio.trim()};
    if (cover != null) data['cover'] = cover;
    final res = await _api.post('/me/profile', data: data);
    return (res['coverUrl'] ?? res['bio'] ?? '').toString();
  }

  static Future<String> uploadCover(String path) async {
    final form = FormData.fromMap({'image': MultipartFile.fromFileSync(path)});
    final res = await _api.post('/uploads/cover', data: form);
    final url = res['url'] as String?;
    return ApiConfig.publicUrl(
      (url != null && url.isNotEmpty ? url : res['path']) as String,
    );
  }

  static Future<String> uploadProductImage(String path) async {
    final form = FormData.fromMap({'image': MultipartFile.fromFileSync(path)});
    final res = await _api.post('/uploads/product-image', data: form);
    final url = res['url'] as String?;
    return (url != null && url.isNotEmpty ? url : res['path']) as String;
  }

  static Future<void> deleteAccount() async {
    await _api.delete('/account', data: {'confirm': 'DELETE'});
    await _session.clear();
    _user = null;
    _userCheckedAt = null;
    _isAdmin = null;
    _isModerator = null;
    _chatMuted = null;
  }

  static Future<AppUser> _me() async {
    final u = (await _api.get('/me'))['user'] as Map<String, dynamic>;
    _isAdmin = u['isAdmin'] as bool? ?? false;
    _isModerator = u['isModerator'] as bool? ?? false;
    _chatMuted = u['chatMuted'] as bool? ?? false;
    final photo = await _session.photoUrl();
    return AppUser(
      id: u['id'] as String,
      email: u['email'] as String? ?? '',
      name: u['displayName'] as String? ?? '',
      photoUrl: photo,
      createdAt: u['createdAt'] as String? ?? '',
      chatMuted: _chatMuted!,
      referralCode: u['referralCode'] as String? ?? '',
    );
  }

  /// Reuses the cached `/me` payload: two parallel calls on launch meant two
  /// DB connections per open, and Hostinger caps them per account.
  static Future<bool> isAdmin() async {
    final cached = _isAdmin;
    if (cached != null) return cached;
    try {
      await currentUser();
      return _isAdmin ?? false;
    } on ApiException {
      return false;
    }
  }

  static Future<bool> isModerator() async {
    final cached = _isModerator;
    if (cached != null) return cached;
    try {
      await currentUser();
      return _isModerator ?? false;
    } on ApiException {
      return false;
    }
  }

  /// Mute status sa world chat, mula sa cached `/me` payload (tulad ng isAdmin).
  /// Ang `refresh: true` ay binubura ang cache para sa totoong status ngayon —
  /// kailangan kapag pwedeng nagbago ang mute habang naka-bukas ang app.
  static Future<bool> chatMuted({bool refresh = false}) async {
    if (refresh) {
      _user = null;
      _userCheckedAt = null;
      _chatMuted = null;
    }
    final cached = _chatMuted;
    if (cached != null) return cached;
    try {
      await currentUser();
      return _chatMuted ?? false;
    } on ApiException {
      return false;
    }
  }

  /// Admin: i-mute/unmute ang isang user sa world chat.
  static Future<void> setChatMuted(String userId, bool muted) async {
    await _api.post(
      '/admin/chat/mute',
      data: {'userId': userId, 'muted': muted},
    );
  }

  /// Admin: lahat ng users na naka-mute sa world chat (para sa Admin screen).
  static Future<List<MutedUser>> mutedUsers() async {
    final res = await _api.get('/admin/chat/muted');
    return (res['users'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MutedUser.fromJson)
        .toList();
  }

  /// Admin: ang banned word list para sa auto-moderation.
  static Future<List<BannedWord>> bannedWords() async {
    final res = await _api.get('/admin/banned-words');
    return (res['words'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BannedWord.fromJson)
        .toList();
  }

  /// Admin: magdagdag ng banned word.
  static Future<void> addBannedWord(String word) async {
    await _api.post('/admin/banned-words', data: {'word': word});
  }

  /// Admin: tanggalin ang banned word.
  static Future<void> deleteBannedWord(int id) async {
    await _api.delete('/admin/banned-words/$id');
  }

  /// Admin: moderation settings (block links + mute duration).
  static Future<Moderation> moderation() async {
    final res = await _api.get('/admin/moderation');
    return Moderation.fromJson(res);
  }

  /// Admin: i-save ang moderation settings.
  static Future<void> saveModeration({
    required bool blockLinks,
    required int muteHours,
  }) async {
    await _api.post(
      '/admin/moderation',
      data: {'blockLinks': blockLinks, 'muteHours': muteHours},
    );
  }

  // ---- profile ----

  static Future<int> coins() async {
    if (await _session.accessToken() == null) return 0;
    try {
      return (await _api.get('/wallet'))['coins'] as int? ?? 0;
    } on ApiException catch (e) {
      // A blip must not read as "0 coins" — that flips the UI to "not enough".
      if (_transient(e)) rethrow;
      return 0;
    }
  }

  /// Client-side mirror of the API's accepted code format. Legacy codes may
  /// contain 0/1 or lack the REF- prefix; empty string means invalid.
  static String normalizeReferralCode(String input) {
    final code = input.trim().toUpperCase();
    return RegExp(r'^(REF-)?[A-Z0-9]{4,12}$').hasMatch(code) ? code : '';
  }

  /// Share copy for the Profile share button: store link + invitation + code.
  static String referralInviteText({
    required String referralCode,
    required bool isPlay,
  }) {
    final url = isPlay
        ? 'https://play.google.com/store/apps/details?id=com.astrixtech.ghosst'
        : 'https://ghossthub.com';
    // Display the code exactly as stored — older accounts may not have the
    // REF- prefix, and a strict filter would silently drop it from invites.
    final code = referralCode.trim();
    final text = StringBuffer(
      'Try Ghosst — earn coins from ads and unlock license keys and apps!\n'
      'Download: $url',
    );
    if (code.isNotEmpty) text.writeln('\nUse my referral code: $code');
    return text.toString();
  }

  /// The invitee claims someone else's code; the API credits that referrer.
  static Future<int> claimReferral(String code) async {
    final res = await _api.post('/me/referral', data: {'code': normalizeReferralCode(code)});
    return res['reward'] as int? ?? referralReward;
  }

  /// Remaining reward budget for the rolling 24h window. Advisory: the SSV
  /// handler still decides whether a callback is credited.
  static Future<AdsRewardStatus> adsRewardStatus() async {
    final res = await _api.get('/ads/status');
    return AdsRewardStatus(
      rewardsToday: res['rewards_today'] as int? ?? 0,
      limit: res['limit'] as int? ?? 50,
      remaining: res['remaining'] as int? ?? 50,
      nextRewardIn: res['next_reward_in'] as int? ?? 0,
      coinsPerReward: res['coins_per_reward'] as int? ?? 10,
    );
  }

  /// Sends a Play Integrity token for server-side decoding. Observe-only —
  /// the caller swallows failures.
  static Future<void> reportIntegrity(String token, String nonce) async {
    await _api.post('/integrity/check', data: {'token': token, 'nonce': nonce});
  }

  /// Update gate config. Null on any failure — the caller must fail open.
  static Future<AppConfig?> appConfig() async {
    try {
      return AppConfig.fromJson(await _api.get('/app/config'));
    } catch (_) {
      return null;
    }
  }

  /// Website tutorials; a failure reads as "none", never an error screen.
  static Future<List<Tutorial>> tutorials() async {
    try {
      final res = await _api.get('/tutorials');
      final list = res['tutorials'];
      if (list is! List) return const [];
      return [
        for (final t in list)
          if (t is Map<String, dynamic>) Tutorial.fromJson(t),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Top coin holders leaderboard (`GET /v1/leaderboard`).
  static Future<List<LeaderboardEntry>> leaderboard() async {
    try {
      final res = await _api.get('/leaderboard');
      final list = res['leaderboard'];
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map<String, dynamic>) LeaderboardEntry.fromJson(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Safe user search for starting a private conversation.
  static Future<List<ChatUserSummary>> searchUsers(String query) async {
    final res = await _api.get('/users/search', query: {'q': query});
    return (res['users'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatUserSummary.fromJson)
        .toList();
  }

  static Future<ChatUserSummary> chatUser(String id) async {
    final res = await _api.get('/users/$id');
    return ChatUserSummary.fromJson(res['user'] as Map<String, dynamic>);
  }

  static Future<PublicUser> publicUser(String id) async {
    final res = await _api.get('/users/$id');
    return PublicUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  static Future<FollowState> followUser(String id) async {
    final res = await _api.post('/users/$id/follow');
    return FollowState.fromJson(res);
  }

  static Future<FollowState> unfollowUser(String id) async {
    final res = await _api.deleteMap('/users/$id/follow');
    return FollowState.fromJson(res);
  }

  static Future<List<PublicUser>> followers(
    String id, {
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _api.get(
      '/users/$id/followers',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return publicUsersFromJson(res['users']);
  }

  static Future<List<PublicUser>> following(
    String id, {
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _api.get(
      '/users/$id/following',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return publicUsersFromJson(res['users']);
  }

  static Future<List<ChatUserSummary>> chatUsers(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final res = await _api.post('/users/summaries', data: {'ids': ids});
    return (res['users'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatUserSummary.fromJson)
        .toList();
  }

  static Future<String> submitFeedback({
    required String comment,
    required int rating,
    required String idempotencyKey,
  }) async {
    final res = await _api.post(
      '/feedback',
      data: {'comment': comment.trim(), 'rating': rating},
      headers: {'idempotency-key': idempotencyKey},
    );
    return (res['feedbackId'] ?? '').toString();
  }

  static Future<List<WebsiteFeedback>> publicFeedback() async {
    final res = await _api.get('/feedback/public');
    return (res['feedbacks'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(WebsiteFeedback.fromJson)
        .toList();
  }

  static Future<List<AppFeedback>> myFeedback({
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _api.get(
      '/feedback/mine',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return (res['feedbacks'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AppFeedback.fromJson)
        .toList();
  }

  static Future<ReelUploadTicket> startReelUpload({
    required String caption,
    required List<Map<String, dynamic>> images,
    required String idempotencyKey,
  }) async {
    final res = await _api.post(
      '/reels/uploads',
      data: {'caption': caption, 'images': images},
      headers: {'idempotency-key': '$idempotencyKey-init'},
    );
    return ReelUploadTicket.fromJson(res);
  }

  static Future<void> completeReelUpload({
    required String reelId,
    required List<Map<String, dynamic>> images,
    required String idempotencyKey,
  }) async {
    await _api.post(
      '/reels/$reelId/complete',
      data: {'images': images},
      headers: {'idempotency-key': '$idempotencyKey-complete'},
    );
    await _api.get('/reels/$reelId');
  }

  static Future<void> deleteReel(String id) => _api.delete('/reels/$id');

  static Future<ReelFeedPage> reels({
    String feed = 'for-you',
    int limit = 10,
    int offset = 0,
  }) async {
    final res = await _api.get(
      '/reels',
      query: {'feed': feed, 'limit': '$limit', 'offset': '$offset'},
    );
    return ReelFeedPage.fromJson(res);
  }

  static Future<({bool isLiked, int likeCount})> likeReel(String id) async {
    final res = await _api.post('/reels/$id/likes');
    return (
      isLiked: res['isLiked'] == true,
      likeCount: (res['likeCount'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<({bool isLiked, int likeCount})> unlikeReel(String id) async {
    final res = await _api.deleteMap('/reels/$id/likes');
    return (
      isLiked: res['isLiked'] == true,
      likeCount: (res['likeCount'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<List<ReelComment>> reelComments(
    String id, {
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _api.get(
      '/reels/$id/comments',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return (res['comments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReelComment.fromJson)
        .toList();
  }

  static Future<void> postReelComment(String id, String text) =>
      _api.post('/reels/$id/comments', data: {'text': text});

  static Future<void> deleteReelComment(String reelId, String commentId) =>
      _api.delete('/reels/$reelId/comments/$commentId');

  static Future<List<Reel>> userReels(
    String id, {
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _api.get(
      '/users/$id/reels',
      query: {'limit': '$limit', 'offset': '$offset'},
    );
    return (res['reels'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Reel.fromJson)
        .toList();
  }

  static String newIdempotencyKey() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
    String? snapshot,
    String? threadId,
  }) => _api.post(
    '/reports',
    data: {
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'details': details,
      'snapshot': ?snapshot,
      'threadId': ?threadId,
    },
  );

  /// API read markers use `Y-m-d H:i:s` UTC, not Dart's ISO-8601 string.
  static String readTimestamp(String value) {
    final text = value.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(text)) {
      return text;
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return '';
    final utc = parsed.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
        '${two(utc.day)} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  }

  /// Server-owned read markers. Null when signed out or the call fails.
  static Future<({String announcementsSeenAt, int chatSeenAtMs})?>
  reads() async {
    try {
      if (await _session.accessToken() == null) return null;
      final res = await _api.get('/reads');
      return (
        announcementsSeenAt: readTimestamp(
          res['announcementsSeenAt'] as String? ?? '',
        ),
        chatSeenAtMs: (res['chatSeenAtMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Advances the account's markers. Best effort: a failure keeps the local
  /// copy and retries on the next mark/sync.
  static Future<void> markReads({
    String? announcementsSeenAt,
    int? chatSeenAtMs,
  }) async {
    try {
      if (await _session.accessToken() == null) return;
      final seen = announcementsSeenAt == null
          ? null
          : readTimestamp(announcementsSeenAt);
      await _api.post(
        '/reads',
        data: {
          if (seen != null && seen.isNotEmpty) 'announcementsSeenAt': seen,
          'chatSeenAtMs': ?chatSeenAtMs,
        },
      );
    } catch (_) {
      // Best effort.
    }
  }

  /// Failures where the screen should keep showing what it had.
  static bool _transient(ApiException e) =>
      e.kind == ApiErrorKind.network ||
      e.kind == ApiErrorKind.timeout ||
      e.kind == ApiErrorKind.server ||
      e.kind == ApiErrorKind.rateLimited ||
      e.kind == ApiErrorKind.quotaExceeded;

  // ---- store ----

  static Future<List<Product>> products() async =>
      (await _apiBackend.products()).map(_product).toList();

  /// Website premium shop (read-only; buying finishes on ghossthub.com).
  static Future<List<ShopGame>> premiumShop() async {
    final res = await _api.get('/premium-shop');
    final currency = res['currency'] as String? ?? '₱';
    return (res['games'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((j) => ShopGame.fromJson({...j, 'currency': currency}))
        .toList();
  }

  /// One premium version with its gallery, description and details.
  static Future<ShopProduct> premiumProduct(int id) async {
    final res = await _api.get('/premium-shop/$id');
    final currency = res['currency'] as String? ?? '₱';
    final product =
        (res['product'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return ShopProduct.fromJson({...product, 'currency': currency});
  }

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
      // `availableCount` sa /products ay laging 0 (inilipat sa admin endpoint).
      final res = await _api.get(
        '/admin/keys',
        query: {'productId': productId, 'status': 'available', 'count': '1'},
      );
      return (res['total'] as num?)?.toInt() ?? 0;
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
        message: 'No key in the server response',
      );
    }
    return key;
  }

  static Future<({String url, String? sha256})> claimApp(
    String productId,
  ) async {
    final res = await _apiBackend.claim(productId);
    final url = res['downloadUrl'] as String?;
    if (url == null || url.trim().isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.conflict,
        message: 'This product has no download link yet.',
      );
    }
    return (url: url, sha256: res['sha256'] as String?);
  }

  static Future<bool> owns(String productId) async =>
      (await myClaims()).any((c) => c.productId == productId);

  /// Ticket-free: the Store only needs the id set, so no `/downloads/:id`
  /// request per owned product.
  static Future<Set<String>> ownedProductIds() async {
    if (await _session.accessToken() == null) return {};
    return _apiBackend.ownedProductIds();
  }

  // ---- history ----

  static Future<List<Claim>> myClaims() async {
    if (await _session.accessToken() == null) return [];
    // Failing the whole call beats returning [] — callers show an error with
    // Retry instead of "you own nothing".
    final raw = await _apiBackend.myClaims();
    // Download tickets in parallel — serial awaits made Purchases wait one
    // round-trip per download claim (N+1).
    final tickets = await Future.wait(
      raw.map((c) async {
        if (!c.isDownload) return null;
        try {
          return await _apiBackend.downloadTicket(c.productId);
        } on ApiException {
          return null;
        }
      }),
    );
    final out = <Claim>[];
    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      final ticket = tickets[i];
      out.add(_claim(c, ticket?.url ?? '', sha: ticket?.sha256 ?? c.sha256));
    }
    return out;
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

  // ---- announcements ----

  static Future<Announcement?> announcement() async {
    if (await _session.accessToken() == null) return null;
    try {
      return await _apiBackend.announcement();
    } on ApiException {
      return null; // a blip must not show a banner-shaped error
    }
  }

  static Future<bool> sendAnnouncement({
    required String title,
    required String body,
  }) => _apiBackend.sendAnnouncement(title: title, body: body);

  static Future<void> deleteAnnouncement(String id) =>
      _apiBackend.deleteAnnouncement(id);

  /// History list; a failure reads as "nothing to show", never an error screen.
  static Future<List<Announcement>> announcements() async {
    if (await _session.accessToken() == null) return [];
    try {
      return await _apiBackend.announcements();
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

  static Future<int> countKeys(
    String productId, {
    bool usedOnly = false,
  }) async {
    final rows = await _adminKeys(
      productId: productId,
      status: usedOnly ? 'claimed' : '',
    );
    return rows.length;
  }

  static Future<int> countAvailableKeys(
    String productId, {
    String duration = '',
  }) async {
    final rows = await _adminKeys(productId: productId, status: 'available');
    return duration.isEmpty
        ? rows.length
        : rows.where((k) => k.duration == duration).length;
  }

  static Future<List<StockEntry>> listKeys() => _adminKeys();

  static Future<List<StockEntry>> keysForProduct(
    String productId, {
    String duration = '',
    int limit = 5000,
  }) async {
    final rows = await _adminKeys(productId: productId, limit: limit);
    return duration.isEmpty
        ? rows
        : rows.where((k) => k.duration == duration).toList();
  }

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
    final res = await _api.post(
      '/products',
      data: {
        'name': name,
        'cost': cost,
        'description': description,
        'youtubeUrl': youtubeUrl,
        'type': type,
        'version': version,
        'fileSize': fileSize,
        if (imageIds.isNotEmpty) 'imageKeys': imageIds,
        if (durations.isNotEmpty) 'durations': _durations(durations),
      },
    );
    final id = res['id'] ?? (res['product'] as Map?)?['id'];
    if (id is! String || id.isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.badResponse,
        message: 'No id in the server response',
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
  }) => _api.patch(
    '/products/$productId',
    data: {
      'name': name,
      'cost': cost,
      'description': description,
      'youtubeUrl': youtubeUrl,
      'imageKeys': imageIds,
      'type': type,
      'version': version,
      'fileSize': fileSize,
      'durations': _durations(durations),
    },
  );

  static Future<void> setProductActive(String productId, bool active) =>
      _api.patch('/products/$productId', data: {'active': active});

  static Future<void> deleteProduct(String productId) =>
      _api.delete('/products/$productId');

  // ---- download link (admin) ----

  /// The stored link, for the admin form. Throws when it can't be read — an
  /// empty string would silently wipe a paid download on the next save.
  static Future<String> appFileFor(String productId) async {
    final p =
        (await _api.get('/products/$productId'))['product']
            as Map<String, dynamic>;
    return p['fileUrl'] as String? ?? '';
  }

  static Future<void> upsertAppFile(String productId, String url) async {
    final link = url.trim();
    if (link.isEmpty) return;
    await _api.patch('/products/$productId', data: {'fileUrl': link});
  }

  static Future<void> deleteAppFile(String productId) =>
      _api.patch('/products/$productId', data: {'fileUrl': ''});

  // ---- moderators (admin only) ----

  static Future<List<Map<String, dynamic>>> moderators() async {
    final res = await _api.get('/admin/moderators');
    final rows = (res['users'] as List?) ?? const [];
    return rows.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  static Future<void> promoteModerator(String userId) async {
    await _api.post('/admin/moderators/$userId');
  }

  static Future<void> demoteModerator(String userId) async {
    await _api.delete('/admin/moderators/$userId');
  }

  static Future<List<Map<String, dynamic>>> searchAdminUsers(
    String query,
  ) async {
    final res = await _api.get('/admin/users', query: {'search': query});
    final rows = (res['users'] as List?) ?? const [];
    return rows.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  // ---- images ----

  /// Images are links: an absolute URL, or a key the CDN will complete.
  static String imageUrl(String fileId, {int width = 900}) =>
      ApiConfig.publicUrl(fileId);

  static Future<void> deleteKey(String keyId) =>
      _api.delete('/admin/keys/$keyId');

  static Future<int> deleteKeysForProduct(
    String productId, {
    bool usedOnly = false,
    void Function(int done, int total)? onProgress,
  }) async {
    var total = 0;
    try {
      total = await countKeys(productId, usedOnly: usedOnly);
    } catch (_) {}
    onProgress?.call(0, total);
    await _api.delete(
      '/admin/products/$productId/keys',
      query: {if (usedOnly) 'status': 'claimed'},
    );
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

  static Claim _claim(ApiClaim c, String downloadUrl, {String? sha}) => Claim(
    id: c.id,
    productId: c.productId,
    productName: c.productName,
    keyText: c.keyText,
    cost: c.cost,
    createdAt: c.createdAt?.toIso8601String() ?? '',
    downloadUrl: downloadUrl,
    duration: c.duration,
    sha256: sha,
  );

  /// The admin UI still hands durations over as a JSON string.
  static List<Map<String, dynamic>> _durations(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final v = jsonDecode(raw);
      return v is List
          ? v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Scalars lang ang bumabalik sa JSON dito, pero hindi lahat string:
  /// `claimed_by` ay int na (users.id) mula noong app_users -> users merge.
  /// `.toString()` ang tamang coercion — `as String` ay nagta-throw at
  /// pinapatumba ang buong listahan.
  static String _pick(Map<String, dynamic> m, String camel, [String? snake]) {
    final v = m[camel] ?? (snake == null ? null : m[snake]);
    return v == null ? '' : v.toString();
  }
}
