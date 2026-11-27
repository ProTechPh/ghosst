import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/reels_screen.dart';
import 'package:ghosst/services/models.dart';

List<Reel> _posts(int n) => [
  for (var i = 0; i < n; i++)
    Reel(
      id: 'r$i',
      caption: '',
      createdAt: '',
      creator: const PublicUser(
        id: 'u',
        displayName: 'U',
        username: 'u',
        createdAt: '',
        followerCount: 0,
        followingCount: 0,
        reelCount: 0,
      ),
      likeCount: 0,
      commentCount: 0,
    ),
];

void main() {
  test('one slot exactly after the 5th post', () {
    final e = reelsFeedEntries(_posts(5), true);
    expect(e.length, 6);
    expect(e[4], isA<Reel>());
    expect(e[5], isA<ReelAdSlot>());
    expect((e[5] as ReelAdSlot).index, 0);
  });

  test('four posts produce no slot', () {
    final e = reelsFeedEntries(_posts(4), true);
    expect(e.length, 4);
    expect(e.whereType<ReelAdSlot>(), isEmpty);
  });

  test('disabled ads produce no slot', () {
    final e = reelsFeedEntries(_posts(10), false);
    expect(e.length, 10);
    expect(e.whereType<ReelAdSlot>(), isEmpty);
  });

  test('slots on two pages keep stable indices', () {
    final first = reelsFeedEntries(_posts(5), true);
    final second = reelsFeedEntries(_posts(10), true);
    expect(second.length, 12);
    expect(second[5], isA<ReelAdSlot>());
    expect(second[11], isA<ReelAdSlot>());
    expect(
      first.whereType<ReelAdSlot>().single.index,
      equals(second.whereType<ReelAdSlot>().first.index),
    );
    expect(second.whereType<ReelAdSlot>().map((s) => s.index).toList(), [0, 1]);
  });

  test('empty feed has no entries', () {
    expect(reelsFeedEntries(const [], true), isEmpty);
  });
}
