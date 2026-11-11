import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'worker_backend.dart';

/// Read markers for the tab badges.
///
/// The API (`/v1/reads`) owns the account's markers so they are shared by
/// every device; this class keeps a local copy for an instant first paint and
/// for offline launches. Marks are monotonic — a marker never moves backwards,
/// so an out-of-order request from another device cannot resurrect old unread.
class ReadStore {
  static final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _kAnnouncementsSeenAt = 'ghosst.announcements.seenAt';
  static const String _kChatSeenAt = 'ghosst.chat.seenAt';

  /// Newest `createdAt` the user has opened the News tab with. Empty = none.
  static Future<String> announcementsSeenAt() async {
    try {
      return await _storage.read(key: _kAnnouncementsSeenAt) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Newest chat message ts (ms) the user has seen. 0 = none.
  static Future<int> chatSeenAtMs() async {
    try {
      return int.tryParse(await _storage.read(key: _kChatSeenAt) ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> markAnnouncementsSeen(String createdAt) async {
    if (createdAt.isEmpty) return;
    await _writeAnnouncements(createdAt);
    unawaited(Backend.markReads(announcementsSeenAt: createdAt));
  }

  static Future<void> markChatSeen(int tsMillis) async {
    if (tsMillis <= 0) return;
    await _writeChat(tsMillis);
    unawaited(Backend.markReads(chatSeenAtMs: tsMillis));
  }

  /// Pulls the account's markers, merges them with the local copy (newest
  /// wins), and pushes anything the server is behind on. Returns the effective
  /// announcements marker for the unread count. Never throws.
  static Future<String> sync() async {
    final localAnn = await announcementsSeenAt();
    final localChat = await chatSeenAtMs();

    final remote = await Backend.reads();
    if (remote == null) return localAnn;

    var ann = localAnn;
    if (remote.announcementsSeenAt.compareTo(ann) > 0) {
      ann = remote.announcementsSeenAt;
      await _writeAnnouncements(ann);
    } else if (ann.compareTo(remote.announcementsSeenAt) > 0) {
      unawaited(Backend.markReads(announcementsSeenAt: ann));
    }

    if (remote.chatSeenAtMs > localChat) {
      await _writeChat(remote.chatSeenAtMs);
    } else if (localChat > remote.chatSeenAtMs) {
      unawaited(Backend.markReads(chatSeenAtMs: localChat));
    }

    return ann;
  }

  static Future<void> _writeAnnouncements(String value) async {
    try {
      await _storage.write(key: _kAnnouncementsSeenAt, value: value);
    } catch (_) {
      // Storage unavailable (tests, locked ROM) — the server copy still holds.
    }
  }

  static Future<void> _writeChat(int value) async {
    try {
      await _storage.write(key: _kChatSeenAt, value: '$value');
    } catch (_) {
      // Storage unavailable — the server copy still holds.
    }
  }
}
