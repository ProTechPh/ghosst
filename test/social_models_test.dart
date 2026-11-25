import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';

void main() {
  test('PublicUser parses a complete safe profile', () {
    final user = PublicUser.fromJson({
      'id': 42,
      'displayName': 'Jeric',
      'username': 'jeric',
      'avatarUrl': 'https://lh3.googleusercontent.com/a/example',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'isAdmin': true,
      'isModerator': false,
      'followerCount': 12,
      'followingCount': 7,
      'reelCount': 3,
      'isFollowing': true,
      'isSelf': false,
      'email': 'private@example.com',
      'balance': 999,
      'password': 'secret',
    });

    expect(user.id, '42');
    expect(user.displayName, 'Jeric');
    expect(user.username, 'jeric');
    expect(user.avatarUrl, 'https://lh3.googleusercontent.com/a/example');
    expect(user.createdAt, '2026-01-01T00:00:00.000Z');
    expect(user.isAdmin, isTrue);
    expect(user.isModerator, isFalse);
    expect(user.followerCount, 12);
    expect(user.followingCount, 7);
    expect(user.reelCount, 3);
    expect(user.isFollowing, isTrue);
    expect(user.isSelf, isFalse);
  });

  test('PublicUser uses safe defaults for missing fields', () {
    final user = PublicUser.fromJson({'id': '42'});

    expect(user.id, '42');
    expect(user.displayName, 'Member #42');
    expect(user.username, '');
    expect(user.avatarUrl, isNull);
    expect(user.createdAt, '');
    expect(user.followerCount, 0);
    expect(user.followingCount, 0);
    expect(user.reelCount, 0);
    expect(user.isFollowing, isFalse);
    expect(user.isSelf, isFalse);
  });

  test('PublicUser tolerates malformed counts and string ids', () {
    final user = PublicUser.fromJson({
      'id': 42,
      'followerCount': 'oops',
      'followingCount': '9',
      'reelCount': null,
    });

    expect(user.id, '42');
    expect(user.followerCount, 0);
    expect(user.followingCount, 9);
    expect(user.reelCount, 0);
  });
}
