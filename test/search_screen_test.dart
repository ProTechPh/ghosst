import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/search_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

Reel _reel() => Reel(
  id: 'r1',
  caption: 'Nice bike',
  posterUrl: 'https://example.com/reel.jpg',
  images: [
    ReelImage(
      position: 1,
      url: 'https://example.com/reel.jpg',
      sha256: 'a' * 64,
      sizeBytes: 1,
      mimeType: 'image/jpeg',
    ),
  ],
  createdAt: '2026-11-27T10:00:00Z',
  creator: PublicUser(
    id: '7',
    displayName: 'Juan',
    username: 'juan',
    createdAt: '',
    followerCount: 0,
    followingCount: 0,
    reelCount: 0,
  ),
  likeCount: 5,
  commentCount: 2,
);

Widget _harness({
  required Future<List<ChatUserSummary>> Function(String) searchUsers,
  required Future<List<Reel>> Function(String) searchReels,
  ValueChanged<String>? onOpenProfile,
  ValueChanged<Reel>? onOpenReel,
}) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: Builder(
      builder: (context) => Column(
        children: [
          const Text('root-screen'),
          ElevatedButton(
            key: const ValueKey('open-search'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SearchScreen(
                  searchUsers: searchUsers,
                  searchReels: searchReels,
                  onOpenProfile: onOpenProfile,
                  onOpenReel: onOpenReel,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-search')));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('search-input')), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one character performs no search', (tester) async {
    var users = 0;
    var reels = 0;
    await tester.pumpWidget(_harness(
      searchUsers: (q) async {
        users++;
        return const [];
      },
      searchReels: (q) async {
        reels++;
        return const [];
      },
    ));
    await _open(tester);
    await _type(tester, 'a');

    expect(users, 0);
    expect(reels, 0);
    expect(find.byKey(const ValueKey('search-no-users')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-no-reels')), findsOneWidget);
  });

  testWidgets('two characters render users and reels', (tester) async {
    await tester.pumpWidget(_harness(
      searchUsers: (q) async => [
        ChatUserSummary(id: '7', name: 'Juan'),
      ],
      searchReels: (q) async => [_reel()],
    ));
    await _open(tester);
    await _type(tester, 'ju');

    expect(find.byKey(const ValueKey('search-user-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-reel-r1')), findsOneWidget);
  });

  testWidgets('failed reel search keeps user results', (tester) async {
    var users = 0;
    var reels = 0;
    var failReels = true;
    await tester.pumpWidget(_harness(
      searchUsers: (q) async {
        users++;
        return [ChatUserSummary(id: '7', name: 'Juan')];
      },
      searchReels: (q) async {
        reels++;
        if (failReels) throw StateError('offline');
        return [_reel()];
      },
    ));
    await _open(tester);
    await _type(tester, 'ju');

    expect(find.byKey(const ValueKey('search-user-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-reels-error')), findsOneWidget);
    failReels = false;
    await tester.tap(find.byKey(const ValueKey('search-reels-retry')));
    await tester.pumpAndSettle();

    expect(reels, 2);
    expect(users, 1);
    expect(find.byKey(const ValueKey('search-reel-r1')), findsOneWidget);
  });

  testWidgets('tapping a result pops search and opens the target', (
    tester,
  ) async {
    String? openedUser;
    await tester.pumpWidget(_harness(
      searchUsers: (q) async => [
        ChatUserSummary(id: '7', name: 'Juan'),
      ],
      searchReels: (q) async => [_reel()],
      onOpenProfile: (id) => openedUser = id,
    ));
    await _open(tester);
    await _type(tester, 'ju');

    await tester.tap(find.byKey(const ValueKey('search-user-7')));
    await tester.pumpAndSettle();

    expect(openedUser, '7');
    expect(find.text('root-screen'), findsOneWidget);
  });
}
