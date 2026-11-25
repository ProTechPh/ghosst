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

  test('Reel parses creator, counts, flags, and optional metadata', () {
    final reel = Reel.fromJson({
      'id': 'r1',
      'caption': 'Hello',
      'videoUrl': 'https://example.com/r1.mp4',
      'posterUrl': 'https://example.com/r1.jpg',
      'durationMs': '1200',
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
    expect(reel.durationMs, 1200);
    expect(reel.likeCount, 3);
    expect(reel.commentCount, 2);
    expect(reel.isLiked, isTrue);
    expect(reel.isMine, isTrue);

    final missing = Reel.fromJson({
      'id': 'r2',
      'creator': {'id': '43'},
    });
    expect(missing.posterUrl, isNull);
    expect(missing.durationMs, isNull);
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
        },
        'bad',
      ],
      'nextOffset': '10',
    });
    expect(page.reels.map((reel) => reel.id), ['r1']);
    expect(page.nextOffset, 10);
  });

  test('ReelUploadTicket parses expiry and limits', () {
    final ticket = ReelUploadTicket.fromJson({
      'reel': {'id': 'r1', 'status': 'pending'},
      'upload': {
        'url': 'https://video.example/upload.php',
        'token': 'signed',
        'expiresAt': '2026-01-01T00:15:00.000Z',
        'maxBytes': '52428800',
      },
    });
    expect(ticket.reelId, 'r1');
    expect(ticket.uploadUrl, 'https://video.example/upload.php');
    expect(ticket.token, 'signed');
    expect(ticket.maxBytes, 52428800);
    expect(ticket.expiresAt.year, 2026);
  });
}
