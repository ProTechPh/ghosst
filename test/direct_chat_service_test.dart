import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/direct_chat_service.dart';
import 'package:ghosst/services/models.dart';

void main() {
  group('direct thread identity', () {
    test('is deterministic regardless of participant order', () {
      expect(directThreadId('2', '10'), directThreadId('10', '2'));
      expect(directThreadId('2', '10'), '10__2');
    });

    test('rejects empty ids', () {
      expect(() => directThreadId('', '10'), throwsArgumentError);
      expect(() => directThreadId('10', ''), throwsArgumentError);
    });

    test('rejects a self thread', () {
      expect(() => directThreadId('10', '10'), throwsArgumentError);
    });
  });

  group('validateDirectMessage', () {
    test('rejects empty and whitespace-only text', () {
      expect(validateDirectMessage(''), isNotNull);
      expect(validateDirectMessage('   \n'), isNotNull);
    });

    test('rejects text longer than 500 characters', () {
      expect(validateDirectMessage('x' * 501), isNotNull);
    });

    test('accepts exactly 500 characters and trims valid text', () {
      expect(validateDirectMessage('x' * 500), isNull);
      expect(validateDirectMessage('  ok  '), isNull);
    });

    test('counts emoji as characters rather than UTF-16 units', () {
      expect(validateDirectMessage('😀' * 500), isNull);
      expect(validateDirectMessage('😀' * 501), isNotNull);
    });
  });

  group('directCooldownPassed', () {
    final now = DateTime(2026, 11, 25, 12);

    test('allows the first send', () {
      expect(directCooldownPassed(null, now), isTrue);
    });

    test('rejects a rapid send', () {
      expect(
        directCooldownPassed(now, now.add(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('allows a send after two seconds', () {
      expect(
        directCooldownPassed(now, now.add(const Duration(seconds: 2))),
        isTrue,
      );
    });
  });

  group('ChatUserSummary.fromJson', () {
    test('maps safe public fields and string ids', () {
      final user = ChatUserSummary.fromJson({
        'id': 42,
        'displayName': 'Jeric',
        'username': 'jeric',
        'avatarUrl': 'https://example.com/a.jpg',
        'isAdmin': true,
        'isModerator': false,
        'email': 'private@example.com',
      });
      expect(user.id, '42');
      expect(user.name, 'Jeric');
      expect(user.avatarUrl, 'https://example.com/a.jpg');
    });

    test('falls back to username and initials-safe empty avatar', () {
      final user = ChatUserSummary.fromJson({
        'id': '42',
        'displayName': '',
        'username': 'jeric',
      });
      expect(user.name, 'jeric');
      expect(user.avatarUrl, isNull);
    });
  });

  group('DirectThread.fromMap', () {
    test('parses timestamps, participants, and unread state', () {
      final thread = DirectThread.fromMap('10__2', {
        'participants': ['10', '2'],
        'lastMessage': 'hello',
        'lastMessageAt': Timestamp.fromMillisecondsSinceEpoch(2000),
        'lastSenderId': '2',
        'lastReadAt': {'10': Timestamp.fromMillisecondsSinceEpoch(1000)},
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(500),
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(2000),
      });
      expect(thread.id, '10__2');
      expect(thread.peerId('10'), '2');
      expect(thread.isUnread('10'), isTrue);
      expect(thread.isUnread('2'), isFalse);
    });

    test('a missing read marker means unread for the peer', () {
      final thread = DirectThread.fromMap('10__2', {
        'participants': ['10', '2'],
        'lastMessage': 'hello',
        'lastMessageAt': Timestamp.fromMillisecondsSinceEpoch(2000),
        'lastSenderId': '2',
        'lastReadAt': <String, dynamic>{},
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(500),
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(2000),
      });
      expect(thread.isUnread('10'), isTrue);
    });
  });

  group('DirectMessage.fromMap', () {
    test('parses sender, text, and timestamp', () {
      final message = DirectMessage.fromMap('m1', {
        'senderId': '10',
        'text': 'hello',
        'ts': Timestamp.fromMillisecondsSinceEpoch(1234),
      });
      expect(message.id, 'm1');
      expect(message.senderId, '10');
      expect(message.text, 'hello');
      expect(message.tsMillis, 1234);
    });
  });
}
