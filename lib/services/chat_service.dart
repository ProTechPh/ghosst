import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'worker_backend.dart';

/// Isang message sa world chat room.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.uid,
    required this.name,
    required this.text,
    required this.admin,
    required this.tsMillis,
  });

  final String uid;
  final String name;
  final String text;
  final bool admin;
  final int tsMillis;
}

/// Ang surface na ginagamit ng [ChatScreen] — fake ito sa widget tests.
abstract class ChatClient {
  bool get ready;

  /// Invisible Firebase sign-in; false = chat unavailable.
  Future<bool> ensureSignedIn();

  Stream<List<ChatMessage>> messages();
  Future<String?> send(String text);
  Future<void> signOut();
}

/// World chat: Firestore + Firebase custom-token session. Ang identity ay
/// ang backend UUID (mula sa PHP `/v1/firebase/token`), kaya walang Firebase
/// Auth UI — invisible sign-in lang. Fail-open: kapag hindi naka-setup o
/// offline, "Chat unavailable" lang ang tab, hindi nasisira ang app.
class ChatService implements ChatClient {
  static const Duration cooldown = Duration(seconds: 5);
  static const int _maxLength = 500;
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
  /// admin claim (halimbawa, ginawang admin ang account pagkatapos ng login).
  @override
  Future<bool> ensureSignedIn() async {
    if (!_ready) return false;
    try {
      final isAdmin = await Backend.isAdmin();
      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        final claims = (await current.getIdTokenResult()).claims ?? const {};
        if ((claims['admin'] == true) == isAdmin) return true;
        await FirebaseAuth.instance.signOut();
      }
      final token = await Backend.firebaseToken();
      await FirebaseAuth.instance.signInWithCustomToken(token);
      return true;
    } catch (e) {
      debugPrint('[ChatService] sign-in failed: $e');
      return false;
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
                    uid: doc.data()['uid'] as String? ?? '',
                    name: doc.data()['name'] as String? ?? '',
                    text: doc.data()['text'] as String? ?? '',
                    admin: doc.data()['admin'] as bool? ?? false,
                    tsMillis:
                        (doc.data()['ts'] as Timestamp).millisecondsSinceEpoch,
                  ),
            ]);
  }

  /// `null` = naipadala; string = dahilan kung bakit hindi. Validation at
  /// cooldown dito mismo (ang rules ay server-side na bantay pa rin).
  @override
  Future<String?> send(String text) async {
    final problem = validate(text);
    if (problem != null) return problem;

    final now = DateTime.now();
    if (!cooldownPassed(_lastSend, now)) {
      return 'Masyadong mabilis — maghintay ng 5 segundo.';
    }
    _lastSend = now;

    try {
      if (!await ensureSignedIn()) return 'Chat unavailable';
      final user = await Backend.currentUser();
      if (user == null) return 'Not signed in';
      await FirebaseFirestore.instance.collection('world_chat').add({
        'uid': user.id,
        'name': fallbackName(user.name, user.id),
        'text': text.trim(),
        'admin': await Backend.isAdmin(),
        'ts': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      debugPrint('[ChatService] send failed: $e');
      return 'Hindi naipadala — subukan ulit.';
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
    if (t.isEmpty) return 'Magsulat ng mensahe.';
    if (t.length > _maxLength) return 'Hanggang $_maxLength characters lang.';
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
