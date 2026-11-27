import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';

void main() {
  test('PublicUser parses bio and cover from a profile payload', () {
    final user = PublicUser.fromJson({
      'id': 42,
      'bio': 'Official drops and updates.',
      'coverUrl': 'https://ghossthub.com/uploads/covers/a.jpg',
    });

    expect(user.bio, 'Official drops and updates.');
    expect(user.coverUrl, 'https://ghossthub.com/uploads/covers/a.jpg');
  });

  test('PublicUser resolves a relative cover key to an absolute URL', () {
    final user = PublicUser.fromJson({
      'id': 42,
      'coverUrl': 'uploads/covers/a.jpg',
    });

    expect(user.coverUrl, startsWith('https://'));
    expect(user.coverUrl, endsWith('uploads/covers/a.jpg'));
  });

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
      'likeCount': 9,
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
    expect(user.likeCount, 9);
    expect(user.isFollowing, isTrue);
    expect(user.isSelf, isFalse);
  });

  test('PublicUser uses safe defaults for missing fields', () {
    final user = PublicUser.fromJson({'id': '42'});

    expect(user.id, '42');
    expect(user.displayName, 'Member #42');
    expect(user.username, '');
    expect(user.avatarUrl, isNull);
    expect(user.bio, '');
    expect(user.coverUrl, isNull);
    expect(user.createdAt, '');
    expect(user.followerCount, 0);
    expect(user.followingCount, 0);
    expect(user.reelCount, 0);
    expect(user.likeCount, 0);
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

  test('AppFeedback parses complete and missing fields', () {
    final complete = AppFeedback.fromJson({
      'id': 7,
      'comment': 'Great app',
      'rating': '5',
      'status': 'hidden',
      'createdAt': '2026-01-01T00:00:00.000Z',
    });
    expect(complete.id, '7');
    expect(complete.comment, 'Great app');
    expect(complete.rating, 5);
    expect(complete.status, 'hidden');
    expect(complete.createdAt, '2026-01-01T00:00:00.000Z');

    final missing = AppFeedback.fromJson({'id': '8'});
    expect(missing.comment, '');
    expect(missing.rating, 0);
    expect(missing.status, 'hidden');
    expect(missing.createdAt, '');
  });

  test('validateAppFeedback mirrors the server limits', () {
    expect(validateAppFeedback('x' * 9, 5), isNotNull);
    expect(validateAppFeedback('x' * 10, 5), isNull);
    expect(validateAppFeedback('x' * 1000, 1), isNull);
    expect(validateAppFeedback('x' * 1001, 1), isNotNull);
    expect(validateAppFeedback('Valid feedback', 0), isNotNull);
    expect(validateAppFeedback('Valid feedback', 6), isNotNull);
    expect(validateAppFeedback('<script>bad</script>', 5), isNotNull);
  });

  test('FollowState parses flags and counts safely', () {
    final complete = FollowState.fromJson({
      'isFollowing': true,
      'followerCount': '12',
    });
    expect(complete.isFollowing, isTrue);
    expect(complete.followerCount, 12);

    final missing = FollowState.fromJson({
      'isFollowing': 'yes',
      'followerCount': 'oops',
    });
    expect(missing.isFollowing, isFalse);
    expect(missing.followerCount, 0);
  });

  test('publicUsersFromJson skips malformed entries', () {
    final users = publicUsersFromJson([
      {'id': 42, 'displayName': 'Jeric'},
      'bad',
      null,
      {'id': '43', 'displayName': 'Peer'},
    ]);
    expect(users.map((user) => user.id), ['42', '43']);
  });

  test('Reel parses ordered images, poster, creator, counts, and flags', () {
    final reel = Reel.fromJson({
      'id': 'r1',
      'caption': 'Hello',
      'posterUrl': 'https://example.com/r1-1.jpg',
      'images': [
        {
          'position': 2,
          'url': 'https://example.com/r1-2.jpg',
          'sha256': 'b' * 64,
          'sizeBytes': 20,
          'mimeType': 'image/png',
        },
        {
          'position': 1,
          'url': 'https://example.com/r1-1.jpg',
          'sha256': 'a' * 64,
          'sizeBytes': 10,
          'mimeType': 'image/jpeg',
        },
      ],
      'createdAt': '2026-01-01T00:00:00.000Z',
      'creator': {'id': 42, 'displayName': 'Jeric'},
      'likeCount': '3',
      'commentCount': 2,
      'isLiked': true,
      'isFollowing': false,
      'isMine': true,
    });
    expect(reel.id, 'r1');
    expect(reel.caption, 'Hello');
    expect(reel.creator.id, '42');
    expect(reel.images.map((i) => i.position), [1, 2]);
    expect(reel.images.first.url, 'https://example.com/r1-1.jpg');
    expect(reel.posterUrl, 'https://example.com/r1-1.jpg');
    expect(reel.likeCount, 3);
    expect(reel.commentCount, 2);
    expect(reel.isLiked, isTrue);
    expect(reel.isMine, isTrue);

    final missing = Reel.fromJson({
      'id': 'r2',
      'creator': {'id': '43'},
    });
    expect(missing.images, isEmpty);
    expect(missing.posterUrl, isNull);
    expect(missing.likeCount, 0);
  });

  test('ReelComment and ReelFeedPage parse safely', () {
    final comment = ReelComment.fromJson({
      'id': 'c1',
      'text': 'Nice',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'user': {'id': 42, 'displayName': 'Jeric'},
    });
    expect(comment.text, 'Nice');
    expect(comment.user.id, '42');

    final page = ReelFeedPage.fromJson({
      'reels': [
        {
          'id': 'r1',
          'creator': {'id': 42},
          'images': [
            {'position': 1, 'url': 'https://example.com/r1-1.jpg'},
          ],
        },
        'bad',
      ],
      'nextOffset': '10',
    });
    expect(page.reels.map((reel) => reel.id), ['r1']);
    expect(page.nextOffset, 10);
  });

  test('ReelUploadTicket parses per-image tickets', () {
    final ticket = ReelUploadTicket.fromJson({
      'reel': {'id': 'r1', 'status': 'pending'},
      'uploads': [
        {
          'position': 1,
          'url': 'https://z.example/upload.php',
          'token': 't1',
          'expiresAt': '2026-01-01T00:15:00.000Z',
          'maxBytes': '10485760',
          'sha256': 'a' * 64,
          'storageKey': 'r1-1.jpg',
        },
      ],
    });
    expect(ticket.reelId, 'r1');
    expect(ticket.uploads.single.position, 1);
    expect(ticket.uploads.single.uploadUrl, 'https://z.example/upload.php');
    expect(ticket.uploads.single.maxBytes, 10485760);
    expect(ticket.expiresAt.year, 2026);
  });
}
