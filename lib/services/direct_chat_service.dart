import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'chat_service.dart';
import 'worker_backend.dart';

const _dmMaxLength = 500;
const _dmPageSize = 50;
const dmCooldown = Duration(seconds: 2);

String directThreadId(String uidA, String uidB) {
  final a = uidA.trim();
  final b = uidB.trim();
  if (a.isEmpty || b.isEmpty) throw ArgumentError('DM ids cannot be empty');
  if (a == b) throw ArgumentError('A DM needs two different users');
  return a.compareTo(b) <= 0 ? '${a}__$b' : '${b}__$a';
}

String? validateDirectMessage(String text) {
  final value = text.trim();
  if (value.isEmpty) return 'Write a message.';
  if (value.runes.length > _dmMaxLength) {
    return 'Maximum $_dmMaxLength characters.';
  }
  return null;
}

bool directCooldownPassed(DateTime? lastSend, DateTime now) {
  if (lastSend == null) return true;
  return now.difference(lastSend) >= dmCooldown;
}

int _timestampMillis(Object? value) {
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

class DirectThread {
  const DirectThread({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastSenderId,
    required this.lastReadAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final List<String> participants;
  final String lastMessage;
  final int lastMessageAt;
  final String lastSenderId;
  final Map<String, int> lastReadAt;
  final int createdAt;
  final int updatedAt;

  String peerId(String myId) {
    for (final id in participants) {
      if (id != myId) return id;
    }
    return '';
  }

  bool isUnread(String myId) =>
      lastSenderId != myId && lastMessageAt > (lastReadAt[myId] ?? 0);

  factory DirectThread.fromMap(String id, Map<String, dynamic> data) {
    final reads = <String, int>{};
    final rawReads = data['lastReadAt'];
    if (rawReads is Map) {
      for (final entry in rawReads.entries) {
        if (entry.key is String) {
          reads[entry.key as String] = _timestampMillis(entry.value);
        }
      }
    }
    return DirectThread(
      id: id,
      participants: (data['participants'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageAt: _timestampMillis(data['lastMessageAt']),
      lastSenderId: data['lastSenderId'] as String? ?? '',
      lastReadAt: Map.unmodifiable(reads),
      createdAt: _timestampMillis(data['createdAt']),
      updatedAt: _timestampMillis(data['updatedAt']),
    );
  }
}

class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.tsMillis,
  });

  final String id;
  final String senderId;
  final String text;
  final int tsMillis;

  factory DirectMessage.fromMap(String id, Map<String, dynamic> data) =>
      DirectMessage(
        id: id,
        senderId: data['senderId'] as String? ?? '',
        text: data['text'] as String? ?? '',
        tsMillis: _timestampMillis(data['ts']),
      );
}

abstract class DirectChatClient {
  Stream<List<DirectThread>> threads();
  Stream<List<DirectMessage>> messages(String threadId);
  Future<String?> send(String threadId, String text);
  Future<void> markRead(String threadId);
  Future<bool> isBlocked(String uid);
  Future<void> block(String uid);
  Future<void> unblock(String uid);
  Future<bool> ensureSignedIn();
  Future<void> signOut();
}

class DirectChatService implements DirectChatClient {
  static DateTime? _lastSend;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  Future<bool> ensureSignedIn() async {
    final user = await Backend.currentUser();
    if (user == null) {
      await signOut();
      return false;
    }
    return ChatService().ensureSignedIn();
  }

  Future<String?> _uid() async {
    if (!await ChatService.started) return null;
    if (!await ensureSignedIn()) return null;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  bool _validThreadFor(String threadId, String uid) {
    final parts = threadId.split('__');
    if (parts.length != 2 || parts.contains(uid) == false) return false;
    return directThreadId(parts[0], parts[1]) == threadId;
  }

  @override
  Stream<List<DirectThread>> threads() async* {
    final uid = await _uid();
    if (uid == null) return;
    yield* _db
        .collection('direct_threads')
        .where('participants', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .limit(_dmPageSize)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snap) => [
            for (final doc in snap.docs)
              DirectThread.fromMap(doc.id, doc.data()),
          ],
        );
  }

  @override
  Stream<List<DirectMessage>> messages(String threadId) async* {
    final uid = await _uid();
    if (uid == null || !_validThreadFor(threadId, uid)) return;
    yield* _db
        .collection('direct_threads')
        .doc(threadId)
        .collection('messages')
        .orderBy('ts', descending: true)
        .limit(_dmPageSize)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snap) => [
            for (final doc in snap.docs)
              DirectMessage.fromMap(doc.id, doc.data()),
          ],
        );
  }

  @override
  Future<String?> send(String threadId, String text) async {
    final invalid = validateDirectMessage(text);
    if (invalid != null) return invalid;
    final uid = await _uid();
    if (uid == null) return 'Chat unavailable';
    if (!_validThreadFor(threadId, uid)) return 'Invalid conversation';

    final now = DateTime.now();
    if (!directCooldownPassed(_lastSend, now)) {
      return 'Wait a moment before sending';
    }
    if (await isBlocked(threadId.split('__').firstWhere((id) => id != uid))) {
      return 'You blocked this user';
    }

    final clean = text.trim();
    final threadRef = _db.collection('direct_threads').doc(threadId);
    final messageRef = threadRef.collection('messages').doc();
    try {
      final existing = await threadRef.get();
      if (existing.exists) {
        final participants =
            (existing.data()?['participants'] as List? ?? const [])
                .whereType<String>()
                .toList();
        if (!participants.contains(uid) || participants.length != 2) {
          return 'Invalid conversation';
        }
      }

      // Batched writes queue offline; a transaction would require the network.
      final batch = _db.batch();
      batch.set(messageRef, {
        'senderId': uid,
        'text': clean,
        'ts': FieldValue.serverTimestamp(),
      });
      if (existing.exists) {
        batch.set(threadRef, {
          'lastMessage': clean,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastSenderId': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        batch.set(threadRef, {
          'participants': threadId.split('__'),
          'lastMessage': clean,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastSenderId': uid,
          'lastReadAt': {uid: FieldValue.serverTimestamp()},
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit().timeout(const Duration(seconds: 4));
      _lastSend = now;
      return null;
    } on TimeoutException {
      _lastSend = now;
      debugPrint('[DirectChatService] send queued locally after ack timeout');
      return null;
    } catch (e) {
      debugPrint('[DirectChatService] send failed: $e');
      return 'Could not send — try again.';
    }
  }

  @override
  Future<void> markRead(String threadId) async {
    final uid = await _uid();
    if (uid == null || !_validThreadFor(threadId, uid)) return;
    await _db.collection('direct_threads').doc(threadId).update({
      'lastReadAt.$uid': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  DocumentReference<Map<String, dynamic>> _blockDoc(String uid) => _db
      .collection('user_blocks')
      .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
      .collection('blocked')
      .doc(uid);

  @override
  Future<bool> isBlocked(String uid) async {
    final myId = await _uid();
    if (myId == null || uid.isEmpty || uid == myId) return false;
    return (await _blockDoc(uid).get()).exists;
  }

  @override
  Future<void> block(String uid) async {
    final myId = await _uid();
    if (myId == null || uid.isEmpty || uid == myId) return;
    await _blockDoc(uid).set({'createdAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> unblock(String uid) async {
    final myId = await _uid();
    if (myId == null || uid.isEmpty || uid == myId) return;
    await _blockDoc(uid).delete();
  }

  @override
  Future<void> signOut() async {
    _lastSend = null;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Firebase may not be initialized yet.
    }
  }
}
