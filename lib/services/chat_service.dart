import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import 'worker_backend.dart';

/// Isang message sa world chat room.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.uid,
    required this.name,
    required this.text,
    required this.admin,
    required this.tsMillis,
    this.replyName,
    this.replyText,
  this.replyToId,
  });

  final String id;
  final String uid;
  final String name;
  final String text;
  final bool admin;
  final int tsMillis;

  /// Snapshot ng ni-re-reply-ang message (null = hindi reply). Ang pangalan
  /// ay maaaring '' (deleted user) — display-time na 'Deleted user'.
  final String? replyName;
  final String? replyText;
  final String? replyToId;
}

/// Ang surface na ginagamit ng [ChatScreen] — fake ito sa widget tests.
abstract class ChatClient {
  bool get ready;

  /// Invisible Firebase sign-in; false = chat unavailable.
  Future<bool> ensureSignedIn();

  /// True kapag may persisted Firebase session na (sync check, walang network).
  /// Kapag true, pwedeng mag-subscribe agad at i-validate sa background.
  bool get hasSession;

  /// Ang backend UUID ng naka-sign-in na user (null = wala pa).
  Future<String?> currentUid();

  /// True kapag ang kasalukuyang user ay naka-mute sa chat (token claim).
  Future<bool> isMuted();

  /// Binabasa ang totoong mute status mula sa backend (bypass ang `/me` cache)
  /// at nire-mint ulit ang token kung nagbago ang claim. Ginagamit pagbalik
  /// sa Chat tab at bago mag-send kapag naka-mute ang token — para hindi
  /// kakailanganin ng app restart para ma-reflect ang unmute (o mute).
  Future<bool> refreshMuted();

  /// Admin: i-mute/unmute ang isang user sa chat. `null` = ok; string = dahilan.
  Future<String?> setUserMuted(String uid, bool muted);

  /// Admin: ang listahan ng naka-mute (para sa dialog state + Admin screen).
  Future<List<MutedUser>> mutedUsers();

  Stream<List<ChatMessage>> messages();
  /// Kumuha ng mas lumang messages bago ang [beforeTsMillis] (pagination).
  Future<List<ChatMessage>> loadOlder(int beforeTsMillis);
  Future<String?> send(String text, {ChatMessage? replyTo});
  Future<void> signOut();
}

/// World chat: Firestore + Firebase custom-token session. Ang identity ay
/// ang backend UUID (mula sa PHP `/v1/firebase/token`), kaya walang Firebase
/// Auth UI — invisible sign-in lang. Fail-open: kapag hindi naka-setup o
/// offline, "Chat unavailable" lang ang tab, hindi nasisira ang app.
class ChatService implements ChatClient {
  static const Duration cooldown = Duration(seconds: 5);
  static const int _maxLength = 500;
  static const int _maxQuote = 200; // rules cap ng replyText
  static const int _pageSize = 50;

  static bool _ready = false;
  static bool _initStarted = false;
  static final Completer<bool> _startedCompleter = Completer<bool>();
  static DateTime? _lastSend;
  static Future<bool>? _inFlightSignIn;

  /// True kapag umandar na ang `Firebase.initializeApp()`.
  @override
  bool get ready => _ready;

  /// Completes kapag nasa-final ang init. Sa widget tests hindi tumatakbo
  /// ang `main()` — hindi ito matatapos, at fallback ang dapat irender.
  static Future<bool> get started => _startedCompleter.future;

  /// Isang beses lang: Android auto-init mula sa google-services.json, kaya
  /// walang arguments (walang firebase_options.dart sa Android-only app).
  static Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (e) {
      // Fail open, same policy as the launch gates.
      debugPrint('[ChatService] Firebase init failed: $e');
      _ready = false;
    }
    _startedCompleter.complete(_ready);
  }

  /// Invisible sign-in gamit ang custom token. Single-flight deduplicated:
  /// kung may tumatakbo nang sign-in sa background (e.g. mula sa HomeShell),
  /// iisang future lang ang hihintayin ng ChatScreen sa halip na magsabay.
  @override
  Future<bool> ensureSignedIn() {
    final existing = _inFlightSignIn;
    if (existing != null) return existing;
    return _inFlightSignIn = _ensureSignedInImpl().whenComplete(() {
      _inFlightSignIn = null;
    });
  }

  Future<bool> _ensureSignedInImpl() async {
    if (!_ready) return false;
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        // Parallelize: both read from the cached /me payload, but if it's
        // not cached yet they share the same single /me call internally.
        // Running them concurrently still saves the microtask overhead.
        final results = await Future.wait([
          Backend.isAdmin(),
          Backend.chatMuted(),
        ]);
        final isAdmin = results[0];
        final muted = results[1];
        Map<String, dynamic>? claims;
        try {
          claims = (await current.getIdTokenResult()).claims;
        } catch (_) {
          claims = null; // patay ang session — mint ulit sa baba
        }
        // Eksaktong tugma, hindi truthy: kulang na claim = kailangang i-mint ulit.
        if (claims != null && claims['admin'] == isAdmin && claims['muted'] == muted) {
          return true;
        }
      }
      final token = await Backend.firebaseToken();
      await FirebaseAuth.instance.signInWithCustomToken(token);
      return true;
    } catch (e) {
      debugPrint('[ChatService] sign-in failed: $e');
      return false;
    }
  }

  @override
  bool get hasSession {
    if (!_ready) return false;
    return FirebaseAuth.instance.currentUser != null;
  }

  /// Admin: lahat ng users na naka-mute sa world chat (para sa Admin screen).
  @override
  Future<List<MutedUser>> mutedUsers() async {
    try {
      return await Backend.mutedUsers();
    } on ApiException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Warm-up: itinatag ang Firestore connection (at auth) habang nasa
  /// splash/login pa ang user, para pagbukas ng Chat tab ay mabilis ang unang
  /// snapshot. Cache-first: kung may offline data na, basahin iyon (instant)
  /// para ma-prime ang snapshot. Kung wala, isang server read lang (limit 1).
  /// Isang read lang (limit 1) kada app start — negligible sa quota.
  /// Best-effort: anumang failure ay bale-wala.
  static Future<void> warm() async {
    if (!_ready) return;
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      // Try cache first — primes the snapshot listener so the first
      // messages() call returns instantly from cache while the server
      // round-trip runs in the background.
      try {
        await FirebaseFirestore.instance
            .collection('world_chat')
            .orderBy('ts', descending: true)
            .limit(1)
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        // No cache yet (first install) — fall through to server read.
        await FirebaseFirestore.instance.collection('world_chat').limit(1).get();
      }
    } catch (_) {
      // Warm lang ito — ang totoong boot ang magdedesisyon.
    }
  }

  /// Ang backend UUID ng kasalukuyang user — panukat ng "own" bubble
  /// (nasa kanan). Null kapag hindi pa naka-sign-in. Ang Firebase uid ng
  /// custom-token user AY ang backend UUID (ito ang ibinigay ng PHP), kaya
  /// walang /me call — zero network.
  @override
  Future<String?> currentUid() async {
    if (!_ready) return null;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  /// Ang `muted` claim ng kasalukuyang token (cached, walang network).
  /// Hindi na nag-fo-force refresh (`false`) — ang cached claims ay sapat
  /// para sa initial paint. Ang totoong status ay nire-refresh pagbalik sa
  /// tab (`_recheckMuted`) at bago mag-send.
  @override
  Future<bool> isMuted() async {
    if (!_ready) return false;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final claims = (await user.getIdTokenResult(false)).claims ?? const {};
      return claims['muted'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Ang totoong status ngayon + re-mint kung nagbago ang claim. Sa error
  /// (offline, PHP down) ay ibinabalik ang huling alam ng token — conservative:
  /// hindi magkukunwaring unmuted ang user dahil sa network blip.
  @override
  Future<bool> refreshMuted() async {
    if (!_ready) return false;
    try {
      final muted = await Backend.chatMuted(refresh: true);
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final claims = (await user.getIdTokenResult()).claims ?? const {};
        // Walang signOut — parehong uid ang mint, nire-re-auth lang ang stream.
        if (claims['muted'] != muted) {
          final token = await Backend.firebaseToken();
          await FirebaseAuth.instance.signInWithCustomToken(token);
        }
      }
      return muted;
    } catch (e) {
      debugPrint('[ChatService] refreshMuted failed: $e');
      try {
        final user = FirebaseAuth.instance.currentUser;
        final claims = (await user?.getIdTokenResult(true))?.claims ?? const {};
        return claims['muted'] == true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Admin-only moderation. Ang API ang nagvavalidate ng role; dito lang
  /// SnackBar-ready na string ang ibinabalik.
  @override
  Future<String?> setUserMuted(String uid, bool muted) async {
    try {
      await Backend.setChatMuted(uid, muted);
      return null;
    } on ApiException catch (e) {
      return e.userMessage;
    } catch (_) {
      return 'Could not update mute. Try again.';
    }
  }

  /// Pinakabagong 50 messages, live (Firestore cache = offline queueing).
  /// Gumagamit ng ServerTimestampBehavior.estimate para sa mga pending writes
  /// (lokal na naipadala pero naghihintay pa ng server timestamp) — kaya
  /// lalabas agad ang sariling chat bubble nang walang pagkaantala.
  @override
  Stream<List<ChatMessage>> messages() {
    if (!_ready) return const Stream<List<ChatMessage>>.empty();
    return FirebaseFirestore.instance
        .collection('world_chat')
        .orderBy('ts', descending: true)
        .limit(_pageSize)
        .snapshots()
        .map((snap) {
          final list = <ChatMessage>[];
          for (final doc in snap.docs) {
            final data = doc.data();
            final ts = data['ts'];
            final int tsMillis;
            if (ts is Timestamp) {
              tsMillis = ts.millisecondsSinceEpoch;
            } else if (doc.metadata.hasPendingWrites) {
              // Pending write: bago ma-compute ng Firestore server ang serverTimestamp,
              // gamitin ang local device time para lumabas agad ang chat bubble.
              tsMillis = DateTime.now().millisecondsSinceEpoch;
            } else {
              continue;
            }
            list.add(ChatMessage(
              id: doc.id,
              uid: data['uid'] as String? ?? '',
              name: data['name'] as String? ?? '',
              text: data['text'] as String? ?? '',
              admin: data['admin'] as bool? ?? false,
              tsMillis: tsMillis,
              replyName: data['replyName'] as String?,
              replyText: data['replyText'] as String?,
              replyToId: data['replyToId'] as String?,
            ));
          }
          return list;
        });
  }

  @override
  Future<List<ChatMessage>> loadOlder(int beforeTsMillis) async {
    if (!_ready) return const [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('world_chat')
          .orderBy('ts', descending: true)
          .startAfter([Timestamp.fromMillisecondsSinceEpoch(beforeTsMillis)])
          .limit(_pageSize)
          .get();
      return [
        for (final doc in snap.docs)
          if (doc.data()['ts'] is Timestamp)
            ChatMessage(
              id: doc.id,
              uid: doc.data()['uid'] as String? ?? '',
              name: doc.data()['name'] as String? ?? '',
              text: doc.data()['text'] as String? ?? '',
              admin: doc.data()['admin'] as bool? ?? false,
              tsMillis:
                  (doc.data()['ts'] as Timestamp).millisecondsSinceEpoch,
              replyName: doc.data()['replyName'] as String?,
              replyText: doc.data()['replyText'] as String?,
              replyToId: doc.data()['replyToId'] as String?,
            ),
      ];
    } catch (e) {
      debugPrint('[ChatService] loadOlder failed: $e');
      return const [];
    }
  }

  /// `null` = naipadala; string = dahilan kung bakit hindi. Validation at
  /// cooldown dito mismo (ang rules ay server-side na bantay pa rin).
  ///
  /// Optimized: ang mute check ay cached claims lang (walang forced refresh).
  /// Kung naka-mute ang cached claims, saka lang mag-refresh para i-confirm —
  /// ibig sabihin, para sa normal (hindi muted) na user, zero network overhead
  /// bago mag-Firestore write. Ang totoong enforcement ay nasa Firestore rules
  /// pa rin, kaya walang security risk.
  @override
  Future<String?> send(String text, {ChatMessage? replyTo}) async {
    final problem = validate(text);
    if (problem != null) return problem;

    final now = DateTime.now();
    if (!cooldownPassed(_lastSend, now)) {
      return 'Too fast — wait 5 seconds.';
    }
    _lastSend = now;

    try {
      // Quick check: kung wala pang Firebase user, sign in muna.
      // Kung meron na (normal case), skip ang buong ensureSignedIn() —
      // na-validate na ito sa boot time.
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) {
        if (!await ensureSignedIn()) return 'Chat unavailable';
      }

      // Mute check: cached claims lang (false = walang network).
      // Para sa karamihan ng users (hindi muted), zero-cost ito.
      // Kung naka-mute ang cached claim, saka lang i-refresh para i-confirm
      // na hindi pa na-unmute — isang network RT lang sa rare case.
      final cachedClaims =
          (await (FirebaseAuth.instance.currentUser
                  ?.getIdTokenResult(false)))
              ?.claims ?? const {};
      if (cachedClaims['muted'] == true) {
        // Baka na-unmute na — refresh ang totoong status.
        if (await refreshMuted()) {
          return 'You are muted in this chat.';
        }
      }

      // User data: laging cached pagkatapos ng boot, zero network.
      final user = await Backend.currentUser();
      if (user == null) return 'Not signed in';

      // isAdmin ay cached din — pinagsama na para walang extra await.
      final data = <String, Object?>{
        'uid': user.id,
        'name': fallbackName(user.name, user.id),
        'text': text.trim(),
        'admin': await Backend.isAdmin(),
        'ts': FieldValue.serverTimestamp(),
      };
      if (replyTo != null) {
        // Snapshot ng quote — hindi doc reference, kaya walang jump-to-message.
        data['replyName'] = replyTo.name;
        data['replyText'] =
            String.fromCharCodes(replyTo.text.runes.take(_maxQuote));
        data['replyToId'] = replyTo.id;
      }
      try {
        await FirebaseFirestore.instance
            .collection('world_chat')
            .add(data)
            .timeout(const Duration(seconds: 4));
      } on TimeoutException {
        // Ang mutation ay nasa local cache / offline queue na ng Firestore at
        // lalabas agad sa snapshot listener gamit ang ServerTimestampBehavior.estimate.
        // Kusang i-si-sync ito kapag stable ang koneksyon.
        debugPrint('[ChatService] add() server ack timed out — write queued in local cache');
      } catch (e) {
        if (replyTo != null) {
          // Fallback 1: Kung hindi pa updated ang Firestore rules sa Firebase console
          // (kulang ng `replyToId` sa hasOnly), tanggalin ang `replyToId` at subukan ulit.
          // Mananatili pa rin ang reply quote preview (replyName + replyText)!
          if (data.containsKey('replyToId')) {
            data.remove('replyToId');
            try {
              await FirebaseFirestore.instance
                  .collection('world_chat')
                  .add(data)
                  .timeout(const Duration(seconds: 4));
              return null;
            } on TimeoutException {
              debugPrint('[ChatService] retry without replyToId timed out — write queued');
              return null;
            } catch (_) {
              // Fallback 2: Tanggalin lahat ng reply fields kung lumang-luma pa ang rules
              data.remove('replyName');
              data.remove('replyText');
              try {
                await FirebaseFirestore.instance
                    .collection('world_chat')
                    .add(data)
                    .timeout(const Duration(seconds: 4));
                return null;
              } on TimeoutException {
                debugPrint('[ChatService] clean retry timed out — write queued');
                return null;
              }
            }
          } else {
            data.remove('replyName');
            data.remove('replyText');
            await FirebaseFirestore.instance
                .collection('world_chat')
                .add(data)
                .timeout(const Duration(seconds: 4));
            return null;
          }
        } else {
          rethrow;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[ChatService] send failed: $e');
      return 'Could not send — try again. ($e)';
    }
  }

  @override
  Future<void> signOut() async {
    _lastSend = null;
    _inFlightSignIn = null;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Hindi pa nag-init ang Firebase — wala namang session na aalisin.
    }
  }

  /// `null` = valid; string = dahilan. Sinasalamin ang Firestore rules.
  static String? validate(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Write a message.';
    if (t.length > _maxLength) return 'Maximum $_maxLength characters.';
    return null;
  }

  /// Display name kung meron; kung wala, `Anon-<unang 6 ng uid>` — stable,
  /// hindi PII. Blank name ('' lamang) ay scrub output ng deleted account.
  /// Naka-cap sa 40 (rules) para hindi permanenteng ma-reject ang send.
  static String fallbackName(String displayName, String uid) {
    final name = displayName.trim();
    if (name.isNotEmpty) {
      return String.fromCharCodes(name.runes.take(40));
    }
    final short = uid.length > 6 ? uid.substring(0, 6) : uid;
    return 'Anon-$short';
  }

  /// True kapag pwede nang mag-send (5s window).
  static bool cooldownPassed(DateTime? lastSend, DateTime now) {
    if (lastSend == null) return true;
    return now.difference(lastSend) >= cooldown;
  }
}
