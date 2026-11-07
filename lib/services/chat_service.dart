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

  /// Invisible sign-in gamit ang custom token. Nagre-mint kapag stale ang
  /// admin o muted claim (halimbawa, ginawang admin o na-mute ang account
  /// pagkatapos ng login). Ang `isAdmin` at `chatMuted` ay kukunin lang
  /// kapag may existing session na — sa bagong device (walang session) hindi
  /// sila ginagamit at isang /me round trip ang nasasayang kung maaga.
  /// Walang `signOut` dito: parehong uid ang mint, kaya ang Firestore stream
  /// ay nire-re-auth lang sa halip na maputol.
  @override
  Future<bool> ensureSignedIn() async {
    if (!_ready) return false;
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        final isAdmin = await Backend.isAdmin();
        final muted = await Backend.chatMuted();
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
  /// snapshot. Isang read lang (limit 1) kada app start — negligible sa quota.
  /// Best-effort: anumang failure ay bale-wala.
  static Future<void> warm() async {
    if (!_ready) return;
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
      await FirebaseFirestore.instance.collection('world_chat').limit(1).get();
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
  @override
  Future<bool> isMuted() async {
    if (!_ready) return false;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final claims = (await user.getIdTokenResult(true)).claims ?? const {};
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
  @override
  Stream<List<ChatMessage>> messages() {
    if (!_ready) return const Stream<List<ChatMessage>>.empty();
    return FirebaseFirestore.instance
        .collection('world_chat')
        .orderBy('ts', descending: true)
        .limit(_pageSize)
        .snapshots()
        .map((snap) => [
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
            ]);
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
      if (!await ensureSignedIn()) return 'Chat unavailable';
      // Kung naka-mute ang token, i-refresh ang totoong status muna — baka
      // na-unmute na ang user habang naka-bukas ang app (hindi kailangan ng
      // restart). Kung naka-mute pa rin, malinaw na dahilan ang ibalik.
      final fbUser = FirebaseAuth.instance.currentUser;
      var claimsMuted = false;
      if (fbUser != null) {
        final claims = (await fbUser.getIdTokenResult(true)).claims ?? const {};
        claimsMuted = claims['muted'] == true;
      }
      if (claimsMuted && await refreshMuted()) {
        return 'You are muted in this chat.';
      }
      final user = await Backend.currentUser();
      if (user == null) return 'Not signed in';
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
      await FirebaseFirestore.instance.collection('world_chat').add(data);
      return null;
    } catch (e) {
      debugPrint('[ChatService] send failed: $e');
      return 'Could not send — try again.';
    }
  }

  @override
  Future<void> signOut() async {
    _lastSend = null;
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
